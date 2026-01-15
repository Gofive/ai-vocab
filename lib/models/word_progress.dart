/// 单词学习状态
@Deprecated(
  'Use FSRS State instead. This enum is part of the SM-2 algorithm which has been replaced by FSRS.',
)
enum WordState {
  newWord, // 新词
  learning, // 学习中
  mastered, // 已掌握
}

/// 单词学习进度模型 (改进版 SM-2 算法)
///
/// 此类已废弃，请使用 [WordCard] 替代。
/// FSRS 算法提供更精准的记忆预测能力。
///
/// _Requirements: 3.1_
@Deprecated('Use WordCard instead. SM-2 algorithm has been replaced by FSRS.')
class WordProgress {
  final int wordId;
  final String word;
  final String dictName;
  double easeFactor; // 简单系数 EF，默认 2.5
  int interval; // 复习间隔天数
  int repetition; // 成功复习次数（答错重置为0）
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
    this.repetition = 0,
    this.nextReviewDate,
    this.state = WordState.newWord,
    this.lastModified,
    this.isReview = false,
  });

  /// 根据用户反馈更新进度 (改进版 SM-2 算法)
  /// quality: 0-5 分
  /// - 0-2: 答错（没记住）
  /// - 3: 困难（有印象）
  /// - 4-5: 简单（记住了）
  void updateWithQuality(int quality) {
    lastModified = DateTime.now();

    if (quality >= 3) {
      // 答对了
      if (repetition == 0) {
        if (quality >= 5) {
          interval = 3; // 记住了：新词直接跨越到3天
        } else {
          interval = 1; // 有印象：标准1天
        }
        repetition = 1;
      } else if (repetition == 1) {
        // 第二次：根据难度设为 3-6 天
        if (quality >= 5) {
          interval = 6;
        } else if (quality >= 4) {
          interval = 4;
        } else {
          interval = 3;
        }
        repetition = 2;
      } else {
        interval = (interval * easeFactor).round();
        repetition += 1;
      }

      // 更新 EF 系数
      easeFactor =
          easeFactor + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));

      // 更新状态
      if (quality >= 4 && interval >= 21) {
        state = WordState.mastered;
      } else {
        state = WordState.learning;
      }
    } else {
      // 答错了
      repetition = 0; // 重置复习次数
      interval = 1; // 明天必须复习
      easeFactor -= 0.2; // 降低 EF
      state = WordState.learning;
    }

    // EF 边界保护：最小 1.3
    if (easeFactor < 1.3) easeFactor = 1.3;

    // 计算下次复习日期
    nextReviewDate = DateTime.now().add(Duration(days: interval));
  }

  /// 预计算点击某个 quality 后的下次复习间隔（用于 UI 显示）
  static int previewNextInterval(
    int quality,
    int currentInterval,
    double currentEF,
    int currentRepetition,
  ) {
    if (quality >= 3) {
      if (currentRepetition == 0) {
        if (quality >= 5) {
          return 3;
        } else {
          return 1;
        }
      } else if (currentRepetition == 1) {
        // 第二次：根据难度设为 3-6 天
        if (quality >= 5) {
          return 6;
        } else if (quality >= 4) {
          return 4;
        } else {
          return 3;
        }
      } else {
        return (currentInterval * currentEF).round();
      }
    } else {
      return 1;
    }
  }

  /// 格式化间隔天数为可读字符串
  static String formatInterval(int days) {
    if (days >= 365) return '${(days / 365).round()}年';
    if (days >= 30) return '${(days / 30).round()}月';
    return '$days天';
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
      repetition: map['repetition'] as int? ?? 0,
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
      'repetition': repetition,
      'next_review_date': nextReviewDate?.toIso8601String(),
      'state': state.index,
      'last_modified': lastModified?.toIso8601String(),
    };
  }
}
