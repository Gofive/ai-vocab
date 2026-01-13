/// 单词学习状态
enum WordState {
  newWord, // 新词
  learning, // 学习中
  mastered, // 已掌握
}

/// 单词学习进度模型 (SM-2 算法)
class WordProgress {
  final int wordId;
  final String word;
  final String dictName;
  double easeFactor; // 简单系数 EF，默认 2.5
  int interval; // 复习间隔天数
  DateTime? nextReviewDate; // 下次复习日期
  WordState state; // 学习状态
  DateTime? lastModified;
  bool isReview; // 是否是复习单词（用于UI显示）

  WordProgress({
    required this.wordId,
    required this.word,
    required this.dictName,
    this.easeFactor = 2.5,
    this.interval = 0,
    this.nextReviewDate,
    this.state = WordState.newWord,
    this.lastModified,
    this.isReview = false,
  });

  /// 根据用户反馈更新进度 (SM-2 算法)
  /// quality: 0-5 分，0-2 表示记不住，3-5 表示记得
  void updateWithQuality(int quality) {
    lastModified = DateTime.now();

    if (quality < 3) {
      // 记不住，重置间隔
      interval = 1;
      state = WordState.learning;
    } else {
      // 记得，计算新间隔
      if (interval == 0) {
        interval = 1;
      } else if (interval == 1) {
        interval = 6;
      } else {
        interval = (interval * easeFactor).round();
      }

      // 更新简单系数 EF
      easeFactor =
          easeFactor + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));
      if (easeFactor < 1.3) easeFactor = 1.3;

      // 更新状态
      if (quality >= 4 && interval >= 21) {
        state = WordState.mastered;
      } else {
        state = WordState.learning;
      }
    }

    // 计算下次复习日期
    nextReviewDate = DateTime.now().add(Duration(days: interval));
  }

  /// 从数据库行创建
  factory WordProgress.fromMap(
    Map<String, dynamic> map, {
    bool isReview = false,
  }) {
    return WordProgress(
      wordId: map['word_id'] as int,
      word: map['word'] as String? ?? '',
      dictName: map['dict_name'] as String? ?? '',
      easeFactor: (map['ease_factor'] as num?)?.toDouble() ?? 2.5,
      interval: map['interval'] as int? ?? 0,
      nextReviewDate: map['next_review_date'] != null
          ? DateTime.parse(map['next_review_date'] as String)
          : null,
      state: WordState.values[map['state'] as int? ?? 0],
      lastModified: map['last_modified'] != null
          ? DateTime.parse(map['last_modified'] as String)
          : null,
      isReview: isReview,
    );
  }

  /// 转换为数据库 Map
  Map<String, dynamic> toMap() {
    return {
      'word_id': wordId,
      'dict_name': dictName,
      'ease_factor': easeFactor,
      'interval': interval,
      'next_review_date': nextReviewDate?.toIso8601String(),
      'state': state.index,
      'last_modified': lastModified?.toIso8601String(),
    };
  }
}
