import 'package:flutter/material.dart';
import 'package:ai_vocab/db_helper.dart';
import 'package:ai_vocab/models/study_settings.dart';
import 'package:ai_vocab/theme/app_theme.dart';
import 'package:ai_vocab/widgets/native_ad_card.dart';
import 'package:ai_vocab/services/ad_service.dart';

class DictPage extends StatefulWidget {
  const DictPage({super.key});

  @override
  State<DictPage> createState() => _DictPageState();
}

class _DictPageState extends State<DictPage> {
  List<Map<String, dynamic>> _dictList = [];
  Map<String, DictProgress> _progressMap = {};
  bool _loading = true;
  String? _selectedDict;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = DBHelper();
    final dicts = await db.getDictList();

    // 获取当前选择的词典
    String? currentDict = await db.getCurrentDict();

    Map<String, DictProgress> progressMap = {};
    for (var dict in dicts) {
      final name = dict['name'] as String;
      progressMap[name] = await db.getDictProgress(name);
    }

    if (mounted) {
      setState(() {
        _dictList = dicts;
        _progressMap = progressMap;
        _loading = false;
        // 如果有保存的选择，使用它；否则使用第一个词典
        if (currentDict != null && dicts.any((d) => d['name'] == currentDict)) {
          _selectedDict = currentDict;
        } else if (dicts.isNotEmpty) {
          _selectedDict = dicts.first['name'] as String;
        }
      });
    }
  }

  /// 选择词典并保存
  Future<void> _selectDict(String dictName) async {
    setState(() => _selectedDict = dictName);
    await DBHelper().setCurrentDict(dictName);
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: context.backgroundColor,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '词典',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: context.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '选择词典开始学习',
                            style: TextStyle(
                              fontSize: 15,
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            childAspectRatio: 0.75,
                          ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          // 在第3个位置插入广告（index=2）
                          final adPosition = 2;
                          final showAd =
                              AdService().isSupported &&
                              _dictList.length > adPosition;

                          if (showAd && index == adPosition) {
                            return const NativeAdCard();
                          }

                          // 调整实际词典的索引
                          final dictIndex = showAd && index > adPosition
                              ? index - 1
                              : index;
                          if (dictIndex >= _dictList.length) {
                            return const SizedBox.shrink();
                          }

                          final dict = _dictList[dictIndex];
                          final name = dict['name'] as String;
                          final count = dict['word_count'] as int;
                          final progress = _progressMap[name];
                          final isSelected = _selectedDict == name;
                          return _buildBookCard(
                            name,
                            count,
                            progress,
                            isSelected,
                            primaryColor,
                          );
                        },
                        childCount:
                            _dictList.length +
                            (AdService().isSupported && _dictList.length > 2
                                ? 1
                                : 0),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
      ),
    );
  }

  Widget _buildBookCard(
    String name,
    int wordCount,
    DictProgress? progress,
    bool isSelected,
    Color primaryColor,
  ) {
    final learned = progress?.learnedCount ?? 0;
    final progressValue = progress?.progress ?? 0;
    final percentage = (progressValue * 100).toInt();

    // 根据词典名称生成不同的颜色
    final bookColors = [
      [const Color(0xFF6366F1), const Color(0xFF818CF8)], // 紫色
      [const Color(0xFF10B981), const Color(0xFF34D399)], // 绿色
      [const Color(0xFFF59E0B), const Color(0xFFFBBF24)], // 橙色
      [const Color(0xFFEF4444), const Color(0xFFF87171)], // 红色
      [const Color(0xFF3B82F6), const Color(0xFF60A5FA)], // 蓝色
      [const Color(0xFFEC4899), const Color(0xFFF472B6)], // 粉色
    ];
    final colorIndex = name.hashCode.abs() % bookColors.length;
    final baseColor = bookColors[colorIndex];

    // 根据学习进度加深背景色
    final darkenFactor = progressValue * 0.3;
    final bookColor = [
      Color.lerp(baseColor[0], Colors.black, darkenFactor)!,
      Color.lerp(baseColor[1], Colors.black, darkenFactor)!,
    ];

    return GestureDetector(
      onTap: () {
        _showSettingsSheet(name, progress);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: bookColor[0].withValues(alpha: isSelected ? 0.3 : 0.15),
              blurRadius: isSelected ? 16 : 8,
              offset: const Offset(4, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              // 纯色渐变背景
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: bookColor,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
              // 书脊效果
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 12,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.2),
                        Colors.transparent,
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                ),
              ),
              // 书页效果
              Positioned(
                right: 2,
                top: 8,
                bottom: 8,
                width: 3,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // 内容区域
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 热门标记 + 待复习提示
                    Row(
                      children: [
                        if (wordCount > 3000)
                          const Icon(
                            Icons.whatshot_rounded,
                            size: 16,
                            color: Colors.amber,
                          ),
                        const Spacer(),
                        if ((progress?.todayReviewCount ?? 0) > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${progress!.todayReviewCount}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const Spacer(),
                    // 词典名称
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // 词汇数量 + 已学数量
                    Text(
                      '已学 $learned / $wordCount',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // 进度条
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progressValue,
                        minHeight: 4,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // 进度百分比
                    Text(
                      '$percentage%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              // 选中标记
              if (isSelected)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.check, size: 16, color: bookColor[0]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettingsSheet(String dictName, DictProgress? progress) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StudySettingsSheet(
        dictName: dictName,
        currentSettings: progress?.settings ?? const StudySettings(),
        onConfirm: (settings) async {
          await DBHelper().saveStudySettings(dictName, settings);
          await _selectDict(dictName); // 点击确认按钮才切换词典
          _loadData();
        },
      ),
    );
  }
}

class StudySettingsSheet extends StatefulWidget {
  final String dictName;
  final StudySettings currentSettings;
  final Function(StudySettings) onConfirm;

  const StudySettingsSheet({
    super.key,
    required this.dictName,
    required this.currentSettings,
    required this.onConfirm,
  });

  @override
  State<StudySettingsSheet> createState() => _StudySettingsSheetState();
}

class _StudySettingsSheetState extends State<StudySettingsSheet> {
  late int _dailyWords;
  late StudyMode _mode;

  @override
  void initState() {
    super.initState();
    _dailyWords = widget.currentSettings.dailyWords;
    _mode = widget.currentSettings.mode;
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.settings_rounded, color: primaryColor, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '学习设置 · ${widget.dictName}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // 每日学习量
              Row(
                children: [
                  Text(
                    '每日学习',
                    style: TextStyle(
                      fontSize: 14,
                      color: context.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  _buildStepButton(Icons.remove, () {
                    if (_dailyWords > 10) setState(() => _dailyWords -= 5);
                  }),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '$_dailyWords 词',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                  ),
                  _buildStepButton(Icons.add, () {
                    if (_dailyWords < 50) setState(() => _dailyWords += 5);
                  }),
                ],
              ),
              const SizedBox(height: 20),
              // 学习模式 - 横向排列
              Text(
                '学习模式',
                style: TextStyle(fontSize: 14, color: context.textSecondary),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildModeChip(
                    StudyMode.sequential,
                    '顺序',
                    Icons.format_list_numbered_rounded,
                  ),
                  const SizedBox(width: 8),
                  _buildModeChip(
                    StudyMode.byDifficulty,
                    '难度',
                    Icons.trending_up_rounded,
                  ),
                  const SizedBox(width: 8),
                  _buildModeChip(StudyMode.random, '随机', Icons.shuffle_rounded),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    widget.onConfirm(
                      StudySettings(dailyWords: _dailyWords, mode: _mode),
                    );
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '选择词典',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: context.backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.dividerColor),
        ),
        child: Icon(icon, size: 18, color: context.textSecondary),
      ),
    );
  }

  Widget _buildModeChip(StudyMode mode, String label, IconData icon) {
    final isSelected = _mode == mode;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mode = mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? primaryColor.withValues(alpha: 0.1)
                : context.backgroundColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? primaryColor : context.dividerColor,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? primaryColor : context.textSecondary,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? primaryColor : context.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
