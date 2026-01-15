import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ai_vocab/db_helper.dart';
import 'package:ai_vocab/models/study_settings.dart';
import 'package:ai_vocab/models/word_model.dart';
import 'package:ai_vocab/models/word_card.dart';
import 'package:ai_vocab/models/study_session.dart';
import 'package:ai_vocab/models/review_log.dart';
import 'package:ai_vocab/theme/app_theme.dart';
import 'package:ai_vocab/providers/dict_provider.dart';
import 'package:ai_vocab/services/ad_service.dart';
import 'package:ai_vocab/services/fsrs_service.dart';
import 'package:ai_vocab/pages/learned_words_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:fsrs/fsrs.dart'
    hide State; // Hide State to avoid conflict with Flutter's State

/// 熟悉度等级 -> FSRS Rating 映射
/// _Requirements: 4.2, 4.3, 4.4_
enum FamiliarityLevel {
  mastered, // 记住了 -> Rating.easy
  familiar, // 有印象 -> Rating.good
  unfamiliar, // 没记住 -> Rating.again
}

extension FamiliarityLevelExt on FamiliarityLevel {
  /// 获取 SM-2 quality 值（用于兼容旧代码）
  ///
  /// 此属性已废弃，请使用 [fsrsRating] 替代。
  /// SM-2 算法已被 FSRS 替代。
  ///
  /// _Requirements: 3.1_
  @Deprecated(
    'Use fsrsRating instead. SM-2 algorithm has been replaced by FSRS.',
  )
  int get quality {
    switch (this) {
      case FamiliarityLevel.mastered:
        return 5;
      case FamiliarityLevel.familiar:
        return 3;
      case FamiliarityLevel.unfamiliar:
        return 1;
    }
  }

  /// 获取 FSRS Rating 值
  /// _Requirements: 4.2, 4.3, 4.4_
  Rating get fsrsRating {
    switch (this) {
      case FamiliarityLevel.mastered:
        return Rating.easy; // 记住了 -> Easy
      case FamiliarityLevel.familiar:
        return Rating.good; // 有印象 -> Good
      case FamiliarityLevel.unfamiliar:
        return Rating.again; // 没记住 -> Again
    }
  }
}

/// 学习页面入口 - 显示统计信息
class StudyPageWrapper extends ConsumerStatefulWidget {
  const StudyPageWrapper({super.key});

  @override
  ConsumerState<StudyPageWrapper> createState() => StudyPageWrapperState();
}

class StudyPageWrapperState extends ConsumerState<StudyPageWrapper>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refresh();
    }
  }

  void refresh() {
    ref.invalidate(currentDictProvider);
  }

  @override
  Widget build(BuildContext context) {
    final asyncDict = ref.watch(currentDictProvider);

    return asyncDict.when(
      data: (progress) {
        if (progress == null) {
          return Scaffold(
            backgroundColor: context.backgroundColor,
            body: Center(
              child: Text(
                '请先选择词典',
                style: TextStyle(color: context.textSecondary),
              ),
            ),
          );
        }
        return _StudyStatsPage(
          dictName: progress.dictName,
          progress: progress,
          onRefresh: refresh,
        );
      },
      loading: () => Scaffold(
        backgroundColor: context.backgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (err, stack) => Scaffold(
        backgroundColor: context.backgroundColor,
        body: Center(
          child: Text(
            '加载失败: $err',
            style: TextStyle(color: context.textSecondary),
          ),
        ),
      ),
    );
  }
}

/// 学习统计页面
class _StudyStatsPage extends StatefulWidget {
  final String dictName;
  final DictProgress progress;
  final VoidCallback onRefresh;

  const _StudyStatsPage({
    required this.dictName,
    required this.progress,
    required this.onRefresh,
  });

  @override
  State<_StudyStatsPage> createState() => _StudyStatsPageState();
}

class _StudyStatsPageState extends State<_StudyStatsPage> {
  TodaySessionStatus _sessionStatus = TodaySessionStatus.noSession;
  bool _loading = true;
  int _streakDays = 0;
  List<DateTime> _weekDates = [];
  Set<DateTime> _studiedDates = {};
  int _dueReviewCount = 0; // 待复习单词数量

  @override
  void initState() {
    super.initState();
    _initWeekDates();
    _loadSessionStatus();
    _loadStreakData();
    _loadDueReviewCount();
  }

  void _initWeekDates() {
    final now = DateTime.now();
    final weekday = now.weekday; // 1=周一, 7=周日
    final monday = now.subtract(Duration(days: weekday - 1));
    _weekDates = List.generate(
      7,
      (i) => DateTime(monday.year, monday.month, monday.day + i),
    );
  }

  Future<void> _loadStreakData() async {
    final db = DBHelper();
    final streak = await db.getStudyStreak();
    final studiedDates = await db.getStudiedDatesInRange(
      _weekDates.first,
      _weekDates.last,
    );
    if (mounted) {
      setState(() {
        _streakDays = streak;
        _studiedDates = studiedDates;
      });
    }
  }

  /// 加载待复习单词数量
  Future<void> _loadDueReviewCount() async {
    final db = DBHelper();
    final dueCards = await db.getDueCards(widget.dictName, limit: 10000);
    if (mounted) {
      setState(() {
        _dueReviewCount = dueCards.length;
      });
    }
  }

  @override
  void didUpdateWidget(covariant _StudyStatsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 词典变化时重新加载状态
    if (oldWidget.dictName != widget.dictName) {
      _loadSessionStatus();
    }
  }

  Future<void> _loadSessionStatus() async {
    setState(() => _loading = true);
    final status = await DBHelper().getTodaySessionStatus(widget.dictName);
    if (mounted) {
      setState(() {
        _sessionStatus = status;
        _loading = false;
      });
    }
    // 同时更新待复习数量
    _loadDueReviewCount();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: context.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // 可滚动内容区
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header - 词典信息
                    _buildHeader(context, primaryColor),
                    const SizedBox(height: 32),

                    // 连续打卡组件
                    _buildStreakCard(context, primaryColor),
                    const SizedBox(height: 16),

                    // 今日任务卡片
                    _buildTaskCards(context, primaryColor),
                    const SizedBox(height: 16),

                    // 待复习词汇统计组件
                    if (_dueReviewCount > 0)
                      _buildDueReviewCard(context, primaryColor),
                    if (_dueReviewCount > 0) const SizedBox(height: 16),

                    // 词库总进度
                    _buildTotalProgress(context, primaryColor),
                  ],
                ),
              ),
            ),

            // 底部固定按钮区域
            if (!_loading)
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                decoration: BoxDecoration(
                  color: context.backgroundColor,
                  border: Border(
                    top: BorderSide(color: context.dividerColor, width: 0.5),
                  ),
                ),
                child: _buildBottomButtons(context, primaryColor),
              ),
          ],
        ),
      ),
    );
  }

  int _estimateStudyTime() {
    final newWords =
        widget.progress.settings.dailyWords - widget.progress.todayNewCount;
    final reviewWords = widget.progress.todayReviewCount;
    // 假设每个新词1分钟，复习词0.5分钟
    return ((newWords * 1 + reviewWords * 0.5).ceil()).clamp(1, 60);
  }

  Widget _buildHeader(BuildContext context, Color primaryColor) {
    return Row(
      children: [
        // 词典图标
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.menu_book_rounded, color: primaryColor, size: 22),
        ),
        const SizedBox(width: 12),
        // 词典名称
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '正在学习',
                style: TextStyle(fontSize: 11, color: context.textSecondary),
              ),
              const SizedBox(height: 2),
              Text(
                widget.dictName,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        // 切换按钮
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.dividerColor),
          ),
          child: Icon(
            Icons.swap_horiz_rounded,
            color: context.textSecondary,
            size: 18,
          ),
        ),
      ],
    );
  }

  Widget _buildTaskCards(BuildContext context, Color primaryColor) {
    final newWordsGoal = widget.progress.settings.dailyWords;
    final learnedNew = widget.progress.todayNewCount;
    final reviewedCount = widget.progress.todayReviewedCount;
    final reviewTotal = widget.progress.todayReviewTotal;
    final estimatedTime = _estimateStudyTime();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '今日任务',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
              const Spacer(),
              Icon(Icons.schedule, size: 14, color: context.textSecondary),
              const SizedBox(width: 4),
              Text(
                '约 $estimatedTime 分钟',
                style: TextStyle(fontSize: 11, color: context.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildTaskItem(
                  context,
                  '新词学习',
                  '$learnedNew/$newWordsGoal',
                  primaryColor,
                ),
              ),
              Container(width: 1, height: 40, color: context.dividerColor),
              Expanded(
                child: _buildTaskItem(
                  context,
                  '复习巩固',
                  '$reviewedCount/$reviewTotal',
                  Colors.orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTaskItem(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: context.textSecondary),
        ),
      ],
    );
  }

  /// 词库总进度
  Widget _buildTotalProgress(BuildContext context, Color primaryColor) {
    final learned = widget.progress.learnedCount;
    final total = widget.progress.totalCount;
    final progress = total > 0 ? learned / total : 0.0;
    final percentage = (progress * 100).toInt();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '词库进度',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
              const Spacer(),
              // 查看已学词表按钮
              GestureDetector(
                onTap: () => _openLearnedWordsPage(context),
                child: Row(
                  children: [
                    Text(
                      '$learned / $total',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: primaryColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, size: 18, color: primaryColor),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: context.dividerColor,
              valueColor: AlwaysStoppedAnimation(primaryColor),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '已掌握 $percentage%',
            style: TextStyle(fontSize: 11, color: context.textSecondary),
          ),
        ],
      ),
    );
  }

  /// 待复习词汇统计组件
  Widget _buildDueReviewCard(BuildContext context, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.refresh, size: 16, color: Colors.orange),
              const SizedBox(width: 6),
              Text(
                '待复习词汇',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '$_dueReviewCount 个',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '这些单词已到复习时间，建议及时复习以巩固记忆',
            style: TextStyle(fontSize: 11, color: context.textSecondary),
          ),
        ],
      ),
    );
  }

  /// 底部按钮区域
  Widget _buildBottomButtons(BuildContext context, Color primaryColor) {
    // 如果今日已完成，显示完成状态
    if (_sessionStatus == TodaySessionStatus.completed) {
      // 如果有待复习词，显示继续复习按钮
      if (_dueReviewCount > 0) {
        return _buildReviewButton(context, primaryColor);
      }

      // 否则显示完成状态
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.teal.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: Colors.teal[400], size: 22),
            const SizedBox(width: 8),
            Text(
              '今日学习已完成',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.teal[400],
              ),
            ),
          ],
        ),
      );
    }

    // 如果有待复习词，显示两个按钮
    if (_dueReviewCount > 0) {
      return Column(
        children: [
          // 继续复习按钮
          _buildReviewButton(context, primaryColor),
          const SizedBox(height: 8),
          // 开始学习按钮
          _buildStartButton(
            context,
            primaryColor,
            _sessionStatus == TodaySessionStatus.inProgress ? '继续学习' : '开始学习',
            isSecondary: true,
          ),
        ],
      );
    }

    // 默认显示开始学习按钮
    return _buildStartButton(
      context,
      primaryColor,
      _sessionStatus == TodaySessionStatus.inProgress ? '继续学习' : '开始学习',
    );
  }

  /// 继续复习按钮
  Widget _buildReviewButton(BuildContext context, Color primaryColor) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: () async {
          // TODO: 实现复习页面跳转
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('复习功能即将上线'),
              duration: Duration(seconds: 2),
            ),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.refresh, size: 24),
            const SizedBox(width: 8),
            Text(
              '继续复习 ($_dueReviewCount)',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  /// 打开已学词表页面
  void _openLearnedWordsPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LearnedWordsPage(dictName: widget.dictName),
      ),
    );
  }

  Widget _buildStreakCard(BuildContext context, Color primaryColor) {
    final now = DateTime.now();
    final weekdays = ['一', '二', '三', '四', '五', '六', '日'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        children: [
          // 标题行
          Row(
            children: [
              const Icon(
                Icons.local_fire_department,
                color: Colors.orange,
                size: 20,
              ),
              const SizedBox(width: 6),
              Text(
                '连续打卡 $_streakDays 天',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '${now.month}月',
                style: TextStyle(fontSize: 11, color: context.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 星期和日期
          Row(
            children: _weekDates.asMap().entries.map((entry) {
              final index = entry.key;
              final date = entry.value;
              final isToday = _isSameDay(date, now);
              final isStudied = _studiedDates.any((d) => _isSameDay(d, date));
              final isFuture = date.isAfter(now);

              return Expanded(
                child: Column(
                  children: [
                    // 星期
                    Text(
                      weekdays[index],
                      style: TextStyle(
                        fontSize: 11,
                        color: context.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 日期圆点
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isStudied ? primaryColor : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Text(
                          '${date.day}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isStudied
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isStudied
                                ? Colors.white
                                : (isFuture
                                      ? context.textSecondary.withValues(
                                          alpha: 0.4,
                                        )
                                      : context.textPrimary),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // 当前日期小点指示器
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: isToday ? primaryColor : Colors.transparent,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildStartButton(
    BuildContext context,
    Color primaryColor,
    String label, {
    bool isSecondary = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StudySessionPage(
                dictName: widget.dictName,
                settings: widget.progress.settings,
                onComplete: () {
                  widget.onRefresh();
                  _loadSessionStatus();
                  _loadStreakData();
                  _loadDueReviewCount();
                },
              ),
            ),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: isSecondary ? context.surfaceColor : primaryColor,
          foregroundColor: isSecondary ? context.textPrimary : Colors.white,
          elevation: 0,
          side: isSecondary ? BorderSide(color: context.dividerColor) : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.menu_book,
              size: 24,
              color: isSecondary ? context.textPrimary : Colors.white,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: isSecondary ? context.textPrimary : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 学习会话页面 - 单词学习
class StudySessionPage extends StatefulWidget {
  final String dictName;
  final StudySettings settings;
  final VoidCallback? onComplete;

  const StudySessionPage({
    super.key,
    required this.dictName,
    required this.settings,
    this.onComplete,
  });

  @override
  State<StudySessionPage> createState() => _StudySessionPageState();
}

class _StudySessionPageState extends State<StudySessionPage> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FSRSService _fsrsService = FSRSService(); // FSRS 服务实例
  StudySession? _session;
  int _currentIndex = 0;
  bool _loading = true;
  int _rebuildKey = 0; // 用于强制重建页面

  // 撤销相关
  WordCard? _lastAction; // 上一次操作的单词卡片（用于撤销）
  int? _lastActionIndex; // 上一次操作的索引
  bool _canUndo = false; // 是否可以撤销
  bool _addedNewWordOnLastAction = false; // 上次操作是否补充了新词
  bool _showFamiliarityButtons = false; // 是否显示熟悉度按钮（倒计时结束后显示）

  @override
  void initState() {
    super.initState();
    _loadOrResumeSession();
  }

  Future<void> _loadOrResumeSession() async {
    final db = DBHelper();
    final session = await db.getOrCreateTodaySession(
      widget.dictName,
      widget.settings,
    );

    if (mounted) {
      // 确保 currentIndex 不超出队列范围
      int safeIndex = 0;
      if (session != null && session.queue.isNotEmpty) {
        safeIndex = session.currentIndex.clamp(0, session.queue.length - 1);
      }

      setState(() {
        _session = session;
        _currentIndex = safeIndex;
        _loading = false;
      });
    }
  }

  Future<void> _saveProgress() async {
    if (_session == null) return;
    await DBHelper().updateSessionProgress(_session!.id, _currentIndex);
  }

  void _playAudio(String? path, {String? word}) async {
    if (path == null) return;
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setAudioSource(
        AudioSource.uri(Uri.parse("https://oss.timetbb.com/word.ai/$path")),
      );
      await _audioPlayer.seek(Duration.zero);
      await _audioPlayer.play();
    } catch (_) {}
  }

  /// 处理倒计时阶段点击"已充分掌握"
  /// 使用 FSRS 算法更新卡片状态
  Future<void> _handleMasteredInCountdown() async {
    if (_session == null) return;

    final queue = _session!.queue;
    final currentWordCard = queue[_currentIndex];
    final isNewWord = !currentWordCard.isReview; // 新词 = 非复习卡片

    // 保存撤销信息（保存 WordCard 的副本）
    _lastActionIndex = _currentIndex;
    _lastAction = currentWordCard.copyWith();

    final db = DBHelper();
    final now = DateTime.now().toUtc();

    // 使用 FSRS 算法更新卡片 - 使用 Rating.easy 表示"已充分掌握"
    final result = _fsrsService.reviewCard(
      currentWordCard.card,
      Rating.easy,
      now: now,
    );

    // 更新 WordCard 的 FSRS Card 对象
    currentWordCard.card = result.card;
    currentWordCard.reps += 1;

    // 保存更新后的 WordCard 到数据库
    await db.saveWordCard(currentWordCard);

    // 记录 ReviewLog
    final reviewLog = ReviewLogEntry.fromFSRSLog(
      wordId: currentWordCard.wordId,
      dictName: widget.dictName,
      fsrsLog: result.reviewLog,
      reviewDatetime: now,
    );
    await db.logReview(reviewLog);

    await db.markSessionWordDone(_session!.id, _currentIndex);

    // 如果是新词被标记为掌握，补充一个新词到队列
    bool addedNewWord = false;
    if (isNewWord) {
      final newWord = await db.getNextNewWordCard(
        widget.dictName,
        widget.settings,
        _session!.queue,
      );
      if (newWord != null) {
        _session!.queue.add(newWord);
        await db.addWordToSessionQueue(_session!.id, newWord.wordId);
        addedNewWord = true;
      }
    }

    setState(() {
      _canUndo = true;
      _addedNewWordOnLastAction = addedNewWord;
    });

    // 显示撤销提示
    _showUndoSnackBar(currentWordCard.word, addedNewWord);

    // 自动跳转到下一个
    _goToNextWord();
  }

  /// 显示撤销 SnackBar
  void _showUndoSnackBar(String word, [bool addedNewWord = false]) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          addedNewWord ? '已标记 "$word" 为充分掌握，已补充新词' : '已标记 "$word" 为充分掌握',
        ),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: '撤销',
          textColor: Colors.amber,
          onPressed: _undoLastAction,
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      ),
    );
  }

  /// 撤销上一次操作
  Future<void> _undoLastAction() async {
    if (!_canUndo || _lastAction == null || _lastActionIndex == null) return;

    final db = DBHelper();
    final targetIndex = _lastActionIndex!;

    // 1. 如果补充了新词，先移除它
    if (_addedNewWordOnLastAction && _session!.queue.isNotEmpty) {
      await db.removeLastWordFromSessionQueue(_session!.id);
      _session!.queue.removeLast();
    }

    // 2. 删除该单词的进度记录（恢复为未学习状态）
    await db.deleteWordProgress(_lastAction!.wordId, widget.dictName);

    // 3. 恢复会话队列中的单词状态为未完成
    await db.unmarkSessionWordDone(_session!.id, targetIndex);

    // 4. 更新会话进度
    await db.updateSessionProgress(_session!.id, targetIndex);

    setState(() {
      _currentIndex = targetIndex;
      _rebuildKey++; // 强制重建页面，重新开始倒计时
      _showFamiliarityButtons = false;
      _canUndo = false;
      _lastAction = null;
      _lastActionIndex = null;
      _addedNewWordOnLastAction = false;
    });

    _saveProgress();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已撤销'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, 80),
      ),
    );
  }

  /// 跳转到下一个单词
  void _goToNextWord() {
    if (_session == null) return;

    if (_currentIndex < _session!.queue.length - 1) {
      setState(() {
        _currentIndex++;
        _showFamiliarityButtons = false;
      });
      _saveProgress();
    } else {
      _completeSession();
    }
  }

  /// 完成学习会话
  Future<void> _completeSession() async {
    await DBHelper().completeSession(_session!.id);
    if (mounted) {
      _showCompletionDialog();
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: context.backgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_session == null || _session!.queue.isEmpty || _session!.isCompleted) {
      return Scaffold(
        backgroundColor: context.backgroundColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.celebration, size: 80, color: Colors.amber[400]),
              const SizedBox(height: 24),
              Text(
                _session?.queue.isEmpty ?? true ? '暂无学习任务' : '今日学习完成！',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '明天继续加油',
                style: TextStyle(fontSize: 16, color: context.textSecondary),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      );
    }

    final queue = _session!.queue;
    final currentWord = queue[_currentIndex];

    return Scaffold(
      backgroundColor: context.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: _WordCardPage(
                  key: ValueKey(
                    '${currentWord.wordId}_${_currentIndex}_$_rebuildKey',
                  ),
                  isActive: true,
                  wordText: currentWord.word,
                  isReview: currentWord.isReview,
                  onPlayAudio: _playAudio,
                  primaryColor: Theme.of(context).colorScheme.primary,
                  onMasteredInCountdown: (_) => _handleMasteredInCountdown(),
                  onShowDetails: () {
                    if (mounted) {
                      setState(() => _showFamiliarityButtons = true);
                    }
                  },
                ),
              ),
            ),
            if (_showFamiliarityButtons) _buildFamiliarityButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final session = _session;
    final queue = session?.queue ?? [];

    // 计算已完成和剩余的统计
    // 已完成的新词：当前索引之前的非复习词数量
    int doneNewWords = 0;
    int remainingReviewWords = 0;

    for (int i = 0; i < queue.length; i++) {
      if (i < _currentIndex) {
        // 已完成的词
        if (!queue[i].isReview) {
          doneNewWords++;
        }
      } else {
        // 未完成的词（从当前索引开始）
        if (queue[i].isReview) {
          remainingReviewWords++;
        }
      }
    }

    final totalCount = queue.length;
    final dailyGoal = widget.settings.dailyWords;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              _saveProgress();
              widget.onComplete?.call();
              Navigator.pop(context);
            },
            child: Icon(Icons.close, size: 24, color: context.textPrimary),
          ),
          Expanded(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '新词 $doneNewWords/$dailyGoal',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '待复习 $remainingReviewWords',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // 进度条或文字
                Text(
                  '当前第 ${_currentIndex + 1} / $totalCount',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildFamiliarityButtons(BuildContext context) {
    final currentWord = _session?.queue[_currentIndex];
    final isReview = currentWord?.isReview ?? false;

    // 使用 FSRS 预览间隔
    // _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_
    final now = DateTime.now().toUtc();
    final card = currentWord?.card;

    // 获取各评分选项的预览间隔
    Map<Rating, Duration> previewIntervals = {};
    if (card != null) {
      previewIntervals = _fsrsService.previewIntervals(card, now: now);
    }

    // 格式化预览间隔为可读字符串
    String getPreviewText(Rating rating) {
      if (previewIntervals.isEmpty) return '...';
      final duration = previewIntervals[rating];
      if (duration == null) return '...';
      // 对于 Again 评分，显示"稍后"
      if (rating == Rating.again && duration.inMinutes < 60) {
        return '稍后';
      }
      return _fsrsService.formatInterval(duration);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      child: Row(
        children: [
          _buildFamiliarityBtn(
            context,
            isReview ? '记得' : '太简单',
            Icons.sentiment_satisfied_alt,
            Colors.teal,
            getPreviewText(Rating.easy),
            onTap: () => _handleFamiliarity(FamiliarityLevel.mastered),
          ),
          const SizedBox(width: 12),
          _buildFamiliarityBtn(
            context,
            isReview ? '模糊' : '有困难',
            Icons.sentiment_neutral,
            Colors.orange,
            getPreviewText(Rating.good),
            onTap: () => _handleFamiliarity(FamiliarityLevel.familiar),
          ),
          const SizedBox(width: 12),
          _buildFamiliarityBtn(
            context,
            isReview ? '忘了' : '不认识',
            Icons.sentiment_dissatisfied,
            context.textSecondary,
            getPreviewText(Rating.again),
            onTap: () => _handleFamiliarity(FamiliarityLevel.unfamiliar),
          ),
        ],
      ),
    );
  }

  /// 处理熟悉度评分
  /// 使用 FSRS 算法更新卡片状态
  /// _Requirements: 4.2, 4.3, 4.4, 4.6_
  Future<void> _handleFamiliarity(FamiliarityLevel level) async {
    if (_session == null) return;

    final queue = _session!.queue;
    final currentWordCard = queue[_currentIndex];
    final isNewWord = !currentWordCard.isReview; // 新词 = 非复习卡片

    // 保存原始状态用于撤销（保存 WordCard 的副本）
    _lastAction = currentWordCard.copyWith();
    _lastActionIndex = _currentIndex;

    final db = DBHelper();
    final now = DateTime.now().toUtc();

    // 使用 FSRS 算法更新卡片
    // _Requirements: 4.2, 4.3, 4.4_
    final result = _fsrsService.reviewCard(
      currentWordCard.card,
      level.fsrsRating,
      now: now,
    );

    // 更新 WordCard 的 FSRS Card 对象
    currentWordCard.card = result.card;
    currentWordCard.reps += 1;
    if (level == FamiliarityLevel.unfamiliar) {
      currentWordCard.lapses += 1;
    }

    // 保存更新后的 WordCard 到数据库
    await db.saveWordCard(currentWordCard);

    // 记录 ReviewLog
    // _Requirements: 9.1, 9.2_
    final reviewLog = ReviewLogEntry.fromFSRSLog(
      wordId: currentWordCard.wordId,
      dictName: widget.dictName,
      fsrsLog: result.reviewLog,
      reviewDatetime: now,
    );
    await db.logReview(reviewLog);

    await db.markSessionWordDone(_session!.id, _currentIndex);

    // 关键逻辑：点击"不认识"时，立即将单词加入队列末尾作为复习
    // _Requirements: 4.6_
    bool addedToQueue = false;
    if (level == FamiliarityLevel.unfamiliar) {
      // 创建一个复习卡片加入队列
      final repeatCard = currentWordCard.copyWith();
      setState(() {
        _session!.queue.add(repeatCard);
      });
      // 添加到数据库队列
      await db.addWordToSessionQueue(_session!.id, repeatCard.wordId);
      addedToQueue = true;

      print(
        'DEBUG: 单词 "${currentWordCard.word}" 点击不认识，已加入队列末尾 (isNewWord: $isNewWord)',
      );
    }

    setState(() {
      _canUndo = true;
      _addedNewWordOnLastAction = addedToQueue;
    });

    // 记录学习次数（用于广告展示）
    AdService().recordStudy();

    _goToNextWord();
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.celebration, color: Colors.amber[400], size: 28),
            const SizedBox(width: 8),
            Text('学习完成', style: TextStyle(color: context.textPrimary)),
          ],
        ),
        content: Text(
          '今日学习任务已完成！',
          style: TextStyle(color: context.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onComplete?.call();
              Navigator.pop(context);
            },
            child: Text(
              '返回',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFamiliarityBtn(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    String nextReview, {
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.dividerColor),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '下次',
                    style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    nextReview,
                    style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单词卡片页面
class _WordCardPage extends StatefulWidget {
  final String wordText;
  final bool isReview;
  final bool isActive;
  final Function(String?, {String? word}) onPlayAudio;
  final Color primaryColor;
  final Function(bool isMastered)? onMasteredInCountdown; // 倒计时阶段点击"已掌握"
  final VoidCallback? onShowDetails; // 倒计时结束显示详情

  const _WordCardPage({
    super.key,
    required this.wordText,
    this.isReview = false,
    required this.isActive,
    required this.onPlayAudio,
    required this.primaryColor,
    this.onMasteredInCountdown,
    this.onShowDetails,
  });

  @override
  State<_WordCardPage> createState() => _WordCardPageState();
}

class _WordCardPageState extends State<_WordCardPage>
    with SingleTickerProviderStateMixin {
  WordDetail? _word;
  int _countdown = 5;
  bool _showDetails = false;
  Timer? _timer;
  late AnimationController _animationController;
  late Animation<double> _progressAnimation;

  static const int _totalSeconds = 5;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: _totalSeconds),
    );
    _progressAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.linear),
    );
    _loadWord();
  }

  @override
  void didUpdateWidget(_WordCardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      // 页面从不活跃变为活跃
      print(
        'DEBUG _WordCardPage: 页面激活 - word=${widget.wordText}, _word=${_word?.word}, _showDetails=$_showDetails',
      );
      if (_word != null) {
        widget.onPlayAudio(_word?.ttsPath, word: _word?.word);
        // 如果还没有显示详情，且倒计时未启动，则启动倒计时
        if (!_showDetails) {
          print('DEBUG _WordCardPage: 启动倒计时 - word=${widget.wordText}');
          _startCountdown();
        }
      } else {
        print(
          'DEBUG _WordCardPage: 单词尚未加载，等待 _loadWord 完成 - word=${widget.wordText}',
        );
      }
    } else if (!widget.isActive && oldWidget.isActive) {
      // 页面从活跃变为不活跃
      print('DEBUG _WordCardPage: 页面失活 - word=${widget.wordText}');
      _timer?.cancel();
      _animationController.stop();
    }
  }

  Future<void> _loadWord() async {
    print(
      'DEBUG _WordCardPage: 开始加载单词 - word=${widget.wordText}, isActive=${widget.isActive}',
    );
    final word = await DBHelper().getWordDetail(widget.wordText);
    if (mounted) {
      setState(() => _word = word);
      print(
        'DEBUG _WordCardPage: 单词加载完成 - word=${widget.wordText}, isActive=${widget.isActive}, _showDetails=$_showDetails',
      );
      // 单词加载完成后，如果页面是活跃的且还没显示详情，启动倒计时
      if (widget.isActive && !_showDetails) {
        print('DEBUG _WordCardPage: 单词加载后启动倒计时 - word=${widget.wordText}');
        widget.onPlayAudio(word?.ttsPath, word: word?.word);
        _startCountdown();
      }
    }
  }

  void _startCountdown() {
    print('DEBUG _WordCardPage: _startCountdown 被调用 - word=${widget.wordText}');
    // 确保先取消之前可能存在的计时器
    _timer?.cancel();

    // 重置状态并更新 UI
    setState(() {
      _countdown = _totalSeconds;
      _showDetails = false;
    });

    // 重置并启动动画控制器
    _animationController.reset();
    _animationController.forward();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 1) {
        setState(() => _countdown--);
      } else {
        timer.cancel();
        print('DEBUG _WordCardPage: 倒计时结束，显示详情 - word=${widget.wordText}');
        setState(() => _showDetails = true);
        widget.onShowDetails?.call();
      }
    });
  }

  void _handleMasteredClick() {
    _timer?.cancel();
    widget.onMasteredInCountdown?.call(true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_word == null) return const Center(child: CircularProgressIndicator());
    return _showDetails ? _buildDetailView() : _buildCountdownView();
  }

  Widget _buildCountdownView() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(24),
                boxShadow: context.isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: widget.isReview
                          ? Colors.orange.withValues(alpha: 0.1)
                          : widget.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      widget.isReview ? '复习巩固' : '词汇背诵',
                      style: TextStyle(
                        color: widget.isReview
                            ? Colors.orange
                            : widget.primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    _word!.word,
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _word!.phonetic,
                    style: TextStyle(
                      fontSize: 16,
                      color: context.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 100,
                          height: 100,
                          child: AnimatedBuilder(
                            animation: _progressAnimation,
                            builder: (context, child) {
                              return CircularProgressIndicator(
                                value: _progressAnimation.value,
                                strokeWidth: 4,
                                backgroundColor: context.dividerColor,
                                valueColor: AlwaysStoppedAnimation(
                                  widget.primaryColor,
                                ),
                              );
                            },
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _countdown.toString().padLeft(2, '0'),
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: widget.primaryColor,
                              ),
                            ),
                            Text(
                              '秒',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    '释义即将显示...',
                    style: TextStyle(
                      fontSize: 14,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 已充分掌握按钮 - 放在卡片外部底部
        OutlinedButton.icon(
          onPressed: _handleMasteredClick,
          icon: const Icon(Icons.check_circle_outline, size: 24),
          label: const Text(
            '已充分掌握',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: context.textPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
            backgroundColor: Colors.indigo,
            side: BorderSide(width: 1, color: Colors.indigo),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
        ),
        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildDetailView() {
    final word = _word!;
    final accentColor = widget.isReview ? Colors.orange : widget.primaryColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Container(
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: widget.isReview
              ? [
                  BoxShadow(
                    color: Colors.orange.withValues(alpha: 0.25),
                    blurRadius: 16,
                    spreadRadius: 0,
                    offset: const Offset(0, 4),
                  ),
                ]
              : (context.isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ]),
        ),
        child: Column(
          children: [
            // 固定的头部：单词和音标
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 复习/新词标签
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.isReview
                                  ? Icons.replay_rounded
                                  : Icons.auto_stories,
                              size: 14,
                              color: accentColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              widget.isReview ? '复习' : '新词',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: accentColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () =>
                            widget.onPlayAudio(word.ttsPath, word: word.word),
                        child: Icon(
                          Icons.volume_up_rounded,
                          size: 26,
                          color: accentColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    word.word,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    word.phonetic,
                    style: TextStyle(
                      fontSize: 15,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: context.dividerColor),
            // 可滚动的内容区域
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('中文释义', widget.primaryColor),
                    const SizedBox(height: 8),
                    Text(
                      word.definitions.join('；'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildMnemonicCard(word.mnemonic),
                    const SizedBox(height: 24),
                    _buildSectionTitle('例句', widget.primaryColor),
                    const SizedBox(height: 12),
                    ...word.usageStacks.asMap().entries.map(
                      (entry) => _buildSentenceItem(entry.value, entry.key + 1),
                    ),
                    if (word.allCollocations.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildSectionTitle('常用短语', widget.primaryColor),
                      const SizedBox(height: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: word.allCollocations
                            .map((p) => _buildPhraseItem(p))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, Color color) {
    return Text(
      title,
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
    );
  }

  Widget _buildMnemonicCard(String mnemonic) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(
              0xFF6366F1,
            ).withValues(alpha: context.isDark ? 0.15 : 0.08),
            const Color(
              0xFF8B5CF6,
            ).withValues(alpha: context.isDark ? 0.15 : 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'AI 助记',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6366F1),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'AI',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6366F1),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            mnemonic,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: context.isDark
                  ? AppTheme.darkTextSecondary
                  : const Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSentenceItem(UsageStack stack, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(top: 2, right: 10),
            decoration: BoxDecoration(
              color: widget.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                '$index',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: widget.primaryColor,
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        stack.enSentence,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: context.textPrimary,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => widget.onPlayAudio(
                        stack.sentenceTts,
                        word: stack.enSentence,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(
                          Icons.volume_up_rounded,
                          size: 24,
                          color: context.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  stack.zhSentence,
                  style: TextStyle(
                    fontSize: 14,
                    color: context.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhraseItem(String phrase) {
    String displayText = phrase;
    final match = RegExp(r'^(.+?)\s*\((.+)\)$').firstMatch(phrase);
    if (match != null) {
      displayText = '${match.group(1)}  ${match.group(2)}';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        displayText,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: context.textPrimary,
          height: 1.5,
        ),
      ),
    );
  }
}
