// lib/models/word_model.dart

class UsageStack {
  final String definition;
  final String enSentence;
  final String zhSentence;
  final String? sentenceTts;

  UsageStack({
    required this.definition,
    required this.enSentence,
    required this.zhSentence,
    this.sentenceTts,
  });
}

class WordDetail {
  final int id;
  final String word;
  final String phonetic;
  final String mnemonic;
  final String? ttsPath;
  final List<UsageStack> usageStacks;

  WordDetail({
    required this.id,
    required this.word,
    required this.phonetic,
    required this.mnemonic,
    this.ttsPath,
    required this.usageStacks,
  });

  /// 工厂方法：将数据库查询到的 List<Map> 转换为 WordDetail 对象
  /// 因为 SQL JOIN 查询会返回多行（一个单词对应多个例句），我们需要合并它们
  factory WordDetail.fromSqlList(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) throw Exception("Word not found");

    final firstRow = rows.first;

    // 提取例句列表
    List<UsageStack> stacks = [];
    for (var row in rows) {
      if (row['en_sentence'] != null) {
        stacks.add(
          UsageStack(
            definition: row['definition'] ?? '',
            enSentence: row['en_sentence'] ?? '',
            zhSentence: row['zh_sentence'] ?? '',
            sentenceTts: row['sentence_tts'],
          ),
        );
      }
    }

    return WordDetail(
      id: firstRow['id'],
      word: firstRow['word'],
      phonetic: firstRow['phonetic'] ?? '',
      mnemonic: firstRow['mnemonic'] ?? '',
      ttsPath: firstRow['tts_path'],
      usageStacks: stacks,
    );
  }
}
