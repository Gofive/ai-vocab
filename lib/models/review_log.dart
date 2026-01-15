import 'package:fsrs/fsrs.dart';

/// 复习日志模型
///
/// 记录每次复习的详细信息，用于未来的 FSRS 参数优化。
///
/// 数据库字段说明：
/// - id: 自增主键
/// - word_id: 单词 ID
/// - dict_name: 词典名称
/// - rating: 用户评分 (1=Again, 2=Hard, 3=Good, 4=Easy)
/// - state: 复习前的卡片状态
/// - due: 复习前的到期时间
/// - stability: 复习后的稳定性
/// - difficulty: 复习后的难度
/// - elapsed_days: 自上次复习以来的天数
/// - scheduled_days: 计划的复习间隔天数
/// - review_datetime: 复习时间
///
/// _Requirements: 9.1, 9.2, 9.4_
class ReviewLogEntry {
  final int? id;
  final int wordId;
  final String dictName;
  final Rating rating;
  final State state;
  final DateTime due;
  final double stability;
  final double difficulty;
  final int elapsedDays;
  final int scheduledDays;
  final DateTime reviewDatetime;

  ReviewLogEntry({
    this.id,
    required this.wordId,
    required this.dictName,
    required this.rating,
    required this.state,
    required this.due,
    required this.stability,
    required this.difficulty,
    required this.elapsedDays,
    required this.scheduledDays,
    required this.reviewDatetime,
  });

  /// 从 FSRS ReviewLog 和卡片信息创建
  ///
  /// [wordId] - 单词 ID
  /// [dictName] - 词典名称
  /// [fsrsLog] - FSRS 库返回的 ReviewLog 对象
  /// [reviewDatetime] - 复习时间（可选，默认使用 fsrsLog 中的时间）
  factory ReviewLogEntry.fromFSRSLog({
    required int wordId,
    required String dictName,
    required ReviewLog fsrsLog,
    DateTime? reviewDatetime,
  }) {
    // 从 FSRS ReviewLog 的 toMap 获取数据
    final logMap = fsrsLog.toMap();

    // 安全获取 state，默认为 Learning (index 0)
    final stateIndex = (logMap['state'] as int?) ?? 0;

    // 安全获取 elapsedDays 和 scheduledDays
    final elapsedDays = (logMap['elapsedDays'] as int?) ?? 0;
    final scheduledDays = (logMap['scheduledDays'] as int?) ?? 0;

    return ReviewLogEntry(
      wordId: wordId,
      dictName: dictName,
      rating: fsrsLog.rating,
      state: State.values[stateIndex],
      due: DateTime.parse(
        logMap['due'] as String? ?? DateTime.now().toUtc().toIso8601String(),
      ),
      stability: (logMap['stability'] as num?)?.toDouble() ?? 0.0,
      difficulty: (logMap['difficulty'] as num?)?.toDouble() ?? 5.0,
      elapsedDays: elapsedDays,
      scheduledDays: scheduledDays,
      reviewDatetime:
          reviewDatetime ??
          DateTime.tryParse(logMap['reviewDateTime'] as String? ?? '') ??
          DateTime.now().toUtc(),
    );
  }

  /// 从数据库 Map 创建
  factory ReviewLogEntry.fromMap(Map<String, dynamic> map) {
    return ReviewLogEntry(
      id: map['id'] as int?,
      wordId: map['word_id'] as int,
      dictName: map['dict_name'] as String,
      rating: Rating.values[map['rating'] as int],
      state: State.values[map['state'] as int],
      due: DateTime.parse(map['due'] as String),
      stability: (map['stability'] as num).toDouble(),
      difficulty: (map['difficulty'] as num).toDouble(),
      elapsedDays: map['elapsed_days'] as int,
      scheduledDays: map['scheduled_days'] as int,
      reviewDatetime: DateTime.parse(map['review_datetime'] as String),
    );
  }

  /// 转换为数据库 Map
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'word_id': wordId,
      'dict_name': dictName,
      'rating': rating.index,
      'state': state.index,
      'due': due.toIso8601String(),
      'stability': stability,
      'difficulty': difficulty,
      'elapsed_days': elapsedDays,
      'scheduled_days': scheduledDays,
      'review_datetime': reviewDatetime.toIso8601String(),
    };
  }

  @override
  String toString() {
    return 'ReviewLogEntry(wordId: $wordId, dictName: $dictName, '
        'rating: $rating, state: $state, due: $due, '
        'stability: $stability, difficulty: $difficulty, '
        'elapsedDays: $elapsedDays, scheduledDays: $scheduledDays, '
        'reviewDatetime: $reviewDatetime)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ReviewLogEntry) return false;

    return wordId == other.wordId &&
        dictName == other.dictName &&
        rating == other.rating &&
        state == other.state &&
        due == other.due &&
        stability == other.stability &&
        difficulty == other.difficulty &&
        elapsedDays == other.elapsedDays &&
        scheduledDays == other.scheduledDays &&
        reviewDatetime == other.reviewDatetime;
  }

  @override
  int get hashCode {
    return Object.hash(
      wordId,
      dictName,
      rating,
      state,
      due,
      stability,
      difficulty,
      elapsedDays,
      scheduledDays,
      reviewDatetime,
    );
  }
}
