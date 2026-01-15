import 'package:fsrs/fsrs.dart';

/// FSRS 单词卡片模型
///
/// 包装 FSRS Card 对象，添加单词元数据（wordId, word, dictName）。
/// 用于替代旧的 WordProgress 模型，支持 FSRS 算法的间隔重复调度。
///
/// 数据库字段说明：
/// - word_id: 单词 ID
/// - dict_name: 词典名称
/// - due: 下次复习时间 (ISO8601)
/// - stability: 记忆稳定性
/// - difficulty: 单词难度 (1-10)
/// - elapsed_days: 自上次复习以来的天数
/// - scheduled_days: 计划的复习间隔天数
/// - reps: 成功复习次数
/// - lapses: 遗忘次数
/// - state: 卡片状态 (1=Learning, 2=Review, 3=Relearning)
/// - last_review: 上次复习时间 (ISO8601)
class WordCard {
  final int wordId;
  final String word;
  final String dictName;
  Card card; // FSRS Card 对象

  // 额外的数据库字段（用于统计和迁移）
  int elapsedDays;
  int reps;
  int lapses;

  WordCard({
    required this.wordId,
    required this.word,
    required this.dictName,
    Card? card,
    this.elapsedDays = 0,
    this.reps = 0,
    this.lapses = 0,
  }) : card = card ?? Card(cardId: 0);

  /// 是否到期需要复习
  ///
  /// 当卡片的 due 时间早于或等于当前时间时，返回 true
  bool get isDue {
    final now = DateTime.now().toUtc();
    return card.due.isBefore(now) || card.due.isAtSameMomentAs(now);
  }

  /// 是否是复习卡片（非新卡）
  ///
  /// 当卡片状态不是 Learning（新卡初始状态）时，返回 true
  /// FSRS 状态: Learning(1), Review(2), Relearning(3)
  bool get isReview => card.state != State.learning;

  /// 从数据库 Map 创建 WordCard
  ///
  /// [map] 应包含以下字段：
  /// - word_id: int
  /// - word: String (可选)
  /// - dict_name: String (可选)
  /// - due: String (ISO8601 格式)
  /// - stability: num
  /// - difficulty: num
  /// - elapsed_days: int
  /// - scheduled_days: int
  /// - reps: int
  /// - lapses: int
  /// - state: int (State 枚举索引)
  /// - last_review: String? (ISO8601 格式，可选)
  factory WordCard.fromMap(Map<String, dynamic> map) {
    final wordId = map['word_id'] as int;

    // 安全获取值，提供默认值
    final dueStr =
        map['due'] as String? ?? DateTime.now().toUtc().toIso8601String();
    final stability = (map['stability'] as num?)?.toDouble() ?? 0.0;
    final difficulty = (map['difficulty'] as num?)?.toDouble() ?? 5.0;
    final scheduledDays = map['scheduled_days'] as int? ?? 0;
    final state = map['state'] as int? ?? 0;

    // 构建 Card 的 map 用于反序列化
    final cardMap = <String, dynamic>{
      'cardId': wordId, // 使用 wordId 作为 cardId
      'due': dueStr,
      'stability': stability,
      'difficulty': difficulty,
      'scheduledDays': scheduledDays,
      'state': state,
    };

    // 可选字段
    if (map['last_review'] != null) {
      cardMap['lastReview'] = map['last_review'] as String;
    }

    return WordCard(
      wordId: wordId,
      word: map['word'] as String? ?? '',
      dictName: map['dict_name'] as String? ?? '',
      card: Card.fromMap(cardMap),
      elapsedDays: map['elapsed_days'] as int? ?? 0,
      reps: map['reps'] as int? ?? 0,
      lapses: map['lapses'] as int? ?? 0,
    );
  }

  /// 转换为数据库 Map
  ///
  /// 返回包含所有 FSRS 卡片字段的 Map，用于数据库存储
  Map<String, dynamic> toMap() {
    final cardMap = card.toMap();

    return {
      'word_id': wordId,
      'dict_name': dictName,
      'due': cardMap['due'] as String? ?? card.due.toUtc().toIso8601String(),
      'stability': (cardMap['stability'] as num?)?.toDouble() ?? card.stability,
      'difficulty':
          (cardMap['difficulty'] as num?)?.toDouble() ?? card.difficulty,
      'elapsed_days': elapsedDays,
      'scheduled_days': (cardMap['scheduledDays'] as int?) ?? 0,
      'reps': reps,
      'lapses': lapses,
      'state': (cardMap['state'] as int?) ?? card.state.index,
      'last_review': cardMap['lastReview'] as String?,
    };
  }

  /// 创建 WordCard 的副本
  ///
  /// 可选择性地覆盖某些字段
  WordCard copyWith({
    int? wordId,
    String? word,
    String? dictName,
    Card? card,
    int? elapsedDays,
    int? reps,
    int? lapses,
  }) {
    return WordCard(
      wordId: wordId ?? this.wordId,
      word: word ?? this.word,
      dictName: dictName ?? this.dictName,
      card: card ?? Card.fromMap(this.card.toMap()),
      elapsedDays: elapsedDays ?? this.elapsedDays,
      reps: reps ?? this.reps,
      lapses: lapses ?? this.lapses,
    );
  }

  @override
  String toString() {
    return 'WordCard(wordId: $wordId, word: $word, dictName: $dictName, '
        'due: ${card.due}, state: ${card.state}, reps: $reps, lapses: $lapses)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! WordCard) return false;

    final cardMap = card.toMap();
    final otherCardMap = other.card.toMap();

    return wordId == other.wordId &&
        word == other.word &&
        dictName == other.dictName &&
        cardMap['due'] == otherCardMap['due'] &&
        cardMap['stability'] == otherCardMap['stability'] &&
        cardMap['difficulty'] == otherCardMap['difficulty'] &&
        cardMap['scheduledDays'] == otherCardMap['scheduledDays'] &&
        cardMap['state'] == otherCardMap['state'] &&
        cardMap['lastReview'] == otherCardMap['lastReview'] &&
        elapsedDays == other.elapsedDays &&
        reps == other.reps &&
        lapses == other.lapses;
  }

  @override
  int get hashCode {
    final cardMap = card.toMap();
    return Object.hash(
      wordId,
      word,
      dictName,
      cardMap['due'],
      cardMap['stability'],
      cardMap['difficulty'],
      cardMap['scheduledDays'],
      cardMap['state'],
      cardMap['lastReview'],
      elapsedDays,
      reps,
      lapses,
    );
  }
}
