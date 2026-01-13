import 'package:flutter/material.dart';
import 'package:ai_vocab/db_helper.dart';
import 'package:ai_vocab/models/study_settings.dart';

class DictPage extends StatefulWidget {
  const DictPage({super.key});

  @override
  State<DictPage> createState() => _DictPageState();
}

class _DictPageState extends State<DictPage> {
  List<Map<String, dynamic>> _dictList = [];
  Map<String, DictProgress> _progressMap = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = DBHelper();
    final dicts = await db.getDictList();

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
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '选择词典',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '选择一个词典开始你的学习之旅',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final dict = _dictList[index];
                        final name = dict['name'] as String;
                        final count = dict['word_count'] as int;
                        final progress = _progressMap[name];
                        return _buildDictCard(name, count, progress);
                      }, childCount: _dictList.length),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildDictCard(String name, int wordCount, DictProgress? progress) {
    final learned = progress?.learnedCount ?? 0;
    final progressValue = progress?.progress ?? 0;

    return GestureDetector(
      onTap: () => _showSettingsSheet(name, progress),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).colorScheme.primary,
                        Theme.of(context).colorScheme.secondary,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.menu_book,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$wordCount 词',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.grey[400]),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progressValue,
                      minHeight: 6,
                      backgroundColor: Colors.grey[200],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$learned / $wordCount',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showSettingsSheet(String dictName, DictProgress? progress) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StudySettingsSheet(
        dictName: dictName,
        currentSettings: progress?.settings ?? const StudySettings(),
        onConfirm: (settings) async {
          await DBHelper().saveStudySettings(dictName, settings);
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
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '学习设置 - ${widget.dictName}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),

              // 每日单词数
              const Text(
                '每日学习单词数',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    '$_dailyWords',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const Text(' 词/天', style: TextStyle(color: Colors.grey)),
                ],
              ),
              Slider(
                value: _dailyWords.toDouble(),
                min: 10,
                max: 30,
                divisions: 4,
                label: '$_dailyWords',
                onChanged: (v) => setState(() => _dailyWords = v.round()),
              ),

              const SizedBox(height: 24),

              // 学习模式
              const Text(
                '学习模式',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 12),
              _buildModeOption(
                StudyMode.sequential,
                '按顺序学习',
                Icons.format_list_numbered,
              ),
              _buildModeOption(
                StudyMode.byDifficulty,
                '按难度学习',
                Icons.trending_up,
              ),
              _buildModeOption(StudyMode.random, '随机抽取', Icons.shuffle),

              const SizedBox(height: 24),

              // 确认按钮
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    widget.onConfirm(
                      StudySettings(dailyWords: _dailyWords, mode: _mode),
                    );
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    '开始学习',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeOption(StudyMode mode, String label, IconData icon) {
    final isSelected = _mode == mode;
    return GestureDetector(
      onTap: () => setState(() => _mode = mode),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
              : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey[600],
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey[700],
              ),
            ),
            const Spacer(),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}
