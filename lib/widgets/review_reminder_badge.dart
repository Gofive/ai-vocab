import 'package:flutter/material.dart';
import 'package:ai_vocab/services/review_reminder_service.dart';
import 'package:ai_vocab/theme/app_theme.dart';

/// 复习提醒徽章
///
/// 显示待复习数量的小红点/数字徽章
class ReviewReminderBadge extends StatelessWidget {
  final Widget child;
  final bool showCount;
  final double? top;
  final double? right;

  const ReviewReminderBadge({
    super.key,
    required this.child,
    this.showCount = true,
    this.top,
    this.right,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ReviewReminderService(),
      builder: (context, _) {
        final service = ReviewReminderService();
        final count = service.dueCount;

        if (count == 0) return child;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            Positioned(
              top: top ?? -4,
              right: right ?? -4,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: showCount && count > 9 ? 4 : 0,
                  vertical: 0,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: BoxDecoration(
                  color: service.reminderInfo.hasUrgentWords
                      ? Colors.red
                      : Colors.orange,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    showCount ? (count > 99 ? '99+' : '$count') : '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 复习提醒横幅
///
/// 显示在页面顶部的提醒横幅
class ReviewReminderBanner extends StatelessWidget {
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;

  const ReviewReminderBanner({super.key, this.onTap, this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ReviewReminderService(),
      builder: (context, _) {
        final service = ReviewReminderService();
        final info = service.reminderInfo;

        if (!info.hasDueWords) return const SizedBox.shrink();

        final isUrgent = info.hasUrgentWords;
        final bgColor = isUrgent
            ? Colors.red.withValues(alpha: 0.1)
            : Colors.orange.withValues(alpha: 0.1);
        final borderColor = isUrgent ? Colors.red : Colors.orange;
        final iconColor = isUrgent ? Colors.red : Colors.orange;

        return GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(
                  isUrgent ? Icons.warning_amber_rounded : Icons.schedule,
                  color: iconColor,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isUrgent ? '有单词急需复习！' : '有单词需要复习',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _buildSubtitle(info),
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: iconColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '去复习',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _buildSubtitle(ReviewReminderInfo info) {
    if (info.hasUrgentWords) {
      return '${info.urgentCount} 个单词已超时，共 ${info.dueCount} 个待复习';
    }
    return '${info.dueCount} 个单词已到复习时间';
  }
}

/// 复习提醒卡片（更详细的展示）
class ReviewReminderCard extends StatelessWidget {
  const ReviewReminderCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ReviewReminderService(),
      builder: (context, _) {
        final service = ReviewReminderService();
        final info = service.reminderInfo;

        if (!info.hasDueWords) return const SizedBox.shrink();

        final isUrgent = info.hasUrgentWords;
        final primaryColor = Theme.of(context).colorScheme.primary;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isUrgent
                  ? Colors.red.withValues(alpha: 0.3)
                  : context.dividerColor,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Row(
                children: [
                  Icon(
                    isUrgent
                        ? Icons.warning_amber_rounded
                        : Icons.notifications_active,
                    color: isUrgent ? Colors.red : Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isUrgent ? '紧急复习提醒' : '复习提醒',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: (isUrgent ? Colors.red : Colors.orange).withValues(
                        alpha: 0.1,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${info.dueCount} 个',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isUrgent ? Colors.red : Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 单词预览
              if (info.dueWords.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: info.dueWords.take(4).map((word) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: word.isUrgent
                            ? Colors.red.withValues(alpha: 0.1)
                            : primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        word.word,
                        style: TextStyle(
                          fontSize: 12,
                          color: word.isUrgent ? Colors.red : primaryColor,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (info.dueCount > 4)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '还有 ${info.dueCount - 4} 个...',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.textSecondary,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}
