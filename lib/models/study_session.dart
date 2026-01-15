/// 一次学习会话
library;

import 'package:ai_vocab/models/word_card.dart';

/// FSRS 学习会话模型
///
/// 使用 WordCard 替代 WordProgress，支持 FSRS 算法的间隔重复调度。
///
/// _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_
class StudySession {
  final int id;
  final String dictName;
  final String sessionDate;
  final int currentIndex;
  final List<WordCard> queue;

  StudySession({
    required this.id,
    required this.dictName,
    required this.sessionDate,
    required this.currentIndex,
    required this.queue,
  });

  /// 会话中包含的新词数量
  /// 新词 = 非复习卡片（isReview = false）
  int get newWordsCount => queue.where((w) => !w.isReview).length;

  /// 会话中包含的复习词数量
  /// 复习词 = 复习卡片（isReview = true）
  int get reviewWordsCount => queue.where((w) => w.isReview).length;

  /// 会话是否已完成
  /// 当 currentIndex >= queue.length 时，会话完成
  bool get isCompleted => currentIndex >= queue.length;
}
