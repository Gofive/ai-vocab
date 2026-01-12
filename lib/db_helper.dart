// lib/db_helper.dart
import 'dart:io';
import 'package:ai_vocab/word_model.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class DBHelper {
  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    // 1. Windows 平台特有的初始化 (解决 Bad state 错误)
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi; // 关键：指定工厂
    }

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, "vocab.db");
    final file = File(path);

    // 2. 自动复制逻辑 (确保不是空数据库)
    if (!await file.exists() || await file.length() < 10 * 1024) {
      print("--- 正在从 Assets 复制数据库 ---");
      try {
        await Directory(dirname(path)).create(recursive: true);
        ByteData data = await rootBundle.load("assets/vocab.db");
        List<int> bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        await file.writeAsBytes(bytes, flush: true);
      } catch (e) {
        print("--- 复制出错: $e ---");
      }
    }

    // 3. 使用工厂打开数据库
    return await databaseFactory.openDatabase(path);
  }

  /// 根据单词文本查询详细信息
  Future<WordDetail?> getWordDetail(String wordText) async {
    final db = await database;

    // 使用 JOIN 一次性查出单词和所有例句
    final List<Map<String, dynamic>> results = await db.rawQuery(
      '''
      SELECT w.*, s.definition, s.en_sentence, s.zh_sentence, s.sentence_tts
      FROM words w
      LEFT JOIN usage_stacks s ON w.id = s.word_id
      WHERE w.word = ?
    ''',
      [wordText],
    );

    if (results.isEmpty) return null;

    return WordDetail.fromSqlList(results);
  }

  /// 获取指定词典下的所有单词列表（用于背诵翻页）
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
