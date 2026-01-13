class UsageStack {
  final String definition;
  final String? collocation; // 固定搭配
  final String enSentence;
  final String zhSentence;
  final String? sentenceTts;

  UsageStack({
    required this.definition,
    this.collocation,
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

  /// 获取所有释义（去重）
  List<String> get definitions =>
      usageStacks.map((s) => s.definition).toSet().toList();

  /// 获取所有固定搭配（去重）
  List<String> get allCollocations {
    final Set<String> result = {};
    for (var stack in usageStacks) {
      if (stack.collocation != null && stack.collocation!.isNotEmpty) {
        // 解析格式: "a lot of (许多)；a few (几个)"
        final parts = stack.collocation!.split('；');
        for (var part in parts) {
          final trimmed = part.trim();
          if (trimmed.isNotEmpty) result.add(trimmed);
        }
      }
    }
    return result.toList();
  }

  factory WordDetail.fromSqlList(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) throw Exception("Word not found");

    final firstRow = rows.first;

    List<UsageStack> stacks = [];
    for (var row in rows) {
      if (row['en_sentence'] != null) {
        stacks.add(
          UsageStack(
            definition: row['definition'] ?? '',
            collocation: row['collocation'],
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
