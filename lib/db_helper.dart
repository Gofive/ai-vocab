import 'dart:io';
import 'package:ai_vocab/models/study_settings.dart';
import 'package:ai_vocab/models/word_model.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';

class DBHelper {
  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    String path;
    DatabaseFactory factory;

    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      factory = databaseFactoryFfi;
      final documentsDirectory = await getApplicationDocumentsDirectory();
      path = join(documentsDirectory.path, "vocab.db");
    } else {
      factory = databaseFactory;
      path = join(await getDatabasesPath(), "vocab.db");
    }

    final file = File(path);

    // 检查数据库版本，如果 assets 更新了则重新复制
    final assetData = await rootBundle.load("assets/vocab.db");
    final assetSize = assetData.lengthInBytes;

    bool needCopy = !await file.exists();
    if (!needCopy && await file.exists()) {
      final fileSize = await file.length();
      // 如果文件大小不同，说明 assets 更新了
      needCopy = fileSize != assetSize;
    }

    if (needCopy) {
      await Directory(dirname(path)).create(recursive: true);
      List<int> bytes = assetData.buffer.asUint8List(
        assetData.offsetInBytes,
        assetData.lengthInBytes,
      );
      await file.writeAsBytes(bytes, flush: true);
    }

    final db = await factory.openDatabase(path);
    await _ensureProgressTable(db);
    return db;
  }

  /// 确保学习进度表存在
  Future<void> _ensureProgressTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS study_progress (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        dict_name TEXT UNIQUE NOT NULL,
        learned_count INTEGER DEFAULT 0,
        daily_words INTEGER DEFAULT 20,
        study_mode INTEGER DEFAULT 0,
        last_study_time TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS word_progress (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_id INTEGER NOT NULL,
        dict_name TEXT NOT NULL,
        is_learned INTEGER DEFAULT 0,
        learn_time TEXT,
        UNIQUE(word_id, dict_name)
      )
    ''');
  }

  /// 获取所有词典列表
  Future<List<Map<String, dynamic>>> getDictList() async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT d.name, COUNT(rel.word_id) as word_count
      FROM dictionaries d
      LEFT JOIN word_dict_rel rel ON d.id = rel.dict_id
      GROUP BY d.id
      ORDER BY d.name
    ''');
    return results;
  }

  /// 获取词典学习进度
  Future<DictProgress> getDictProgress(String dictName) async {
    final db = await database;

    // 获取词典总词数
    final countResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as total FROM words w
      JOIN word_dict_rel rel ON w.id = rel.word_id
      JOIN dictionaries d ON rel.dict_id = d.id
      WHERE d.name = ?
    ''',
      [dictName],
    );
    final totalCount = countResult.first['total'] as int;

    // 获取学习进度
    final progressResult = await db.query(
      'study_progress',
      where: 'dict_name = ?',
      whereArgs: [dictName],
    );

    if (progressResult.isEmpty) {
      return DictProgress(
        dictName: dictName,
        totalCount: totalCount,
        settings: const StudySettings(),
      );
    }

    final row = progressResult.first;
    return DictProgress(
      dictName: dictName,
      learnedCount: row['learned_count'] as int? ?? 0,
      totalCount: totalCount,
      settings: StudySettings(
        dailyWords: row['daily_words'] as int? ?? 20,
        mode: StudyMode.values[row['study_mode'] as int? ?? 0],
      ),
      lastStudyTime: row['last_study_time'] != null
          ? DateTime.parse(row['last_study_time'] as String)
          : null,
    );
  }

  /// 保存学习设置
  Future<void> saveStudySettings(
    String dictName,
    StudySettings settings,
  ) async {
    final db = await database;
    await db.insert('study_progress', {
      'dict_name': dictName,
      'daily_words': settings.dailyWords,
      'study_mode': settings.mode.index,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 标记单词已学习
  Future<void> markWordLearned(int wordId, String dictName) async {
    final db = await database;
    await db.insert('word_progress', {
      'word_id': wordId,
      'dict_name': dictName,
      'is_learned': 1,
      'learn_time': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // 更新总进度
    await db.rawUpdate(
      '''
      UPDATE study_progress 
      SET learned_count = (
        SELECT COUNT(*) FROM word_progress 
        WHERE dict_name = ? AND is_learned = 1
      ),
      last_study_time = ?
      WHERE dict_name = ?
    ''',
      [dictName, DateTime.now().toIso8601String(), dictName],
    );
  }

  /// 获取今日待学习单词
  Future<List<String>> getTodayWords(
    String dictName,
    StudySettings settings,
  ) async {
    final db = await database;
    String orderBy;

    switch (settings.mode) {
      case StudyMode.sequential:
        orderBy = 'w.id ASC';
        break;
      case StudyMode.byDifficulty:
        orderBy = 'w.difficulty DESC, w.id ASC';
        break;
      case StudyMode.random:
        orderBy = 'RANDOM()';
        break;
    }

    final results = await db.rawQuery(
      '''
      SELECT w.word FROM words w
      JOIN word_dict_rel rel ON w.id = rel.word_id
      JOIN dictionaries d ON rel.dict_id = d.id
      LEFT JOIN word_progress wp ON w.id = wp.word_id AND wp.dict_name = ?
      WHERE d.name = ? AND (wp.is_learned IS NULL OR wp.is_learned = 0)
      ORDER BY $orderBy
      LIMIT ?
    ''',
      [dictName, dictName, settings.dailyWords],
    );

    return results.map((row) => row['word'] as String).toList();
  }

  /// 根据单词文本查询详细信息
  Future<WordDetail?> getWordDetail(String wordText) async {
    final db = await database;
    final List<Map<String, dynamic>> results = await db.rawQuery(
      '''
      SELECT w.*, s.definition, s.collocation, s.en_sentence, s.zh_sentence, s.sentence_tts
      FROM words w
      LEFT JOIN usage_stacks s ON w.id = s.word_id
      WHERE w.word = ?
    ''',
      [wordText],
    );

    if (results.isEmpty) return null;
    return WordDetail.fromSqlList(results);
  }

  /// 获取指定词典下的所有单词列表
  Future<List<String>> getWordListByDict(String dictName) async {
    final db = await database;
    final List<Map<String, dynamic>> results = await db.rawQuery(
      '''
      SELECT w.word FROM words w
      JOIN word_dict_rel rel ON w.id = rel.word_id
      JOIN dictionaries d ON rel.dict_id = d.id
      WHERE d.name = ?
      ORDER BY w.word ASC
    ''',
      [dictName],
    );

    return results.map((row) => row['word'] as String).toList();
  }
}
