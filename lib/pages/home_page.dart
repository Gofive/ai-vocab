import 'package:flutter/material.dart';
import 'package:ai_vocab/pages/dict_page.dart';
import 'package:ai_vocab/pages/study_page.dart';
import 'package:ai_vocab/pages/settings_page.dart';
import 'package:ai_vocab/theme/app_theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  final GlobalKey<StudyPageWrapperState> _studyPageKey = GlobalKey();

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      StudyPageWrapper(key: _studyPageKey),
      const DictPage(),
      const SettingsPage(),
    ];
  }

  void _onTabChanged(int index) {
    setState(() => _currentIndex = index);
    // 切换到学习页面时刷新数据
    if (index == 0) {
      _studyPageKey.currentState?.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: context.surfaceColor,
          border: Border(
            top: BorderSide(color: context.dividerColor, width: 0.5),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.school_outlined, Icons.school, '学习'),
                _buildNavItem(1, Icons.book_outlined, Icons.book, '词典'),
                _buildNavItem(2, Icons.person_outline, Icons.person, '我的'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    IconData icon,
    IconData activeIcon,
    String label,
  ) {
    final isActive = _currentIndex == index;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final color = isActive ? primaryColor : context.textSecondary;

    return Expanded(
      child: GestureDetector(
        onTap: () => _onTabChanged(index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isActive ? activeIcon : icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
