/// 学习模式
enum StudyMode {
  sequential, // 按顺序
  byDifficulty, // 按难度
  random, // 随机
}

/// 学习设置
class StudySettings {
  final int dailyWords;
  final StudyMode mode;

  const StudySettings({this.dailyWords = 20, this.mode = StudyMode.sequential});

  Map<String, dynamic> toJson() => {
    'dailyWords': dailyWords,
    'mode': mode.index,
  };

  factory StudySettings.fromJson(Map<String, dynamic> json) => StudySettings(
    dailyWords: json['dailyWords'] ?? 20,
    mode: StudyMode.values[json['mode'] ?? 0],
  );
}

/// 词典学习进度
class DictProgress {
  final String dictName;
  final int learnedCount;
  final int totalCount;
  final StudySettings settings;
  final DateTime? lastStudyTime;
  final int todayNewCount; // 今日新学单词数
  final int todayReviewCount; // 今日待复习数

  const DictProgress({
    required this.dictName,
    this.learnedCount = 0,
    this.totalCount = 0,
    required this.settings,
    this.lastStudyTime,
    this.todayNewCount = 0,
    this.todayReviewCount = 0,
  });

  double get progress => totalCount > 0 ? learnedCount / totalCount : 0;
}
