/// 一次学习会话
import 'package:ai_vocab/models/word_progress.dart';

class StudySession {
  final int id;
  final String dictName;
  final String sessionDate;
  final int currentIndex;
  final List<WordProgress> queue;
  final int newWordsCount; // 会话中包含的新词数量
  final int reviewWordsCount; // 会话中包含的复习词数量

  StudySession({
    required this.id,
    required this.dictName,
    required this.sessionDate,
    required this.currentIndex,
    required this.queue,
  }) : newWordsCount = queue.where((w) => !w.isReview).length,
       reviewWordsCount = queue.where((w) => w.isReview).length;
}
