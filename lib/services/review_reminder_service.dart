import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:ai_vocab/db_helper.dart';

/// 复习提醒信息
class ReviewReminderInfo {
  final int dueCount; // 到期待复习数量
  final int urgentCount; // 紧急待复习数量（超过24小时未复习）
  final DateTime? nextDueTime; // 下一个到期时间
  final List<DueWordInfo> dueWords; // 到期单词列表（前几个）

  const ReviewReminderInfo({
    this.dueCount = 0,
    this.urgentCount = 0,
    this.nextDueTime,
    this.dueWords = const [],
  });

  bool get hasDueWords => dueCount > 0;
  bool get hasUrgentWords => urgentCount > 0;
}

/// 到期单词信息
class DueWordInfo {
  final int wordId;
  final String word;
  final DateTime dueTime;
  final bool isUrgent; // 是否紧急（超过24小时）

  const DueWordInfo({
    required this.wordId,
    required this.word,
    required this.dueTime,
    this.isUrgent = false,
  });
}

/// 复习提醒服务
///
/// 提供类似 drift watchQuery 的响应式 API。
///
/// 使用方式：
/// ```dart
/// // 监听到期单词变化
/// ReviewReminderService().watchDueWords('词典名').listen((info) {
///   print('待复习: ${info.dueCount}');
/// });
///
/// // 或使用 ChangeNotifier
/// ListenableBuilder(
///   listenable: ReviewReminderService(),
///   builder: (context, _) => Text('${ReviewReminderService().dueCount}'),
/// );
/// ```
///
/// 注意：SQLite 不支持原生订阅，通过以下机制模拟：
/// 1. 数据变更时调用 notifyChange() 触发 Stream 更新
/// 2. 定时检查作为兜底（每5分钟）
class ReviewReminderService extends ChangeNotifier {
  static final ReviewReminderService _instance =
      ReviewReminderService._internal();
  factory ReviewReminderService() => _instance;
  ReviewReminderService._internal();

  // Stream 控制器，用于提供类似 watchQuery 的 API
  final _streamController = StreamController<ReviewReminderInfo>.broadcast();

  Timer? _checkTimer;
  String? _currentDictName;
  ReviewReminderInfo _reminderInfo = const ReviewReminderInfo();

  // 防抖
  DateTime? _lastRefreshTime;
  static const _debounceInterval = Duration(milliseconds: 300);

  /// 当前提醒信息
  ReviewReminderInfo get reminderInfo => _reminderInfo;

  /// 是否有待复习单词
  bool get hasDueWords => _reminderInfo.hasDueWords;

  /// 待复习数量
  int get dueCount => _reminderInfo.dueCount;

  /// 监听到期单词变化（类似 drift 的 watchQuery）
  ///
  /// 返回一个 Stream，每当数据变化时会推送新的 ReviewReminderInfo。
  /// 调用 notifyChange() 或定时检查时会触发更新。
  Stream<ReviewReminderInfo> watchDueWords(String dictName) {
    // 确保服务已初始化
    if (_currentDictName != dictName) {
      _currentDictName = dictName;
      _checkDueWordsAndNotify();
    }
    return _streamController.stream;
  }

  /// 初始化服务
  Future<void> initialize(
    String dictName, {
    Duration checkInterval = const Duration(minutes: 5),
  }) async {
    _currentDictName = dictName;
    await _checkDueWordsAndNotify();
    _startPeriodicCheck(checkInterval);
  }

  /// 更新当前词典
  Future<void> updateDictName(String dictName) async {
    if (_currentDictName != dictName) {
      _currentDictName = dictName;
      await _checkDueWordsAndNotify();
    }
  }

  /// 通知数据变更（供外部调用）
  ///
  /// 在 saveWordCard、completeSession 等操作后调用此方法，
  /// 触发 Stream 更新，实现类似 drift watchQuery 的效果。
  Future<void> notifyChange() async {
    final now = DateTime.now();
    if (_lastRefreshTime != null &&
        now.difference(_lastRefreshTime!) < _debounceInterval) {
      return;
    }
    _lastRefreshTime = now;
    await _checkDueWordsAndNotify();
  }

  /// 刷新（别名，兼容旧代码）
  Future<void> refresh() => notifyChange();

  /// 强制刷新
  Future<void> forceRefresh() async {
    _lastRefreshTime = null;
    await _checkDueWordsAndNotify();
  }

  /// 检查待复习单词并通知
  Future<void> _checkDueWordsAndNotify() async {
    if (_currentDictName == null) {
      debugPrint('ReviewReminderService: 词典名为空，跳过检查');
      return;
    }

    try {
      final db = DBHelper();
      final now = DateTime.now().toUtc();
      final yesterday = now.subtract(const Duration(hours: 24));

      debugPrint('ReviewReminderService: 检查词典 $_currentDictName 的待复习单词...');
      final dueCards = await db.getDueCards(_currentDictName!, limit: 100);
      debugPrint('ReviewReminderService: getDueCards 返回 ${dueCards.length} 个');

      // 动态追加到期单词到今日会话队列
      if (dueCards.isNotEmpty) {
        final addedCount = await db.appendDueCardsToTodaySession(
          _currentDictName!,
        );
        if (addedCount > 0) {
          debugPrint('ReviewReminderService: 已追加 $addedCount 个到期单词到今日队列');
        }
      }

      int urgentCount = 0;
      final dueWords = <DueWordInfo>[];

      for (final card in dueCards) {
        final dueTime = card.card.due;
        final isUrgent = dueTime.isBefore(yesterday);

        if (isUrgent) urgentCount++;

        if (dueWords.length < 5) {
          dueWords.add(
            DueWordInfo(
              wordId: card.wordId,
              word: card.word,
              dueTime: dueTime,
              isUrgent: isUrgent,
            ),
          );
        }
      }

      DateTime? nextDueTime;
      if (dueCards.isEmpty) {
        final allCards = await db.getAllWordCards(_currentDictName!, limit: 1);
        if (allCards.isNotEmpty) {
          nextDueTime = allCards.first.card.due;
        }
      }

      _reminderInfo = ReviewReminderInfo(
        dueCount: dueCards.length,
        urgentCount: urgentCount,
        nextDueTime: nextDueTime,
        dueWords: dueWords,
      );

      debugPrint(
        'ReviewReminderService: 更新提醒信息 - dueCount=${_reminderInfo.dueCount}, urgentCount=$urgentCount',
      );

      // 推送到 Stream（类似 drift watchQuery）
      if (!_streamController.isClosed) {
        _streamController.add(_reminderInfo);
      }

      // 通知 ChangeNotifier 监听者
      notifyListeners();
    } catch (e) {
      debugPrint('ReviewReminderService: 检查待复习单词失败: $e');
    }
  }

  void _startPeriodicCheck(Duration interval) {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(interval, (_) => _checkDueWordsAndNotify());
  }

  void stop() {
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  @override
  void dispose() {
    stop();
    _streamController.close();
    super.dispose();
  }
}
