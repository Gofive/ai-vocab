import 'dart:io';
import 'package:ai_vocab/models/study_settings.dart';
import 'package:ai_vocab/models/word_model.dart';
import 'package:ai_vocab/models/word_progress.dart';
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

    // 只在数据库文件不存在时复制 assets 中的数据库
    // 不再根据文件大小判断，因为用户数据会改变文件大小
    if (!await file.exists()) {
      final assetData = await rootBundle.load("assets/vocab.db");
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
    // 用户设置表（保存当前选择的词典等）
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

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

    // SM-2 算法进度表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_study_progress (
        word_id INTEGER NOT NULL,
        dict_name TEXT NOT NULL,
        ease_factor REAL DEFAULT 2.5,
        interval INTEGER DEFAULT 0,
        next_review_date TEXT,
        state INTEGER DEFAULT 0,
        last_modified TEXT,
        PRIMARY KEY (word_id, dict_name)
      )
    ''');

    // 学习会话表（保存当前学习队列，支持中断恢复）
    await db.execute('''
      CREATE TABLE IF NOT EXISTS study_session (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        dict_name TEXT NOT NULL,
        session_date TEXT NOT NULL,
        current_index INTEGER DEFAULT 0,
        is_completed INTEGER DEFAULT 0,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(dict_name, session_date)
      )
    ''');

    // 学习会话队列表（保存会话中的单词队列）
    await db.execute('''
      CREATE TABLE IF NOT EXISTS study_session_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        word_id INTEGER NOT NULL,
        queue_index INTEGER NOT NULL,
        is_review INTEGER DEFAULT 0,
        is_done INTEGER DEFAULT 0,
        FOREIGN KEY (session_id) REFERENCES study_session(id) ON DELETE CASCADE
      )
    ''');

    // 旧表兼容（如果存在则迁移数据）
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

  // ==================== 用户设置 ====================

  /// 获取当前选择的词典
  Future<String?> getCurrentDict() async {
    final db = await database;
    final result = await db.query(
      'user_settings',
      where: 'key = ?',
      whereArgs: ['current_dict'],
    );
    if (result.isEmpty) return null;
    return result.first['value'] as String?;
  }

  /// 保存当前选择的词典
  Future<void> setCurrentDict(String dictName) async {
    final db = await database;
    await db.insert('user_settings', {
      'key': 'current_dict',
      'value': dictName,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 获取用户设置
  Future<String?> getUserSetting(String key) async {
    final db = await database;
    final result = await db.query(
      'user_settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (result.isEmpty) return null;
    return result.first['value'] as String?;
  }

  /// 保存用户设置
  Future<void> setUserSetting(String key, String value) async {
    final db = await database;
    await db.insert('user_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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

    // 从 user_study_progress 表统计已学习的单词数
    final learnedResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count FROM user_study_progress
      WHERE dict_name = ? AND state >= 1
    ''',
      [dictName],
    );
    final learnedCount = learnedResult.first['count'] as int? ?? 0;

    // 获取今日学习统计
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final todayNewResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count FROM user_study_progress
      WHERE dict_name = ? AND DATE(last_modified) = ? AND state = 1
    ''',
      [dictName, today],
    );
    final todayNewCount = todayNewResult.first['count'] as int? ?? 0;

    // 获取今日待复习数量
    final reviewResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count FROM user_study_progress
      WHERE dict_name = ? AND next_review_date <= ? AND state > 0
    ''',
      [dictName, today],
    );
    final reviewCount = reviewResult.first['count'] as int? ?? 0;

    // 获取学习设置
    final progressResult = await db.query(
      'study_progress',
      where: 'dict_name = ?',
      whereArgs: [dictName],
    );

    StudySettings settings = const StudySettings();
    DateTime? lastStudyTime;

    if (progressResult.isNotEmpty) {
      final row = progressResult.first;
      settings = StudySettings(
        dailyWords: row['daily_words'] as int? ?? 20,
        mode: StudyMode.values[row['study_mode'] as int? ?? 0],
      );
      lastStudyTime = row['last_study_time'] != null
          ? DateTime.parse(row['last_study_time'] as String)
          : null;
    }

    return DictProgress(
      dictName: dictName,
      learnedCount: learnedCount,
      totalCount: totalCount,
      settings: settings,
      lastStudyTime: lastStudyTime,
      todayNewCount: todayNewCount,
      todayReviewCount: reviewCount,
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

  /// 获取今日待学习单词（返回单词文本和ID的映射）
  Future<Map<String, int>> getTodayWordsWithIds(
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
      SELECT w.id, w.word FROM words w
      JOIN word_dict_rel rel ON w.id = rel.word_id
      JOIN dictionaries d ON rel.dict_id = d.id
      LEFT JOIN word_progress wp ON w.id = wp.word_id AND wp.dict_name = ?
      WHERE d.name = ? AND (wp.is_learned IS NULL OR wp.is_learned = 0)
      ORDER BY $orderBy
      LIMIT ?
    ''',
      [dictName, dictName, settings.dailyWords],
    );

    return {for (var row in results) row['word'] as String: row['id'] as int};
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

  // ==================== SM-2 算法相关方法 ====================

  /// 获取今日需要复习的单词
  Future<List<WordProgress>> getReviewWords(
    String dictName, {
    int limit = 10,
  }) async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);

    final results = await db.rawQuery(
      '''
      SELECT usp.*, w.word 
      FROM user_study_progress usp
      JOIN words w ON usp.word_id = w.id
      WHERE usp.dict_name = ? 
        AND usp.next_review_date <= ?
        AND usp.state > 0
      ORDER BY usp.next_review_date ASC
      LIMIT ?
    ''',
      [dictName, today, limit],
    );

    return results
        .map((row) => WordProgress.fromMap(row, isReview: true))
        .toList();
  }

  /// 获取今日学习队列（新词 + 复习词穿插）
  Future<List<WordProgress>> getTodayStudyQueue(
    String dictName,
    StudySettings settings,
  ) async {
    final db = await database;

    // 1. 获取需要复习的单词
    final reviewWords = await getReviewWords(
      dictName,
      limit: settings.dailyWords ~/ 2,
    );

    // 2. 获取新单词
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

    final newWordsLimit = settings.dailyWords - reviewWords.length;
    final newWordResults = await db.rawQuery(
      '''
      SELECT w.id as word_id, w.word, ? as dict_name
      FROM words w
      JOIN word_dict_rel rel ON w.id = rel.word_id
      JOIN dictionaries d ON rel.dict_id = d.id
      LEFT JOIN user_study_progress usp ON w.id = usp.word_id AND usp.dict_name = ?
      WHERE d.name = ? AND usp.word_id IS NULL
      ORDER BY $orderBy
      LIMIT ?
    ''',
      [dictName, dictName, dictName, newWordsLimit],
    );

    final newWords = newWordResults
        .map((row) => WordProgress.fromMap(row))
        .toList();

    // 3. 穿插合并：每学3个新词插入1个复习词
    final List<WordProgress> queue = [];
    int newIndex = 0;
    int reviewIndex = 0;
    int newCount = 0;

    while (newIndex < newWords.length || reviewIndex < reviewWords.length) {
      // 每3个新词后插入1个复习词
      if (newIndex < newWords.length &&
          (newCount < 3 || reviewIndex >= reviewWords.length)) {
        queue.add(newWords[newIndex++]);
        newCount++;
      } else if (reviewIndex < reviewWords.length) {
        queue.add(reviewWords[reviewIndex++]);
        newCount = 0;
      }
    }

    return queue;
  }

  /// 更新单词学习进度 (SM-2 算法)
  Future<void> updateWordProgress(WordProgress progress) async {
    final db = await database;
    await db.insert(
      'user_study_progress',
      progress.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // 更新总进度统计
    await _updateDictProgress(progress.dictName);
  }

  /// 更新词典总进度
  Future<void> _updateDictProgress(String dictName) async {
    final db = await database;

    // 统计已掌握的单词数
    final masteredCount = await db.rawQuery(
      '''
      SELECT COUNT(*) as count FROM user_study_progress
      WHERE dict_name = ? AND state >= 1
    ''',
      [dictName],
    );

    final count = masteredCount.first['count'] as int;

    await db.rawUpdate(
      '''
      UPDATE study_progress 
      SET learned_count = ?,
          last_study_time = ?
      WHERE dict_name = ?
    ''',
      [count, DateTime.now().toIso8601String(), dictName],
    );

    // 如果不存在则插入
    await db.insert('study_progress', {
      'dict_name': dictName,
      'learned_count': count,
      'last_study_time': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// 获取单词的学习进度
  Future<WordProgress?> getWordProgress(int wordId, String dictName) async {
    final db = await database;
    final results = await db.rawQuery(
      '''
      SELECT usp.*, w.word 
      FROM user_study_progress usp
      JOIN words w ON usp.word_id = w.id
      WHERE usp.word_id = ? AND usp.dict_name = ?
    ''',
      [wordId, dictName],
    );

    if (results.isEmpty) return null;
    return WordProgress.fromMap(results.first);
  }

  // ==================== 学习会话管理 ====================

  /// 今日学习状态枚举
  /// - noSession: 今日没有学习记录
  /// - inProgress: 今日有未完成的学习
  /// - completed: 今日学习已完成
  Future<TodaySessionStatus> getTodaySessionStatus(String dictName) async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);

    // 检查今日是否有会话
    final sessions = await db.query(
      'study_session',
      where: 'dict_name = ? AND session_date = ?',
      whereArgs: [dictName, today],
    );

    if (sessions.isEmpty) {
      return TodaySessionStatus.noSession;
    }

    // 检查是否已完成
    final completedSession = sessions.where((s) => s['is_completed'] == 1);
    if (completedSession.isNotEmpty) {
      return TodaySessionStatus.completed;
    }

    return TodaySessionStatus.inProgress;
  }

  /// 获取或创建今日学习会话
  Future<StudySession?> getOrCreateTodaySession(
    String dictName,
    StudySettings settings,
  ) async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);

    // 1. 检查是否有今日未完成的会话
    final existingSession = await db.query(
      'study_session',
      where: 'dict_name = ? AND session_date = ? AND is_completed = 0',
      whereArgs: [dictName, today],
    );

    if (existingSession.isNotEmpty) {
      // 恢复已有会话
      final sessionId = existingSession.first['id'] as int;
      final currentIndex = existingSession.first['current_index'] as int;
      final queue = await _getSessionQueue(sessionId);

      if (queue.isNotEmpty) {
        return StudySession(
          id: sessionId,
          dictName: dictName,
          sessionDate: today,
          currentIndex: currentIndex,
          queue: queue,
        );
      }
    }

    // 2. 创建新会话
    final queue = await getTodayStudyQueue(dictName, settings);
    if (queue.isEmpty) return null;

    // 插入会话记录
    final sessionId = await db.insert('study_session', {
      'dict_name': dictName,
      'session_date': today,
      'current_index': 0,
      'is_completed': 0,
      'created_at': DateTime.now().toIso8601String(),
    });

    // 插入队列
    for (int i = 0; i < queue.length; i++) {
      await db.insert('study_session_queue', {
        'session_id': sessionId,
        'word_id': queue[i].wordId,
        'queue_index': i,
        'is_review': queue[i].isReview ? 1 : 0,
        'is_done': 0,
      });
    }

    return StudySession(
      id: sessionId,
      dictName: dictName,
      sessionDate: today,
      currentIndex: 0,
      queue: queue,
    );
  }

  /// 获取会话队列
  Future<List<WordProgress>> _getSessionQueue(int sessionId) async {
    final db = await database;
    final results = await db.rawQuery(
      '''
      SELECT ssq.*, w.word, usp.ease_factor, usp.interval, 
             usp.next_review_date, usp.state, usp.last_modified,
             ssq.is_review as is_review_flag
      FROM study_session_queue ssq
      JOIN words w ON ssq.word_id = w.id
      JOIN study_session ss ON ssq.session_id = ss.id
      LEFT JOIN user_study_progress usp ON ssq.word_id = usp.word_id AND usp.dict_name = ss.dict_name
      WHERE ssq.session_id = ?
      ORDER BY ssq.queue_index ASC
    ''',
      [sessionId],
    );

    return results.map((row) {
      return WordProgress(
        wordId: row['word_id'] as int,
        word: row['word'] as String,
        dictName: '', // 会从 session 获取
        easeFactor: (row['ease_factor'] as num?)?.toDouble() ?? 2.5,
        interval: row['interval'] as int? ?? 0,
        nextReviewDate: row['next_review_date'] != null
            ? DateTime.parse(row['next_review_date'] as String)
            : null,
        state: WordState.values[row['state'] as int? ?? 0],
        lastModified: row['last_modified'] != null
            ? DateTime.parse(row['last_modified'] as String)
            : null,
        isReview: (row['is_review_flag'] as int? ?? 0) == 1,
      );
    }).toList();
  }

  /// 更新会话进度
  Future<void> updateSessionProgress(int sessionId, int currentIndex) async {
    final db = await database;
    await db.update(
      'study_session',
      {'current_index': currentIndex},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// 标记会话中的单词已完成
  Future<void> markSessionWordDone(int sessionId, int queueIndex) async {
    final db = await database;
    await db.update(
      'study_session_queue',
      {'is_done': 1},
      where: 'session_id = ? AND queue_index = ?',
      whereArgs: [sessionId, queueIndex],
    );
  }

  /// 完成会话
  Future<void> completeSession(int sessionId) async {
    final db = await database;
    await db.update(
      'study_session',
      {'is_completed': 1},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// 获取今日学习统计
  Future<Map<String, int>> getTodayStats(String dictName) async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);

    // 今日学习的新词数
    final newWordsResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count FROM user_study_progress
      WHERE dict_name = ? AND DATE(last_modified) = ?
    ''',
      [dictName, today],
    );

    // 今日复习的词数
    final reviewResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count FROM study_session_queue ssq
      JOIN study_session ss ON ssq.session_id = ss.id
      WHERE ss.dict_name = ? AND ss.session_date = ? 
        AND ssq.is_review = 1 AND ssq.is_done = 1
    ''',
      [dictName, today],
    );

    return {
      'newWords': newWordsResult.first['count'] as int? ?? 0,
      'reviewWords': reviewResult.first['count'] as int? ?? 0,
    };
  }

  /// 删除单词学习进度（用于撤销操作）
  Future<void> deleteWordProgress(int wordId, String dictName) async {
    final db = await database;
    await db.delete(
      'user_study_progress',
      where: 'word_id = ? AND dict_name = ?',
      whereArgs: [wordId, dictName],
    );
  }

  /// 添加单词到会话队列（用于"没记住"时加入队列末尾）
  Future<void> addWordToSessionQueue(
    int sessionId,
    int wordId,
    int queueIndex,
  ) async {
    final db = await database;
    await db.insert('study_session_queue', {
      'session_id': sessionId,
      'word_id': wordId,
      'queue_index': queueIndex,
      'is_review': 1,
      'is_done': 0,
    });
  }

  /// 获取下一个新词（用于补充队列）
  Future<WordProgress?> getNextNewWord(
    String dictName,
    StudySettings settings,
    List<WordProgress> currentQueue,
  ) async {
    final db = await database;

    // 获取当前队列中的所有 word_id
    final existingIds = currentQueue.map((w) => w.wordId).toList();
    final placeholders = existingIds.isNotEmpty
        ? existingIds.map((_) => '?').join(',')
        : '0';

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
      SELECT w.id as word_id, w.word, ? as dict_name
      FROM words w
      JOIN word_dict_rel rel ON w.id = rel.word_id
      JOIN dictionaries d ON rel.dict_id = d.id
      LEFT JOIN user_study_progress usp ON w.id = usp.word_id AND usp.dict_name = ?
      WHERE d.name = ? 
        AND usp.word_id IS NULL
        AND w.id NOT IN ($placeholders)
      ORDER BY $orderBy
      LIMIT 1
    ''',
      [dictName, dictName, dictName, ...existingIds],
    );

    if (results.isEmpty) return null;
    return WordProgress.fromMap(results.first);
  }

  /// 移除会话队列中的最后一个单词（用于撤销时）
  Future<void> removeLastWordFromSessionQueue(int sessionId) async {
    final db = await database;

    // 获取最大的 queue_index
    final maxIndex = await db.rawQuery(
      'SELECT MAX(queue_index) as max_idx FROM study_session_queue WHERE session_id = ?',
      [sessionId],
    );

    if (maxIndex.isNotEmpty && maxIndex.first['max_idx'] != null) {
      final idx = maxIndex.first['max_idx'] as int;
      await db.delete(
        'study_session_queue',
        where: 'session_id = ? AND queue_index = ?',
        whereArgs: [sessionId, idx],
      );
    }
  }

  /// 取消标记会话中的单词为已完成（用于撤销）
  Future<void> unmarkSessionWordDone(int sessionId, int queueIndex) async {
    final db = await database;
    await db.update(
      'study_session_queue',
      {'is_done': 0},
      where: 'session_id = ? AND queue_index = ?',
      whereArgs: [sessionId, queueIndex],
    );
  }
}

/// 学习会话模型
class StudySession {
  final int id;
  final String dictName;
  final String sessionDate;
  final int currentIndex;
  final List<WordProgress> queue;

  StudySession({
    required this.id,
    required this.dictName,
    required this.sessionDate,
    required this.currentIndex,
    required this.queue,
  });

  int get newWordsCount => queue.where((w) => !w.isReview).length;
  int get reviewWordsCount => queue.where((w) => w.isReview).length;
  bool get isCompleted => currentIndex >= queue.length;
}

/// 今日学习状态
enum TodaySessionStatus {
  noSession, // 今日没有学习记录
  inProgress, // 今日有未完成的学习
  completed, // 今日学习已完成
}
