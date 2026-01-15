import 'dart:io';

import 'package:ai_vocab/pages/home_page.dart';
import 'package:ai_vocab/theme/app_theme.dart';
import 'package:ai_vocab/services/ad_service.dart';
import 'package:ai_vocab/services/migration_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 桌面端初始化
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // 初始化 AdMob（仅移动端）
  await AdService().initialize();

  // 全屏沉浸式
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Vocab',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const _AppInitializer(),
    );
  }
}

/// 应用初始化器
///
/// 在应用启动时检测是否需要 FSRS 迁移，并显示迁移进度提示。
///
/// _Requirements: 1.1, 2.4_
class _AppInitializer extends StatefulWidget {
  const _AppInitializer();

  @override
  State<_AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<_AppInitializer> {
  bool _migrationChecked = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // 检查是否需要迁移
    final migrationService = MigrationService();
    final needsMigration = await migrationService.checkMigrationNeeded();

    if (mounted) {
      // 如果需要迁移，显示迁移对话框
      if (needsMigration) {
        await _showMigrationDialog();
      }

      setState(() {
        _migrationChecked = true;
      });
    }
  }

  Future<void> _showMigrationDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => MigrationDialog(
        onComplete: () {
          // 迁移完成后关闭对话框
          Navigator.of(context).pop();
        },
        onError: () {
          // 迁移失败，显示错误但仍允许继续使用应用
          // 用户可以稍后重试
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_migrationChecked) {
      // 显示加载界面
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                '正在初始化...',
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 初始化完成，显示主页
    return const HomePage();
  }
}
