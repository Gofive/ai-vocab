import 'dart:async';
import 'package:ai_vocab/db_helper.dart';
import 'package:ai_vocab/models/study_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 全局当前词典状态提供者
final currentDictProvider =
    AsyncNotifierProvider<CurrentDictNotifier, DictProgress?>(
      CurrentDictNotifier.new,
    );

class CurrentDictNotifier extends AsyncNotifier<DictProgress?> {
  final DBHelper _db = DBHelper();

  @override
  Future<DictProgress?> build() async {
    return _loadData();
  }

  Future<DictProgress?> _loadData() async {
    // 1. 获取当前选择的词典
    String? currentDict = await _db.getCurrentDict();

    // 2. 如果没有保存的选择，使用第一个词典
    if (currentDict == null) {
      final dicts = await _db.getDictList();
      if (dicts.isNotEmpty) {
        currentDict = dicts.first['name'] as String;
        await _db.setCurrentDict(currentDict);
      }
    }

    // 3. 如果还是没有，说明没有词典数据
    if (currentDict == null) return null;

    // 4. 加载进度
    return await _db.getDictProgress(currentDict);
  }

  /// 刷新数据
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _loadData());
  }

  /// 切换词典
  Future<void> switchDict(String dictName) async {
    state = const AsyncValue.loading();
    await _db.setCurrentDict(dictName);
    state = await AsyncValue.guard(() => _loadData());
  }

  /// 更新每日单词数量
  Future<void> updateDailyWords(int count) async {
    final current = state.value;
    if (current == null) return;

    final newSettings = StudySettings(
      dailyWords: count,
      mode: current.settings.mode,
    );
    await _db.saveStudySettings(current.dictName, newSettings);
    await refresh();
  }

  /// 更新学习模式
  Future<void> updateStudyMode(StudyMode mode) async {
    final current = state.value;
    if (current == null) return;

    final newSettings = StudySettings(
      dailyWords: current.settings.dailyWords,
      mode: mode,
    );
    await _db.saveStudySettings(current.dictName, newSettings);
    await refresh();
  }
}
