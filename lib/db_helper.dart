import 'dart:io';
import 'package:ai_vocab/models/study_settings.dart';
import 'package:ai_vocab/models/word_model.dart';
import 'package:ai_vocab/models/word_card.dart';
import 'package:ai_vocab/models/review_log.dart';
import 'package:ai_vocab/models/study_session.dart';
import 'package:ai_vocab/services/review_reminder_service.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';

/// 数据库版本号
const int _dbVersion = 2;

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
        repetition INTEGER DEFAULT 0,
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
        occurrence INTEGER DEFAULT 1,
        FOREIGN KEY (session_id) REFERENCES study_session(id) ON DELETE CASCADE
      )
    ''');

    // 添加 occurrence 字段（如果不存在）
    await _addOccurrenceColumn(db);

    // 检查并升级数据库结构到 FSRS
    await _upgradeToFSRS(db);
  }

  /// 添加 occurrence 字段到 study_session_queue 表
  Future<void> _addOccurrenceColumn(Database db) async {
    final tableInfo = await db.rawQuery(
      "PRAGMA table_info(study_session_queue)",
    );
    final existingColumns = tableInfo.map((c) => c['name'] as String).toSet();

    if (!existingColumns.contains('occurrence')) {
      try {
        await db.execute(
          'ALTER TABLE study_session_queue ADD COLUMN occurrence INTEGER DEFAULT 1',
        );
        print('DEBUG: 添加列 occurrence 到 study_session_queue');
      } catch (e) {
        print('DEBUG: 添加列 occurrence 失败: $e');
      }
    }
  }

  /// 检查数据库版本并升级到 FSRS 结构
  Future<void> _upgradeToFSRS(Database db) async {
    // 检查当前数据库版本
    final currentVersion = await _getDbVersion(db);

    if (currentVersion < _dbVersion) {
      print('DEBUG: 数据库版本 $currentVersion -> $_dbVersion，开始升级...');

      // 添加 FSRS 字段到 user_study_progress 表
      await _addFSRSColumns(db);

      // 创建 review_logs 表
      await _createReviewLogsTable(db);

      // 更新数据库版本
      await _setDbVersion(db, _dbVersion);

      print('DEBUG: 数据库升级完成');
    }
  }

  /// 获取数据库版本号
  Future<int> _getDbVersion(Database db) async {
    try {
      final result = await db.query(
        'user_settings',
        where: 'key = ?',
        whereArgs: ['db_version'],
      );
      if (result.isEmpty) return 1; // 默认版本 1 (SM-2)
      return int.tryParse(result.first['value'] as String? ?? '1') ?? 1;
    } catch (e) {
      // 表可能不存在
      return 1;
    }
  }

  /// 设置数据库版本号
  Future<void> _setDbVersion(Database db, int version) async {
    await db.insert('user_settings', {
      'key': 'db_version',
      'value': version.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 添加 FSRS 字段到 user_study_progress 表
  Future<void> _addFSRSColumns(Database db) async {
    // 检查是否已有 FSRS 字段
    final tableInfo = await db.rawQuery(
      "PRAGMA table_info(user_study_progress)",
    );
    final existingColumns = tableInfo.map((c) => c['name'] as String).toSet();

    // FSRS 新增字段列表
    final fsrsColumns = <String, String>{
      'due': 'TEXT', // 下次复习时间 (ISO8601)
      'stability': 'REAL DEFAULT 0', // 记忆稳定性
      'difficulty': 'REAL DEFAULT 5.0', // 单词难度 (1-10)
      'elapsed_days': 'INTEGER DEFAULT 0', // 自上次复习以来的天数
      'scheduled_days': 'INTEGER DEFAULT 0', // 计划的复习间隔天数
      'reps': 'INTEGER DEFAULT 0', // 成功复习次数
      'lapses': 'INTEGER DEFAULT 0', // 遗忘次数
      'last_review': 'TEXT', // 上次复习时间 (ISO8601)
      'first_learned_date': 'TEXT', // 首次学习日期 (ISO8601)
    };

    for (final entry in fsrsColumns.entries) {
      if (!existingColumns.contains(entry.key)) {
        try {
          await db.execute(
            'ALTER TABLE user_study_progress ADD COLUMN ${entry.key} ${entry.value}',
          );
          print('DEBUG: 添加列 ${entry.key} 到 user_study_progress');
        } catch (e) {
          print('DEBUG: 添加列 ${entry.key} 失败: $e');
        }
      }
    }
  }

  /// 创建 review_logs 表
  Future<void> _createReviewLogsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS review_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_id INTEGER NOT NULL,
        dict_name TEXT NOT NULL,
        rating INTEGER NOT NULL,
        state INTEGER NOT NULL,
        due TEXT NOT NULL,
        stability REAL NOT NULL,
        difficulty REAL NOT NULL,
        elapsed_days INTEGER NOT NULL,
        scheduled_days INTEGER NOT NULL,
        review_datetime TEXT NOT NULL,
        FOREIGN KEY (word_id) REFERENCES words(id)
      )
    ''');

    // 创建索引以优化查询性能
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_review_logs_word 
      ON review_logs(word_id, dict_name)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_review_logs_datetime 
      ON review_logs(review_datetime)
    ''');

    print('DEBUG: review_logs 表创建完成');
  }

  /// 检查是否需要迁移到 FSRS
  Future<bool> needsFSRSMigration() async {
    final db = await database;
    final version = await _getDbVersion(db);

    // 如果版本已经是 FSRS 版本，检查是否有未迁移的数据
    if (version >= _dbVersion) {
      // 检查是否有 SM-2 数据但没有 FSRS 数据的记录
      final unmigrated = await db.rawQuery('''
        SELECT COUNT(*) as count FROM user_study_progress
        WHERE state > 0 AND (due IS NULL OR due = '')
      ''');
      return (unmigrated.first['count'] as int? ?? 0) > 0;
    }

    return true;
  }

  /// 获取数据库文件路径
  Future<String> getDatabasePath() async {
    if (Platform.isWindows || Platform.isLinux) {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      return join(documentsDirectory.path, "vocab.db");
    } else {
      return join(await getDatabasesPath(), "vocab.db");
    }
  }

  // ==================== FSRS 数据迁移服务 ====================

  /// 备份数据库
  ///
  /// 在迁移前创建数据库备份，以便迁移失败时可以回滚。
  /// 返回备份文件的路径。
  ///
  /// _Requirements: 8.5_
  Future<String> backupDatabase() async {
    final dbPath = await getDatabasePath();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final backupPath = '$dbPath.backup_$timestamp';

    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      await dbFile.copy(backupPath);
      print('DEBUG: 数据库已备份到 $backupPath');
    }

    return backupPath;
  }

  /// 从备份恢复数据库
  ///
  /// 当迁移失败时，使用此方法恢复到备份状态。
  ///
  /// _Requirements: 2.4_
  Future<void> _restoreFromBackup(String backupPath) async {
    final dbPath = await getDatabasePath();
    final backupFile = File(backupPath);

    if (await backupFile.exists()) {
      // 关闭当前数据库连接
      if (_db != null) {
        await _db!.close();
        _db = null;
      }

      // 恢复备份
      await backupFile.copy(dbPath);
      print('DEBUG: 数据库已从备份恢复: $backupPath');

      // 重新打开数据库
      _db = await _initDB();
    }
  }

  /// 迁移 SM-2 数据到 FSRS 格式
  ///
  /// 将现有的 SM-2 学习进度数据转换为 FSRS 格式。
  /// 迁移策略：
  /// - stability = interval * 0.9 (估算)
  /// - difficulty = 5.0 (固定中等难度)
  /// - reps = repetition (直接复制)
  /// - state: 0 -> 保持新卡, >=1 -> State.review
  /// - lapses = 0 (无历史数据)
  /// - elapsed_days = 0 (无历史数据)
  /// - scheduled_days = interval
  /// - due = next_review_date (直接复制)
  /// - last_review = last_modified (直接复制)
  ///
  /// _Requirements: 2.2, 2.3, 2.4, 8.1, 8.2, 8.3, 8.4, 8.5, 8.6_
  Future<void> migrateToFSRS() async {
    final db = await database;

    // 1. 备份数据库
    final backupPath = await backupDatabase();

    try {
      // 2. 获取所有需要迁移的 SM-2 数据
      // 只迁移 state > 0 的记录（已学习过的单词）
      final sm2Records = await db.rawQuery('''
        SELECT word_id, dict_name, ease_factor, interval, repetition,
               next_review_date, state, last_modified
        FROM user_study_progress
        WHERE state > 0 AND (due IS NULL OR due = '')
      ''');

      print('DEBUG: 找到 ${sm2Records.length} 条需要迁移的 SM-2 记录');

      if (sm2Records.isEmpty) {
        print('DEBUG: 没有需要迁移的数据');
        return;
      }

      // 3. 开始事务进行迁移
      await db.transaction((txn) async {
        for (final record in sm2Records) {
          final wordId = record['word_id'] as int;
          final dictName = record['dict_name'] as String;
          final interval = record['interval'] as int? ?? 0;
          final repetition = record['repetition'] as int? ?? 0;
          final nextReviewDate = record['next_review_date'] as String?;
          final sm2State = record['state'] as int? ?? 0;
          final lastModified = record['last_modified'] as String?;

          // SM-2 到 FSRS 的转换
          // stability = interval * 0.9 (估算遗忘速率)
          final stability = interval > 0 ? interval * 0.9 : 0.0;

          // difficulty = 5.0 (固定中等难度)
          const difficulty = 5.0;

          // state: SM-2 state >= 1 -> FSRS State.review (index = 2)
          // FSRS State: 0=New, 1=Learning, 2=Review, 3=Relearning
          final fsrsState = sm2State >= 1 ? 2 : 0;

          // due: 使用 next_review_date，如果为空则使用当前时间
          final due =
              nextReviewDate ?? DateTime.now().toUtc().toIso8601String();

          // last_review: 使用 last_modified
          final lastReview = lastModified;

          // 更新记录
          await txn.update(
            'user_study_progress',
            {
              'due': due,
              'stability': stability,
              'difficulty': difficulty,
              'elapsed_days': 0,
              'scheduled_days': interval,
              'reps': repetition,
              'lapses': 0,
              'state': fsrsState,
              'last_review': lastReview,
            },
            where: 'word_id = ? AND dict_name = ?',
            whereArgs: [wordId, dictName],
          );
        }
      });

      print('DEBUG: FSRS 数据迁移完成，共迁移 ${sm2Records.length} 条记录');
    } catch (e) {
      // 4. 迁移失败，回滚到备份
      print('DEBUG: FSRS 迁移失败: $e，正在回滚...');
      await _restoreFromBackup(backupPath);
      rethrow;
    }
  }

  /// 获取迁移状态
  ///
  /// 返回迁移相关的统计信息
  Future<Map<String, int>> getMigrationStatus() async {
    final db = await database;

    // 总记录数
    final totalResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM user_study_progress WHERE state > 0',
    );
    final total = totalResult.first['count'] as int? ?? 0;

    // 已迁移记录数（有 FSRS 数据）
    final migratedResult = await db.rawQuery('''
      SELECT COUNT(*) as count FROM user_study_progress
      WHERE state > 0 AND due IS NOT NULL AND due != ''
    ''');
    final migrated = migratedResult.first['count'] as int? ?? 0;

    // 未迁移记录数
    final unmigratedResult = await db.rawQuery('''
      SELECT COUNT(*) as count FROM user_study_progress
      WHERE state > 0 AND (due IS NULL OR due = '')
    ''');
    final unmigrated = unmigratedResult.first['count'] as int? ?? 0;

    return {'total': total, 'migrated': migrated, 'unmigrated': unmigrated};
  }

  // ==================== FSRS WordCard CRUD 操作 ====================

  /// 获取 FSRS 卡片
  ///
  /// 根据 wordId 和 dictName 获取单词的 FSRS 卡片数据。
  /// 如果卡片不存在，返回 null。
  ///
  /// _Requirements: 6.1_
  Future<WordCard?> getWordCard(int wordId, String dictName) async {
    final db = await database;

    final results = await db.rawQuery(
      '''
      SELECT usp.word_id, usp.dict_name, usp.due, usp.stability, usp.difficulty,
             usp.elapsed_days, usp.scheduled_days, usp.reps, usp.lapses,
             usp.state, usp.last_review, usp.first_learned_date, w.word
      FROM user_study_progress usp
      JOIN words w ON usp.word_id = w.id
      WHERE usp.word_id = ? AND usp.dict_name = ?
        AND usp.due IS NOT NULL AND usp.due != ''
    ''',
      [wordId, dictName],
    );

    if (results.isEmpty) return null;

    return WordCard.fromMap(results.first);
  }

  /// 保存 FSRS 卡片
  ///
  /// 将 WordCard 保存到数据库。如果记录已存在则更新，否则插入新记录。
  /// 首次保存时会自动设置 first_learned_date 为当前日期。
  ///
  /// _Requirements: 6.1_
  Future<void> saveWordCard(WordCard card) async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);

    // 检查是否是首次学习（没有 first_learned_date）
    if (card.firstLearnedDate == null) {
      // 检查数据库中是否已有记录
      final existing = await db.query(
        'user_study_progress',
        columns: ['first_learned_date'],
        where: 'word_id = ? AND dict_name = ?',
        whereArgs: [card.wordId, card.dictName],
      );

      if (existing.isEmpty || existing.first['first_learned_date'] == null) {
        // 首次学习，设置 first_learned_date
        card.firstLearnedDate = today;
      } else {
        // 保留已有的 first_learned_date
        card.firstLearnedDate = existing.first['first_learned_date'] as String?;
      }
    }

    final map = card.toMap();

    // 使用 REPLACE 语义：如果主键存在则更新，否则插入
    await db.insert(
      'user_study_progress',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // 通知复习提醒服务数据已变更
    ReviewReminderService().notifyChange();
  }

  /// 获取待复习的 FSRS 卡片
  ///
  /// 查询指定词典中所有到期需要复习的卡片。
  /// 按 due 日期升序排列（最早到期的优先）。
  /// 获取待复习的 FSRS 卡片
  ///
  /// 查询指定词典中所有到期需要复习的卡片（due <= now）。
  /// 按 due 日期升序排列（最早到期的优先）。
  ///
  /// 注意：此方法返回所有 FSRS 算法层面到期的卡片，
  /// 不区分是今日新词还是之前学过的词。
  /// 如需区分，请使用 WordCard.isReview 属性。
  ///
  /// [dictName] - 词典名称
  /// [limit] - 返回的最大卡片数量，默认 100
  ///
  /// _Requirements: 6.1, 6.2_
  Future<List<WordCard>> getDueCards(String dictName, {int limit = 100}) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();

    final results = await db.rawQuery(
      '''
      SELECT usp.word_id, usp.dict_name, usp.due, usp.stability, usp.difficulty,
             usp.elapsed_days, usp.scheduled_days, usp.reps, usp.lapses,
             usp.state, usp.last_review, usp.first_learned_date, w.word
      FROM user_study_progress usp
      JOIN words w ON usp.word_id = w.id
      WHERE usp.dict_name = ?
        AND usp.due IS NOT NULL AND usp.due != ''
        AND usp.due <= ?
      ORDER BY usp.due ASC
      LIMIT ?
    ''',
      [dictName, now, limit],
    );

    return results.map((row) => WordCard.fromMap(row)).toList();
  }

  /// 获取待复习的 FSRS 卡片（排除今日新词）
  ///
  /// 用于统计"复习巩固"数量，排除今日首次学习的新词。
  /// 今日新词的定义：first_learned_date = 今天
  ///
  /// [dictName] - 词典名称
  /// [limit] - 返回的最大卡片数量，默认 100
  Future<List<WordCard>> getDueCardsExcludeTodayNew(
    String dictName, {
    int limit = 100,
  }) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    final today = DateTime.now().toIso8601String().substring(0, 10);

    final results = await db.rawQuery(
      '''
      SELECT usp.word_id, usp.dict_name, usp.due, usp.stability, usp.difficulty,
             usp.elapsed_days, usp.scheduled_days, usp.reps, usp.lapses,
             usp.state, usp.last_review, usp.first_learned_date, w.word
      FROM user_study_progress usp
      JOIN words w ON usp.word_id = w.id
      WHERE usp.dict_name = ?
        AND usp.due IS NOT NULL AND usp.due != ''
        AND usp.due <= ?
        AND (usp.first_learned_date IS NULL OR DATE(usp.first_learned_date) != ?)
      ORDER BY usp.due ASC
      LIMIT ?
    ''',
      [dictName, now, today, limit],
    );

    return results.map((row) => WordCard.fromMap(row)).toList();
  }

  /// 获取所有 FSRS 卡片（包括未到期的）
  ///
  /// 用于统计和调试目的。
  ///
  /// [dictName] - 词典名称
  /// [limit] - 返回的最大卡片数量，默认 1000
  Future<List<WordCard>> getAllWordCards(
    String dictName, {
    int limit = 1000,
  }) async {
    final db = await database;

    final results = await db.rawQuery(
      '''
      SELECT usp.word_id, usp.dict_name, usp.due, usp.stability, usp.difficulty,
             usp.elapsed_days, usp.scheduled_days, usp.reps, usp.lapses,
             usp.state, usp.last_review, usp.first_learned_date, w.word
      FROM user_study_progress usp
      JOIN words w ON usp.word_id = w.id
      WHERE usp.dict_name = ?
        AND usp.due IS NOT NULL AND usp.due != ''
      ORDER BY usp.due ASC
      LIMIT ?
    ''',
      [dictName, limit],
    );

    return results.map((row) => WordCard.fromMap(row)).toList();
  }

  /// 创建新的 FSRS 卡片
  ///
  /// 为新单词创建一个初始化的 FSRS 卡片。
  ///
  /// [wordId] - 单词 ID
  /// [word] - 单词文本
  /// [dictName] - 词典名称
  ///
  /// 返回创建的 WordCard 对象
  Future<WordCard> createWordCard(
    int wordId,
    String word,
    String dictName,
  ) async {
    final card = WordCard(wordId: wordId, word: word, dictName: dictName);

    await saveWordCard(card);
    return card;
  }

  // ==================== FSRS ReviewLog 操作 ====================

  /// 记录复习日志
  ///
  /// 将复习日志保存到 review_logs 表，用于未来的 FSRS 参数优化。
  ///
  /// [log] - ReviewLogEntry 对象，包含复习的详细信息
  ///
  /// 返回插入记录的 ID
  ///
  /// _Requirements: 9.1, 9.2_
  Future<int> logReview(ReviewLogEntry log) async {
    final db = await database;

    final id = await db.insert('review_logs', log.toMap());

    return id;
  }

  /// 获取单词的复习历史
  ///
  /// [wordId] - 单词 ID
  /// [dictName] - 词典名称
  /// [limit] - 返回的最大记录数，默认 100
  ///
  /// 返回按时间倒序排列的复习日志列表
  Future<List<ReviewLogEntry>> getReviewHistory(
    int wordId,
    String dictName, {
    int limit = 100,
  }) async {
    final db = await database;

    final results = await db.query(
      'review_logs',
      where: 'word_id = ? AND dict_name = ?',
      whereArgs: [wordId, dictName],
      orderBy: 'review_datetime DESC',
      limit: limit,
    );

    return results.map((row) => ReviewLogEntry.fromMap(row)).toList();
  }

  /// 获取指定时间范围内的复习日志
  ///
  /// [dictName] - 词典名称
  /// [startDate] - 开始日期
  /// [endDate] - 结束日期
  ///
  /// 返回按时间升序排列的复习日志列表
  ///
  /// _Requirements: 9.4_
  Future<List<ReviewLogEntry>> getReviewLogsByDateRange(
    String dictName,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final db = await database;

    final results = await db.query(
      'review_logs',
      where: 'dict_name = ? AND review_datetime >= ? AND review_datetime <= ?',
      whereArgs: [
        dictName,
        startDate.toIso8601String(),
        endDate.toIso8601String(),
      ],
      orderBy: 'review_datetime ASC',
    );

    return results.map((row) => ReviewLogEntry.fromMap(row)).toList();
  }

  /// 导出所有复习日志
  ///
  /// 用于 FSRS 参数优化。返回所有复习日志的 Map 列表。
  ///
  /// [dictName] - 词典名称（可选，为空则导出所有词典）
  ///
  /// _Requirements: 9.4_
  Future<List<Map<String, dynamic>>> exportReviewLogs({
    String? dictName,
  }) async {
    final db = await database;

    if (dictName != null) {
      return await db.query(
        'review_logs',
        where: 'dict_name = ?',
        whereArgs: [dictName],
        orderBy: 'review_datetime ASC',
      );
    } else {
      return await db.query('review_logs', orderBy: 'review_datetime ASC');
    }
  }

  /// 获取复习日志统计
  ///
  /// [dictName] - 词典名称
  ///
  /// 返回统计信息：总复习次数、各评分次数等
  Future<Map<String, int>> getReviewLogStats(String dictName) async {
    final db = await database;

    // 总复习次数
    final totalResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM review_logs WHERE dict_name = ?',
      [dictName],
    );
    final total = totalResult.first['count'] as int? ?? 0;

    // 各评分次数
    final ratingStats = <String, int>{'total': total};

    for (int i = 1; i <= 4; i++) {
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM review_logs WHERE dict_name = ? AND rating = ?',
        [dictName, i],
      );
      ratingStats['rating_$i'] = result.first['count'] as int? ?? 0;
    }

    return ratingStats;
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
  ///
  /// 统计逻辑：
  /// - 已学习: 有 FSRS 数据的记录
  /// - 今日新词: 队列中 is_review = 0 且 is_done = 1 的数量
  /// - 复习总量: 队列中 is_review = 1 的数量
  /// - 已复习: 队列中 is_review = 1 且 is_done = 1 的数量
  Future<DictProgress> getDictProgress(String dictName) async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);

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

    // 已学习 = 有 FSRS 数据的记录
    final learnedResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count FROM user_study_progress
      WHERE dict_name = ? AND due IS NOT NULL AND due != ''
    ''',
      [dictName],
    );
    final learnedCount = learnedResult.first['count'] as int? ?? 0;

    // 获取学习设置
    final progressResult = await db.query(
      'study_progress',
      where: 'dict_name = ?',
      whereArgs: [dictName],
    );
    StudySettings settings = const StudySettings();
    if (progressResult.isNotEmpty) {
      final row = progressResult.first;
      settings = StudySettings(
        dailyWords: row['daily_words'] as int? ?? 20,
        mode: StudyMode.values[row['study_mode'] as int? ?? 0],
      );
    }

    // 基于今日队列统计
    int todayNewCount = 0;
    int reviewTotal = 0;
    int reviewedCount = 0;

    final sessionResult = await db.query(
      'study_session',
      where: 'dict_name = ? AND session_date = ?',
      whereArgs: [dictName, today],
    );

    if (sessionResult.isNotEmpty) {
      final sessionId = sessionResult.first['id'] as int;

      // 今日新词 = 队列中 is_review = 0 且 is_done = 1
      final newResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM study_session_queue WHERE session_id = ? AND is_review = 0 AND is_done = 1',
        [sessionId],
      );
      todayNewCount = newResult.first['count'] as int? ?? 0;

      // 复习总量 = 队列中 is_review = 1
      final totalResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM study_session_queue WHERE session_id = ? AND is_review = 1',
        [sessionId],
      );
      reviewTotal = totalResult.first['count'] as int? ?? 0;

      // 已复习 = 队列中 is_review = 1 且 is_done = 1
      final doneResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM study_session_queue WHERE session_id = ? AND is_review = 1 AND is_done = 1',
        [sessionId],
      );
      reviewedCount = doneResult.first['count'] as int? ?? 0;
    }

    final reviewCount = reviewTotal - reviewedCount;

    print(
      'DEBUG getDictProgress: 词典=$dictName, 今日新词=$todayNewCount, 复习总量=$reviewTotal, 已复习=$reviewedCount, 待复习=$reviewCount',
    );

    return DictProgress(
      dictName: dictName,
      totalCount: totalCount,
      learnedCount: learnedCount,
      todayNewCount: todayNewCount,
      todayReviewCount: reviewCount,
      todayReviewedCount: reviewedCount,
      todayReviewTotal: reviewTotal,
      settings: settings,
      lastStudyTime: null,
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

  /// 获取今日待学习单词（返回单词文本和ID的映射）
  /// 注意：此方法已废弃，建议使用 getTodayStudyQueue
  @Deprecated('Use getTodayStudyQueue instead')
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
      LEFT JOIN user_study_progress usp ON w.id = usp.word_id AND usp.dict_name = ?
      WHERE d.name = ? AND usp.word_id IS NULL
      ORDER BY $orderBy
      LIMIT ?
    ''',
      [dictName, dictName, settings.dailyWords],
    );

    return {for (var row in results) row['word'] as String: row['id'] as int};
  }

  /// 获取今日待学习单词
  /// 注意：此方法已废弃，建议使用 getTodayStudyQueue
  @Deprecated('Use getTodayStudyQueue instead')
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
      LEFT JOIN user_study_progress usp ON w.id = usp.word_id AND usp.dict_name = ?
      WHERE d.name = ? AND usp.word_id IS NULL
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

  /// 获取今日学习队列（新词 + 复习词穿插）
  ///
  /// 使用 FSRS 算法获取待复习卡片，并与新词穿插组成学习队列。
  Future<List<WordCard>> getTodayStudyQueue(
    String dictName,
    StudySettings settings,
  ) async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);

    // 1. 获取需要复习的 FSRS 卡片（排除今日新词，避免重复）
    final reviewCards = await getDueCardsExcludeTodayNew(dictName, limit: 1000);

    // 2. 计算今日已学新词数量，确定还需要多少新词
    final todayNewWordsResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count FROM user_study_progress
      WHERE dict_name = ? AND DATE(first_learned_date) = ?
    ''',
      [dictName, today],
    );
    final todayLearnedNewCount =
        todayNewWordsResult.first['count'] as int? ?? 0;
    final remainingNewWords = (settings.dailyWords - todayLearnedNewCount)
        .clamp(0, settings.dailyWords);

    // 3. 获取新单词 (剩余需要学习的数量)
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

    final newWordsLimit = remainingNewWords; // 剩余需要学习的新词数量
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

    // 将新词转换为 WordCard（初始化为新卡片）
    final newCards = newWordResults.map((row) {
      return WordCard(
        wordId: row['word_id'] as int,
        word: row['word'] as String,
        dictName: row['dict_name'] as String,
        // 使用默认的 FSRS Card（新卡片状态）
      );
    }).toList();

    // 3. 穿插合并：策略是 2(New):1(Review) 穿插，直到一方耗尽
    final List<WordCard> queue = [];
    int newIndex = 0;
    int reviewIndex = 0;

    while (newIndex < newCards.length || reviewIndex < reviewCards.length) {
      // 添加最多2个新词
      int addedNew = 0;
      while (newIndex < newCards.length && addedNew < 2) {
        queue.add(newCards[newIndex++]);
        addedNew++;
      }

      // 添加1个复习词
      if (reviewIndex < reviewCards.length) {
        queue.add(reviewCards[reviewIndex++]);
      }

      // 如果新词没了，剩下复习词全部加上
      if (newIndex >= newCards.length) {
        while (reviewIndex < reviewCards.length) {
          queue.add(reviewCards[reviewIndex++]);
        }
      }
      // 如果复习词没了，剩下新词全部加上
      else if (reviewIndex >= reviewCards.length) {
        while (newIndex < newCards.length) {
          queue.add(newCards[newIndex++]);
        }
      }
    }

    return queue;
  }

  /// [Debug] 强制将所有学习中/已掌握单词的复习时间提前1天
  Future<void> debugReduceReviewDate() async {
    final db = await database;
    await db.rawUpdate('''
      UPDATE user_study_progress 
      SET next_review_date = datetime(next_review_date, '-1 day')
      WHERE state > 0
    ''');
  }

  /// [Debug] 打印关键表数据
  Future<void> debugPrintTables(String dictName) async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);

    print('\n========== DEBUG: 关键表数据 ($dictName) ==========');
    print('今日日期: $today\n');

    // 1. study_progress 表
    print('--- study_progress ---');
    final studyProgress = await db.query(
      'study_progress',
      where: 'dict_name = ?',
      whereArgs: [dictName],
    );
    if (studyProgress.isEmpty) {
      print('(无数据)');
    } else {
      for (final row in studyProgress) {
        print(
          'daily_words=${row['daily_words']}, mode=${row['study_mode']}, last_study=${row['last_study_time']}',
        );
      }
    }

    // 2. study_session 表
    print('\n--- study_session (最近5条) ---');
    final sessions = await db.rawQuery(
      '''
      SELECT id, dict_name, session_date, current_index, is_completed
      FROM study_session
      WHERE dict_name = ?
      ORDER BY session_date DESC
      LIMIT 5
    ''',
      [dictName],
    );
    if (sessions.isEmpty) {
      print('(无数据)');
    } else {
      for (final row in sessions) {
        print(
          'id=${row['id']}, date=${row['session_date']}, idx=${row['current_index']}, done=${row['is_completed']}',
        );
      }
    }

    // 3. study_session_queue 表 (今日会话)
    print('\n--- study_session_queue (今日) ---');
    final todaySession = await db.query(
      'study_session',
      where: 'dict_name = ? AND session_date = ?',
      whereArgs: [dictName, today],
    );
    if (todaySession.isNotEmpty) {
      final sessionId = todaySession.first['id'] as int;
      final queue = await db.rawQuery(
        '''
        SELECT ssq.queue_index, ssq.word_id, w.word, ssq.is_review, ssq.is_done, ssq.occurrence
        FROM study_session_queue ssq
        JOIN words w ON ssq.word_id = w.id
        WHERE ssq.session_id = ?
        ORDER BY ssq.queue_index
      ''',
        [sessionId],
      );
      print('会话ID: $sessionId, 队列长度: ${queue.length}');
      for (final row in queue) {
        final status = row['is_done'] == 1 ? '✓' : ' ';
        final type = row['is_review'] == 1 ? '复习' : '新词';
        print(
          '[$status] ${row['queue_index']}: ${row['word']} ($type, occ=${row['occurrence']})',
        );
      }
    } else {
      print('(今日无会话)');
    }

    // 4. user_study_progress 表
    print('\n--- user_study_progress (最近20条) ---');
    final progress = await db.rawQuery(
      '''
      SELECT usp.word_id, w.word, usp.due, usp.state, usp.reps, 
             usp.first_learned_date, usp.last_review
      FROM user_study_progress usp
      JOIN words w ON usp.word_id = w.id
      WHERE usp.dict_name = ?
      ORDER BY usp.due ASC
      LIMIT 20
    ''',
      [dictName],
    );
    if (progress.isEmpty) {
      print('(无数据)');
    } else {
      final nowUtc = DateTime.now().toUtc().toIso8601String();
      for (final row in progress) {
        final due = row['due'] as String?;
        final isDue = due != null && due.compareTo(nowUtc) <= 0;
        final isTodayNew = row['first_learned_date'] == today;
        String status = isDue ? '[到期]' : '';
        if (isTodayNew) status += '[今日新]';
        print(
          '${row['word']}: due=${due?.substring(0, 10)}, state=${row['state']}, reps=${row['reps']}, first=${row['first_learned_date']} $status',
        );
      }
    }

    // 5. review_logs 表 (今日)
    print('\n--- review_logs (今日) ---');
    final logs = await db.rawQuery(
      '''
      SELECT rl.word_id, w.word, rl.rating, rl.state, rl.review_datetime
      FROM review_logs rl
      JOIN words w ON rl.word_id = w.id
      WHERE rl.dict_name = ? AND DATE(rl.review_datetime) = ?
      ORDER BY rl.review_datetime DESC
      LIMIT 20
    ''',
      [dictName, today],
    );
    if (logs.isEmpty) {
      print('(今日无复习记录)');
    } else {
      for (final row in logs) {
        print(
          '${row['word']}: rating=${row['rating']}, state=${row['state']}, time=${row['review_datetime']}',
        );
      }
    }

    print('\n==========================================\n');
  }

  // ==================== 学习会话管理 ====================

  /// 今日学习状态枚举
  /// - noSession: 今日没有学习记录
  /// - inProgress: 今日有未完成的学习
  /// - completed: 今日学习已完成
  Future<TodaySessionStatus> getTodaySessionStatus(String dictName) async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);

    // 1. 获取当前进度统计（这是最可靠的数据源）
    final progress = await getDictProgress(dictName);

    // 判断是否还有任务：有到期复习 OR 今日新词未达标（且词典还有词）
    final hasWork =
        progress.todayReviewCount > 0 ||
        (progress.todayNewCount < progress.settings.dailyWords &&
            progress.learnedCount < progress.totalCount);

    if (!hasWork) {
      return TodaySessionStatus.completed;
    }

    // 2. 检查今日是否已开启过会话
    final sessions = await db.query(
      'study_session',
      where: 'dict_name = ? AND session_date = ?',
      whereArgs: [dictName, today],
    );

    return sessions.isEmpty
        ? TodaySessionStatus.noSession
        : TodaySessionStatus.inProgress;
  }

  /// 动态追加到期复习单词到今日会话队列
  ///
  /// 当 ReviewReminderService 检测到新的到期单词时调用此方法，
  /// 将到期单词追加到今日会话末尾。
  ///
  /// 追加条件：单词到期（due <= now）且在队列中最后一次出现已完成
  ///
  /// 返回追加的单词数量，如果今日没有会话则返回 -1
  Future<int> appendDueCardsToTodaySession(String dictName) async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);

    // 检查今日会话是否存在
    final sessionResult = await db.query(
      'study_session',
      where: 'dict_name = ? AND session_date = ?',
      whereArgs: [dictName, today],
    );

    if (sessionResult.isEmpty) {
      return -1; // 今日没有会话
    }

    final sessionId = sessionResult.first['id'] as int;

    // 获取所有到期的复习卡片（包括今日新词，因为它们可能需要重复学习）
    final dueCards = await getDueCards(dictName, limit: 100);

    // 获取当前最大索引
    final maxIdxResult = await db.rawQuery(
      'SELECT MAX(queue_index) as max_idx FROM study_session_queue WHERE session_id = ?',
      [sessionId],
    );
    int nextIdx = (maxIdxResult.first['max_idx'] as int? ?? -1) + 1;

    int addedCount = 0;
    for (final card in dueCards) {
      // 检查该单词在队列中的最后一次出现是否已完成
      final lastOccurrence = await db.rawQuery(
        '''
        SELECT is_done FROM study_session_queue 
        WHERE session_id = ? AND word_id = ?
        ORDER BY queue_index DESC
        LIMIT 1
        ''',
        [sessionId, card.wordId],
      );

      // 如果单词不在队列中，或者最后一次出现已完成，则需要追加
      final shouldAppend =
          lastOccurrence.isEmpty ||
          (lastOccurrence.first['is_done'] as int) == 1;

      if (shouldAppend) {
        // 计算该单词在队列中的出现次数
        final occurrenceResult = await db.rawQuery(
          'SELECT COUNT(*) as count FROM study_session_queue WHERE session_id = ? AND word_id = ?',
          [sessionId, card.wordId],
        );
        final occurrence = (occurrenceResult.first['count'] as int? ?? 0) + 1;

        await db.insert('study_session_queue', {
          'session_id': sessionId,
          'word_id': card.wordId,
          'queue_index': nextIdx++,
          'is_review': 1,
          'is_done': 0,
          'occurrence': occurrence,
        });
        addedCount++;
      }
    }

    if (addedCount > 0) {
      print('DEBUG appendDueCardsToTodaySession: 追加了 $addedCount 个到期复习单词');
    }

    return addedCount;
  }

  /// 获取或创建今日学习会话
  ///
  /// 使用 WordCard 支持 FSRS 算法。
  /// 当会话恢复时，会重新计算所有卡片的 isDue 状态。
  Future<StudySession?> getOrCreateTodaySession(
    String dictName,
    StudySettings settings,
  ) async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);

    // 1. 检查今日会话（无论是否完成）
    final existingSession = await db.query(
      'study_session',
      where: 'dict_name = ? AND session_date = ?',
      whereArgs: [dictName, today],
    );

    if (existingSession.isNotEmpty) {
      final sessionId = existingSession.first['id'] as int;
      int currentIndex = existingSession.first['current_index'] as int;
      final queue = await _getSessionQueue(sessionId, dictName);

      print(
        'DEBUG getOrCreateTodaySession: 恢复会话 $sessionId, 当前队列长度: ${queue.length}',
      );

      // A. 动态追加待复习单词：确保所有到期的复习词都在队列中
      // 使用排除今日新词的方法，避免今日新词被重复添加
      final currentDueCards = await getDueCardsExcludeTodayNew(
        dictName,
        limit: 100,
      );
      final wordIdsInQueue = queue.map((w) => w.wordId).toSet();

      int nextIdx = 0;
      if (queue.isNotEmpty) {
        final maxIdxResult = await db.rawQuery(
          'SELECT MAX(queue_index) as max_idx FROM study_session_queue WHERE session_id = ?',
          [sessionId],
        );
        nextIdx = (maxIdxResult.first['max_idx'] as int? ?? -1) + 1;
      }

      int addedReviewCount = 0;
      for (var card in currentDueCards) {
        if (!wordIdsInQueue.contains(card.wordId)) {
          // 计算该单词在队列中的出现次数
          final occurrenceResult = await db.rawQuery(
            'SELECT COUNT(*) as count FROM study_session_queue WHERE session_id = ? AND word_id = ?',
            [sessionId, card.wordId],
          );
          final occurrence = (occurrenceResult.first['count'] as int? ?? 0) + 1;

          await db.insert('study_session_queue', {
            'session_id': sessionId,
            'word_id': card.wordId,
            'queue_index': nextIdx++,
            'is_review': 1,
            'is_done': 0,
            'occurrence': occurrence,
          });
          card.occurrence = occurrence;
          queue.add(card);
          addedReviewCount++;
        }
      }

      if (addedReviewCount > 0) {
        print('DEBUG: 动态追加了 $addedReviewCount 个待复习单词');
      }

      // B. 动态补全新词：如果每日目标调整，补充新词到目标数量
      final currentNewCount = queue.where((w) => !w.isReview).length;
      int addedNewCount = 0;
      if (currentNewCount < settings.dailyWords) {
        int wordsToFill = settings.dailyWords - currentNewCount;
        for (int i = 0; i < wordsToFill; i++) {
          final nextNew = await getNextNewWordCard(dictName, settings, queue);
          if (nextNew == null) break;

          await db.insert('study_session_queue', {
            'session_id': sessionId,
            'word_id': nextNew.wordId,
            'queue_index': nextIdx++,
            'is_review': 0,
            'is_done': 0,
            'occurrence': 1, // 新词首次出现
          });
          queue.add(nextNew);
          addedNewCount++;
        }

        if (addedNewCount > 0) {
          print('DEBUG: 动态补充了 $addedNewCount 个新词');
        }
      }

      // C. 重新校准当前索引：指向第一个未完成的单词
      final firstUndoneResult = await db.rawQuery(
        'SELECT MIN(queue_index) as idx FROM study_session_queue WHERE session_id = ? AND is_done = 0',
        [sessionId],
      );

      if (firstUndoneResult.isNotEmpty &&
          firstUndoneResult.first['idx'] != null) {
        currentIndex = firstUndoneResult.first['idx'] as int;
      } else {
        currentIndex = queue.length; // 所有单词都已完成
      }

      // 更新数据库中的索引
      await db.update(
        'study_session',
        {'current_index': currentIndex},
        where: 'id = ?',
        whereArgs: [sessionId],
      );

      print(
        'DEBUG: 会话已刷新 - 队列总数: ${queue.length}, 当前索引: $currentIndex, 新词: ${queue.where((w) => !w.isReview).length}, 复习: ${queue.where((w) => w.isReview).length}',
      );

      return StudySession(
        id: sessionId,
        dictName: dictName,
        sessionDate: today,
        currentIndex: currentIndex,
        queue: queue,
      );
    }

    // 2. 创建新会话：生成今日学习队列
    final queue = await getTodayStudyQueue(dictName, settings);
    print(
      'DEBUG: 创建新会话 - 队列大小: ${queue.length}, 新词: ${queue.where((w) => !w.isReview).length}, 复习: ${queue.where((w) => w.isReview).length}',
    );
    if (queue.isEmpty) {
      print('DEBUG: 队列为空，没有需要学习的单词');
      return null;
    }

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
        'occurrence': 1, // 初始队列中的单词都是首次出现
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

  /// 获取会话队列 - FSRS 版本
  ///
  /// 返回 WordCard 列表，支持 FSRS 算法。
  /// 当会话恢复时，会重新计算所有卡片的 isDue 状态。
  ///
  /// _Requirements: 10.1, 10.2_
  Future<List<WordCard>> _getSessionQueue(
    int sessionId,
    String dictName,
  ) async {
    final db = await database;
    final results = await db.rawQuery(
      '''
      SELECT ssq.*, w.word, 
             usp.due, usp.stability, usp.difficulty,
             usp.elapsed_days, usp.scheduled_days, usp.reps, usp.lapses,
             usp.state, usp.last_review, usp.first_learned_date,
             ssq.is_review as is_review_flag,
             ssq.occurrence
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
      final wordId = row['word_id'] as int;
      final word = row['word'] as String;
      final occurrence = row['occurrence'] as int? ?? 1;

      // 检查是否有 FSRS 数据
      final hasFsrsData =
          row['due'] != null && (row['due'] as String).isNotEmpty;

      if (hasFsrsData) {
        // 有 FSRS 数据，从数据库构建 WordCard
        return WordCard.fromMap({
          'word_id': wordId,
          'word': word,
          'dict_name': dictName,
          'due': row['due'] as String,
          'stability': row['stability'] as num? ?? 0.0,
          'difficulty': row['difficulty'] as num? ?? 5.0,
          'elapsed_days': row['elapsed_days'] as int? ?? 0,
          'scheduled_days': row['scheduled_days'] as int? ?? 0,
          'reps': row['reps'] as int? ?? 0,
          'lapses': row['lapses'] as int? ?? 0,
          'state': row['state'] as int? ?? 0,
          'last_review': row['last_review'] as String?,
          'first_learned_date': row['first_learned_date'] as String?,
          'occurrence': occurrence,
        });
      } else {
        // 没有 FSRS 数据，创建新卡片
        return WordCard(
          wordId: wordId,
          word: word,
          dictName: dictName,
          occurrence: occurrence,
          // 使用默认的 FSRS Card（新卡片状态）
        );
      }
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
    // 获取队列长度作为最终索引
    final countResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM study_session_queue WHERE session_id = ?',
      [sessionId],
    );
    final total = countResult.first['count'] as int? ?? 0;

    await db.update(
      'study_session',
      {'current_index': total},
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
  ///
  /// 会自动计算该单词在队列中的出现次数（occurrence）
  Future<void> addWordToSessionQueue(int sessionId, int wordId) async {
    final db = await database;

    // 动态获取当前最高索引
    final maxResult = await db.rawQuery(
      'SELECT MAX(queue_index) as max_idx FROM study_session_queue WHERE session_id = ?',
      [sessionId],
    );
    final nextIndex = (maxResult.first['max_idx'] as int? ?? -1) + 1;

    // 计算该单词在队列中的出现次数
    final occurrenceResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM study_session_queue WHERE session_id = ? AND word_id = ?',
      [sessionId, wordId],
    );
    final occurrence = (occurrenceResult.first['count'] as int? ?? 0) + 1;

    await db.insert('study_session_queue', {
      'session_id': sessionId,
      'word_id': wordId,
      'queue_index': nextIndex,
      'is_review': 1,
      'is_done': 0,
      'occurrence': occurrence,
    });

    print(
      'DEBUG: Dynamic Append: WordId $wordId added to queue at index $nextIndex, occurrence: $occurrence',
    );
  }

  /// 获取下一个新词（用于补充队列）
  ///
  /// 返回 WordCard 对象，用于 FSRS 会话队列。
  Future<WordCard?> getNextNewWordCard(
    String dictName,
    StudySettings settings,
    List<WordCard> currentQueue,
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

    // 创建新的 WordCard（新卡片状态）
    return WordCard(
      wordId: results.first['word_id'] as int,
      word: results.first['word'] as String,
      dictName: results.first['dict_name'] as String,
      // 使用默认的 FSRS Card（新卡片状态）
    );
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

/// 今日学习状态
enum TodaySessionStatus {
  noSession, // 今日没有学习记录
  inProgress, // 今日有未完成的学习
  completed, // 今日学习已完成
}

// ==================== 打卡统计 ====================

extension DBHelperStreak on DBHelper {
  /// 获取连续打卡天数
  Future<int> getStudyStreak() async {
    final db = await database;

    // 获取所有有学习记录的日期（已完成的会话）
    final result = await db.rawQuery('''
      SELECT DISTINCT DATE(session_date) as study_date
      FROM study_session
      WHERE is_completed = 1
      ORDER BY study_date DESC
    ''');

    if (result.isEmpty) return 0;

    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    int streak = 0;
    DateTime checkDate = today;

    // 如果今天还没学习，从昨天开始计算
    final firstStudyDate = result.first['study_date'] as String;
    if (firstStudyDate != todayStr) {
      checkDate = today.subtract(const Duration(days: 1));
    }

    for (final row in result) {
      final studyDateStr = row['study_date'] as String;
      final parts = studyDateStr.split('-');
      final studyDate = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );

      final checkDateStr =
          '${checkDate.year}-${checkDate.month.toString().padLeft(2, '0')}-${checkDate.day.toString().padLeft(2, '0')}';

      if (studyDateStr == checkDateStr) {
        streak++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      } else if (studyDate.isBefore(checkDate)) {
        // 中断了
        break;
      }
    }

    return streak;
  }

  /// 获取指定日期范围内的学习日期
  Future<Set<DateTime>> getStudiedDatesInRange(
    DateTime start,
    DateTime end,
  ) async {
    final db = await database;

    final startStr =
        '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
    final endStr =
        '${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}';

    final result = await db.rawQuery(
      '''
      SELECT DISTINCT DATE(session_date) as study_date
      FROM study_session
      WHERE is_completed = 1
        AND DATE(session_date) >= ?
        AND DATE(session_date) <= ?
    ''',
      [startStr, endStr],
    );

    final dates = <DateTime>{};
    for (final row in result) {
      final dateStr = row['study_date'] as String;
      final parts = dateStr.split('-');
      dates.add(
        DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2])),
      );
    }

    return dates;
  }
}
