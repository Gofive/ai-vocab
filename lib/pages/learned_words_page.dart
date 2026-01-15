import 'package:flutter/material.dart';
import 'package:ai_vocab/db_helper.dart';
import 'package:ai_vocab/models/word_card.dart';
import 'package:ai_vocab/theme/app_theme.dart';

/// 已学词表页面
///
/// 显示当前词典中所有已学习的单词，包括下次复习时间
class LearnedWordsPage extends StatefulWidget {
  final String dictName;

  const LearnedWordsPage({super.key, required this.dictName});

  @override
  State<LearnedWordsPage> createState() => _LearnedWordsPageState();
}

class _LearnedWordsPageState extends State<LearnedWordsPage> {
  List<WordCard> _learnedWords = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLearnedWords();
  }

  Future<void> _loadLearnedWords() async {
    final db = DBHelper();
    final words = await db.getAllWordCards(widget.dictName, limit: 10000);
    if (mounted) {
      setState(() {
        _learnedWords = words;
        _loading = false;
      });
    }
  }

  /// 格式化下次复习时间
  String _formatNextReview(DateTime due) {
    final now = DateTime.now().toUtc();
    final diff = due.difference(now);

    if (diff.isNegative) {
      // 已到期
      final overdue = now.difference(due);
      if (overdue.inDays > 0) {
        return '已逾期 ${overdue.inDays} 天';
      } else if (overdue.inHours > 0) {
        return '已逾期 ${overdue.inHours} 小时';
      } else {
        return '已逾期 ${overdue.inMinutes} 分钟';
      }
    }

    // 未到期
    if (diff.inDays > 365) {
      return '${(diff.inDays / 365).round()} 年后';
    } else if (diff.inDays > 30) {
      return '${(diff.inDays / 30).round()} 月后';
    } else if (diff.inDays > 0) {
      return '${diff.inDays} 天后';
    } else if (diff.inHours > 0) {
      return '${diff.inHours} 小时后';
    } else {
      return '${diff.inMinutes} 分钟后';
    }
  }

  /// 获取状态颜色
  Color _getStatusColor(DateTime due) {
    final now = DateTime.now().toUtc();
    final diff = due.difference(now);

    // 已到期（包括刚好到期的）
    if (diff.isNegative || diff.inSeconds == 0) {
      return Colors.red; // 已逾期
    } else if (diff.inHours < 24) {
      return Colors.orange; // 24小时内到期
    } else if (diff.inDays <= 1) {
      return Colors.amber; // 明天到期
    } else {
      return Colors.green; // 未来到期
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        backgroundColor: context.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '已学词表',
          style: TextStyle(
            color: context.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _learnedWords.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.school_outlined,
                    size: 64,
                    color: context.textSecondary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '暂无已学单词',
                    style: TextStyle(
                      fontSize: 16,
                      color: context.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '开始学习后，已学单词会显示在这里',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.textSecondary.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // 统计信息
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Text(
                        '共 ${_learnedWords.length} 个单词',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      // 到期统计
                      _buildDueStats(context),
                    ],
                  ),
                ),
                Divider(height: 1, color: context.dividerColor),
                // 单词列表
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _learnedWords.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      indent: 20,
                      endIndent: 20,
                      color: context.dividerColor,
                    ),
                    itemBuilder: (context, index) {
                      final word = _learnedWords[index];
                      return _buildWordItem(context, word, primaryColor);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildDueStats(BuildContext context) {
    final now = DateTime.now().toUtc();
    // 使用 isBefore 或 isAtSameMomentAs 来匹配数据库的 <= 比较
    final dueCount = _learnedWords
        .where(
          (w) => w.card.due.isBefore(now) || w.card.due.isAtSameMomentAs(now),
        )
        .length;

    if (dueCount > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '$dueCount 个待复习',
          style: const TextStyle(
            fontSize: 12,
            color: Colors.red,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildWordItem(
    BuildContext context,
    WordCard word,
    Color primaryColor,
  ) {
    final statusColor = _getStatusColor(word.card.due);
    final nextReview = _formatNextReview(word.card.due);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      title: Text(
        word.word,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: context.textPrimary,
        ),
      ),
      subtitle: Row(
        children: [
          // 复习次数
          Icon(Icons.repeat, size: 12, color: context.textSecondary),
          const SizedBox(width: 4),
          Text(
            '${word.reps}次',
            style: TextStyle(fontSize: 12, color: context.textSecondary),
          ),
          const SizedBox(width: 12),
          // 稳定性
          Icon(Icons.psychology, size: 12, color: context.textSecondary),
          const SizedBox(width: 4),
          Text(
            '${(word.card.stability ?? 0.0).toStringAsFixed(1)}',
            style: TextStyle(fontSize: 12, color: context.textSecondary),
          ),
        ],
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          nextReview,
          style: TextStyle(
            fontSize: 12,
            color: statusColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
