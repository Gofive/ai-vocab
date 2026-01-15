import 'package:fsrs/fsrs.dart';

/// FSRS 服务 - 封装间隔重复调度逻辑
///
/// 使用 FSRS (Free Spaced Repetition Scheduler) 算法来计算
/// 单词卡片的下次复习时间。
class FSRSService {
  late final Scheduler _scheduler;

  FSRSService() {
    _scheduler = Scheduler(
      desiredRetention: 0.9, // 90% 目标保留率
      maximumInterval: 36500, // 100 年最大间隔
      learningSteps: [Duration(minutes: 1), Duration(minutes: 10)],
      relearningSteps: [Duration(minutes: 10)],
    );
  }

  /// 获取调度器实例（用于测试）
  Scheduler get scheduler => _scheduler;

  /// 复习卡片并返回调度结果
  ///
  /// [card] - FSRS 卡片对象
  /// [rating] - 用户评分 (Again, Hard, Good, Easy)
  /// [now] - 当前时间（用于计算）
  ///
  /// 返回包含更新后卡片和复习日志的记录
  ({Card card, ReviewLog reviewLog}) reviewCard(
    Card card,
    Rating rating, {
    DateTime? now,
  }) {
    final result = _scheduler.reviewCard(card, rating, reviewDateTime: now);
    return result;
  }

  /// 预览所有评分选项的下次复习间隔
  ///
  /// 此方法不会修改原始卡片，仅用于预览显示
  ///
  /// [card] - FSRS 卡片对象
  /// [now] - 当前时间
  ///
  /// 返回各评分对应的复习间隔
  Map<Rating, Duration> previewIntervals(Card card, {DateTime? now}) {
    final currentTime = now ?? DateTime.now().toUtc();

    // 为每个评分计算预览间隔
    final Map<Rating, Duration> intervals = {};

    for (final rating in [
      Rating.again,
      Rating.hard,
      Rating.good,
      Rating.easy,
    ]) {
      // 创建卡片副本进行预览计算
      final cardCopy = Card.fromMap(card.toMap());
      final result = _scheduler.reviewCard(
        cardCopy,
        rating,
        reviewDateTime: currentTime,
      );
      intervals[rating] = result.card.due.difference(currentTime);
    }

    return intervals;
  }

  /// 格式化间隔为可读字符串
  ///
  /// [duration] - 时间间隔
  ///
  /// 返回格式化的中文字符串，如 "5 分钟", "2 天", "3 月"
  String formatInterval(Duration duration) {
    final minutes = duration.inMinutes;

    if (minutes < 60) {
      return '$minutes 分钟';
    }

    if (minutes < 1440) {
      // 小于 1 天，显示小时
      return '${duration.inHours} 小时';
    }

    final days = duration.inDays;

    if (days < 30) {
      return '$days 天';
    }

    if (days < 365) {
      return '${(days / 30).round()} 月';
    }

    return '${(days / 365).round()} 年';
  }

  /// 获取卡片的当前记忆保留率
  ///
  /// [card] - FSRS 卡片对象
  ///
  /// 返回 0-1 之间的概率值
  double getRetrievability(Card card) {
    return _scheduler.getCardRetrievability(card);
  }
}
