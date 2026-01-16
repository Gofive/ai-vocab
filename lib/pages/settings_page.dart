import 'package:flutter/material.dart';
import 'package:ai_vocab/theme/app_theme.dart';
import 'package:ai_vocab/db_helper.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _darkMode = true;
  bool _notificationEnabled = true;
  int _dailyGoal = 10;
  String _reminderTime = '08:30 AM';

  // 统计数据（实际应从数据库获取）
  int _learnedWords = 0;
  int _activeDays = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    // 这里可以从数据库加载实际数据
    // TODO: 从 DBHelper 获取实际统计数据
    setState(() {
      _learnedWords = 1240; // 替换为实际数据
      _activeDays = 45; // 替换为实际数据
    });
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: context.backgroundColor,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    // 用户头像和信息
                    _buildUserProfile(context, primaryColor),
                    const SizedBox(height: 24),
                    // 统计卡片
                    _buildStatsCards(context, primaryColor),
                    const SizedBox(height: 28),
                    // 账户设置
                    _buildSectionTitle('账户设置'),
                    const SizedBox(height: 12),
                    _buildAccountSection(context, primaryColor),
                    const SizedBox(height: 28),
                    // 学习偏好
                    _buildSectionTitle('学习偏好'),
                    const SizedBox(height: 12),
                    _buildPreferencesSection(context, primaryColor),
                    const SizedBox(height: 28),
                    // 其他设置
                    _buildOtherSection(context, primaryColor),
                    const SizedBox(height: 28),
                    // 退出登录按钮
                    _buildLogoutButton(context, primaryColor),
                    const SizedBox(height: 20),
                    // 版本信息
                    _buildVersionInfo(context),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserProfile(BuildContext context, Color primaryColor) {
    return Center(
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: primaryColor.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: ClipOval(
                  child: Container(
                    color: context.surfaceColor,
                    child: Icon(Icons.person, size: 38, color: primaryColor),
                  ),
                ),
              ),
              // PRO 标签
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(context.radiusSm),
                  ),
                  child: Text(
                    'PRO',
                    style: context.textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 8,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: context.spaceMd),
          Text('学习者', style: context.textTheme.headlineSmall),
          SizedBox(height: context.spaceXs),
          Text('learner@example.com', style: context.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _buildStatsCards(BuildContext context, Color primaryColor) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            context,
            icon: Icons.bar_chart_rounded,
            iconColor: primaryColor,
            label: '已学单词',
            value: _learnedWords.toString(),
            change: '+12%',
            changePositive: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            context,
            icon: Icons.local_fire_department_rounded,
            iconColor: Colors.orange,
            label: '活跃天数',
            value: _activeDays.toString(),
            change: '+5%',
            changePositive: true,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String change,
    required bool changePositive,
  }) {
    return Container(
      padding: EdgeInsets.all(context.spaceLg),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 24),
          SizedBox(height: context.spaceSm),
          Text(label, style: context.textTheme.labelMedium),
          SizedBox(height: context.spaceXs),
          Text(
            value,
            style: context.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: context.textTheme.labelMedium);
  }

  Widget _buildAccountSection(BuildContext context, Color primaryColor) {
    return Container(
      decoration: context.cardDecoration,
      child: Column(
        children: [
          _buildSettingItem(
            context,
            icon: Icons.person_outline,
            iconColor: primaryColor,
            title: '编辑个人资料',
            onTap: () {},
          ),
          _buildDivider(context),
          _buildSettingItem(
            context,
            icon: Icons.card_membership_outlined,
            iconColor: primaryColor,
            title: '订阅计划',
            subtitle: '高级会员已激活',
            subtitleColor: primaryColor,
            onTap: () {},
          ),
          _buildDivider(context),
          _buildSettingItem(
            context,
            icon: Icons.security_outlined,
            iconColor: primaryColor,
            title: '安全设置',
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildPreferencesSection(BuildContext context, Color primaryColor) {
    return Container(
      decoration: context.cardDecoration,
      child: Column(
        children: [
          _buildSettingItem(
            context,
            icon: Icons.flag_outlined,
            iconColor: primaryColor,
            title: '每日目标',
            trailing: Text(
              '$_dailyGoal 词/日',
              style: TextStyle(fontSize: 14, color: context.textSecondary),
            ),
            onTap: () => _showDailyGoalPicker(context),
          ),
          _buildDivider(context),
          _buildSettingItem(
            context,
            icon: Icons.access_time_outlined,
            iconColor: primaryColor,
            title: '提醒时间',
            trailing: Text(
              _reminderTime,
              style: TextStyle(fontSize: 14, color: context.textSecondary),
            ),
            onTap: () => _showTimePicker(context),
          ),
        ],
      ),
    );
  }

  Widget _buildOtherSection(BuildContext context, Color primaryColor) {
    return Container(
      decoration: context.cardDecoration,
      child: Column(
        children: [
          _buildSettingItem(
            context,
            icon: Icons.notifications_outlined,
            iconColor: primaryColor,
            title: '通知设置',
            trailing: Switch(
              value: _notificationEnabled,
              activeTrackColor: primaryColor,
              onChanged: (value) {
                setState(() => _notificationEnabled = value);
              },
            ),
          ),
          _buildDivider(context),
          _buildSettingItem(
            context,
            icon: Icons.dark_mode_outlined,
            iconColor: primaryColor,
            title: '主题模式',
            trailing: Switch(
              value: _darkMode,
              activeTrackColor: primaryColor,
              onChanged: (value) {
                setState(() => _darkMode = value);
              },
            ),
          ),
          _buildDivider(context),
          _buildSettingItem(
            context,
            icon: Icons.help_outline,
            iconColor: primaryColor,
            title: '帮助与支持',
            onTap: () {},
          ),
          _buildDivider(context),
          _buildSettingItem(
            context,
            icon: Icons.bug_report_outlined,
            iconColor: Colors.orange,
            title: 'Debug: 复习时间-1天',
            onTap: () async {
              await DBHelper().debugReduceReviewDate();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已将所有在学单词复习时间提前1天')),
                );
              }
            },
          ),
          _buildDivider(context),
          _buildSettingItem(
            context,
            icon: Icons.table_chart_outlined,
            iconColor: Colors.purple,
            title: 'Debug: 打印关键表数据',
            onTap: () async {
              final dictName = await DBHelper().getCurrentDict();
              if (dictName != null) {
                await DBHelper().debugPrintTables(dictName);
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('已打印到控制台')));
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSettingItem(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    Color? subtitleColor,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(context.radiusLg),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.spaceLg,
          vertical: context.spaceMd + 2,
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 22),
            SizedBox(width: context.spaceMd + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.textTheme.titleSmall),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: subtitleColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing ??
                Icon(
                  Icons.chevron_right,
                  color: context.textSecondary,
                  size: 22,
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 50),
      child: Divider(height: 1, color: context.dividerColor),
    );
  }

  Widget _buildLogoutButton(BuildContext context, Color primaryColor) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        onPressed: () {
          // 退出登录逻辑
        },
        style: context.outlineButtonStyle,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout, color: primaryColor, size: 20),
            const SizedBox(width: 8),
            Text(
              '退出登录',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVersionInfo(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Text('版本 1.0.0 (1001)', style: context.textTheme.labelSmall),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('隐私政策', style: context.textTheme.labelSmall),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('|', style: context.textTheme.labelSmall),
              ),
              Text('服务条款', style: context.textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }

  void _showDailyGoalPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '每日学习目标',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            ...List.generate(5, (index) {
              final goal = (index + 1) * 5;
              return ListTile(
                title: Text(
                  '$goal 词/日',
                  style: TextStyle(color: context.textPrimary),
                ),
                trailing: _dailyGoal == goal
                    ? Icon(
                        Icons.check,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                onTap: () {
                  setState(() => _dailyGoal = goal);
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showTimePicker(BuildContext context) async {
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 30),
    );
    if (time != null) {
      setState(() {
        _reminderTime = time.format(context);
      });
    }
  }
}
