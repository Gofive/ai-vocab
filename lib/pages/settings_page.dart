import 'package:flutter/material.dart';
import 'package:ai_vocab/theme/app_theme.dart';
import 'package:ai_vocab/db_helper.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.backgroundColor,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '我的',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 32),
                    _buildUserCard(context),
                    const SizedBox(height: 24),
                    _buildSettingsSection(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.secondary,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '学习者',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '坚持学习，每天进步',
                  style: TextStyle(fontSize: 14, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: context.isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        children: [
          _buildSettingItem(
            context,
            icon: Icons.notifications_outlined,
            title: '学习提醒',
            subtitle: '每日提醒你学习',
            onTap: () {},
          ),
          _buildDivider(context),
          _buildSettingItem(
            context,
            icon: Icons.dark_mode_outlined,
            title: '深色模式',
            subtitle: '跟随系统',
            trailing: Icon(
              context.isDark ? Icons.dark_mode : Icons.light_mode,
              color: context.textSecondary,
            ),
          ),
          _buildDivider(context),
          _buildSettingItem(
            context,
            icon: Icons.volume_up_outlined,
            title: '发音设置',
            subtitle: '美式/英式发音',
            onTap: () {},
          ),
          _buildDivider(context),
          _buildSettingItem(
            context,
            icon: Icons.delete_outline,
            title: '清除学习记录',
            subtitle: '重置所有进度',
            onTap: () {},
          ),
          _buildDivider(context),
          _buildSettingItem(
            context,
            icon: Icons.info_outline,
            title: '关于',
            subtitle: 'v1.0.0',
            onTap: () {},
          ),
          _buildDivider(context),
          _buildSettingItem(
            context,
            icon: Icons.bug_report,
            title: 'Debug: 复习时间-1天',
            subtitle: '用于测试复习模块',
            trailing: const Icon(Icons.touch_app, color: Colors.red),
            onTap: () async {
              await DBHelper().debugReduceReviewDate();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已将所有在学单词复习时间提前1天')),
                );
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
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: context.isDark
              ? AppTheme.darkDivider
              : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: context.textSecondary),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: context.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 13, color: context.textSecondary),
      ),
      trailing:
          trailing ?? Icon(Icons.chevron_right, color: context.textSecondary),
      onTap: onTap,
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Divider(
      height: 1,
      indent: 80,
      endIndent: 20,
      color: context.dividerColor,
    );
  }
}
