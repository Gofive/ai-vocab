# 复习单词监听方案重构设计（方案一：全局倒计时管理器）

## 一、当前系统分析

### 1.1 现有架构

- **ReviewReminderService**: 单例服务，使用 ChangeNotifier + Stream 提供响应式 API
- **检查机制**: 每 5 分钟定时检查 + 手动触发 `notifyChange()`
- **业务逻辑**:
  - 从数据库查询到期单词 (`getDueCards`)
  - 自动追加到期单词到今日会话队列 (`appendDueCardsToTodaySession`)
  - 计算紧急单词数量（超过 24 小时）
  - 通知 UI 更新

### 1.2 存在的问题

1. **定时检查间隔过长**: 5 分钟检查一次，无法实时响应单词到期
2. **性能问题**: 每次检查都查询数据库，即使没有单词即将到期
3. **时间不精确**: 从后台切回前台时，可能错过到期时间点
4. **无法应对动态变化**: 如果在运行时插入了更早到期的单词，无法及时响应

## 二、重构方案设计（Listener.md 方案一）

### 2.1 核心思路

**全局倒计时管理器 + 内存中的今日单词列表**

关键优化：

1. **只关注今日**: 只加载今日（00:00 - 23:59:59）到期的单词到内存
2. **心跳扫描**: 使用单个 Timer 每秒扫描内存列表
3. **纯内存操作**: 所有到期检测在内存中完成，无需频繁查询数据库
4. **动态更新**: 数据变更时更新内存列表，Timer 自动检测
5. **自动处理**: 初始化后，定时器第一次执行就会自动处理已过期单词（无需单独处理）
6. **跨天处理**: 监听日期变化，跨天时重新加载新一天的数据

### 2.2 架构设计

```
┌─────────────────────────────────────────────────────────┐
│                  ReviewReminderService                   │
│                (单例 + ChangeNotifier)                   │
├─────────────────────────────────────────────────────────┤
│  内存数据:                                               │
│  List<WordCard> _todayDueWords = []  // 今日到期单词    │
│  Timer? _heartbeatTimer              // 每秒心跳        │
│  Set<int> _processedWordIds          // 已处理的单词ID  │
│  String _currentDate                 // 当前日期        │
├─────────────────────────────────────────────────────────┤
│  初始化阶段:                                             │
│  1. 从数据库加载今日到期的单词到内存                     │
│  2. 启动心跳 Timer（每秒扫描一次）                       │
│  3. 定时器第一次执行时自动处理已过期单词                 │
├─────────────────────────────────────────────────────────┤
│  运行时（每秒心跳）:                                     │
│  1. 检查是否跨天 → 是则重新加载新一天的数据              │
│  2. 扫描内存列表，找出新到期的单词                       │
│  3. 执行业务逻辑（追加到会话队列）                       │
│  4. 标记已处理的单词                                     │
│  5. 通知 UI 更新                                         │
├─────────────────────────────────────────────────────────┤
│  数据变更:                                               │
│  1. 新增/更新单词 → 重新加载今日内存列表                 │
│  2. 清空已处理标记                                       │
│  3. Timer 继续运行，下次心跳自动检测                     │
├─────────────────────────────────────────────────────────┤
│  生命周期:                                               │
│  1. 前台恢复 → 检查日期 → 重新加载内存列表              │
│  2. 后台挂起 → Timer 继续运行（系统允许的情况下）        │
└─────────────────────────────────────────────────────────┘
```

### 2.3 工作流程示例

假设现在是 **2025-01-16 14:00**，内存中有以下单词：

| 单词   | 到期时间         | 状态   |
| ------ | ---------------- | ------ |
| apple  | 2025-01-16 14:05 | 未到期 |
| banana | 2025-01-16 14:30 | 未到期 |
| cat    | 2025-01-16 15:00 | 未到期 |

**14:00** - 初始化

```
1. 从数据库加载今日（2025-01-16）到期的 3 个单词到内存
2. 启动心跳 Timer（每秒触发）
3. 不单独处理已过期单词，等待定时器第一次执行
```

**14:00:01** - 第一次心跳

```
1. 检查日期：仍是 2025-01-16，无需重新加载
2. 扫描内存列表：没有到期的单词
3. 更新 UI（显示倒计时）
```

**14:03** - 数据库插入新单词

```
用户学习了一个新单词 "dog"，到期时间 2025-01-16 14:04

1. 调用 notifyChange()
2. 重新加载今日内存列表：[dog(14:04), apple(14:05), banana(14:30), cat(15:00)]
3. 清空已处理标记
4. Timer 继续运行
```

**14:04:00** - 心跳检测

```
1. 检查日期：仍是 2025-01-16
2. 扫描内存列表：发现 dog 已到期
3. 执行业务逻辑：追加到会话队列
4. 标记 dog 为已处理
5. 通知 UI 更新
```

**14:05:00** - 心跳检测

```
1. 检查日期：仍是 2025-01-16
2. 扫描内存列表：发现 apple 已到期
3. 执行业务逻辑
4. 标记 apple 为已处理
5. 通知 UI 更新
```

**次日 00:00:01** - 跨天检测

```
1. 检查日期：变为 2025-01-17
2. 重新加载新一天的数据
3. 清空已处理标记
4. 继续心跳扫描
```

**关键优势**：

- ✅ 只关注今日数据，内存占用更小
- ✅ 即使在 14:03 插入了更早到期的单词，系统也能在 14:04 准时检测到
- ✅ 自动跨天处理，无需手动干预

## 三、详细设计

### 3.1 数据模型

```dart
class ReviewReminderService extends ChangeNotifier
    with WidgetsBindingObserver {

  // ========== 内存数据 ==========

  /// 内存中的今日到期单词列表（按到期时间排序）
  List<WordCard> _todayDueWords = [];

  /// 心跳 Timer（每秒扫描一次）
  Timer? _heartbeatTimer;

  /// 当前词典
  String? _currentDictName;

  /// 当前日期（用于检测跨天）
  String _currentDate = '';

  /// 已处理的单词 ID 集合（避免重复处理）
  final Set<int> _processedWordIds = {};

  /// 统计信息（缓存）
  ReviewReminderInfo _reminderInfo = const ReviewReminderInfo();

  /// Stream 控制器
  final _streamController = StreamController<ReviewReminderInfo>.broadcast();

  // ========== 防抖 ==========

  DateTime? _lastRefreshTime;
  static const _debounceInterval = Duration(milliseconds: 300);

  // ========== 辅助方法 ==========

  /// 获取今日日期字符串（格式：2025-01-16）
  String _getTodayDateString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// 获取今日开始时间（UTC）
  DateTime _getTodayStart() {
    final now = DateTime.now();
    final localStart = DateTime(now.year, now.month, now.day);
    return localStart.toUtc();
  }

  /// 获取今日结束时间（UTC）
  DateTime _getTodayEnd() {
    final now = DateTime.now();
    final localEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
    return localEnd.toUtc();
  }
}
```

### 3.2 核心方法

#### 3.2.1 初始化

```dart
/// 初始化服务
Future<void> initialize(String dictName) async {
  _currentDictName = dictName;
  _currentDate = _getTodayDateString();

  // 1. 从数据库加载今日到期的单词到内存
  await _loadTodayDueWordsToMemory();

  // 2. 启动心跳 Timer（每秒扫描一次）
  // 注意：不单独处理已过期单词，定时器第一次执行时会自动处理
  _startHeartbeat();

  // 3. 启动生命周期监听
  WidgetsBinding.instance.addObserver(this);

  debugPrint('ReviewReminder: 初始化完成，内存中有 ${_todayDueWords.length} 个今日到期单词');
}
```

#### 3.2.2 加载今日单词到内存

```dart
/// 从数据库加载今日到期的单词到内存
///
/// 只加载今日（00:00 - 23:59:59）到期的单词，减少内存占用。
Future<void> _loadTodayDueWordsToMemory() async {
  if (_currentDictName == null) return;

  final db = DBHelper();
  final todayStart = _getTodayStart();
  final todayEnd = _getTodayEnd();

  // 加载今日到期的单词（due 在今日范围内）
  final todayCards = await db.getTodayDueCards(
    _currentDictName!,
    todayStart,
    todayEnd,
  );

  // 按到期时间排序（早的在前）
  todayCards.sort((a, b) => a.card.due.compareTo(b.card.due));

  _todayDueWords = todayCards;

  debugPrint('ReviewReminder: 加载了 ${_todayDueWords.length} 个今日到期单词到内存');
}
```

#### 3.2.3 启动心跳

```dart
/// 启动心跳 Timer（每秒扫描一次内存列表）
void _startHeartbeat() {
  _heartbeatTimer?.cancel();

  // 每秒触发一次
  _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
    _onHeartbeat();
  });

  debugPrint('ReviewReminder: 心跳 Timer 已启动');
}

/// 心跳回调：检查跨天、检查到期单词
void _onHeartbeat() {
  if (_currentDictName == null) return;

  // 1. 检查是否跨天
  final todayDate = _getTodayDateString();
  if (todayDate != _currentDate) {
    debugPrint('ReviewReminder: 检测到跨天 $_currentDate -> $todayDate，重新加载数据');
    _currentDate = todayDate;
    _processedWordIds.clear();
    _loadTodayDueWordsToMemory().then((_) => _updateReminderInfo());
    return;
  }

  if (_todayDueWords.isEmpty) {
    _updateReminderInfo();
    return;
  }

  // 2. 找出刚刚到期的单词（未被处理过的）
  final now = DateTime.now().toUtc();
  final newlyExpired = _todayDueWords.where((card) {
    final isDue = card.card.due.isBefore(now) ||
                  card.card.due.isAtSameMomentAs(now);
    final notProcessed = !_processedWordIds.contains(card.wordId);
    return isDue && notProcessed;
  }).toList();

  if (newlyExpired.isEmpty) {
    // 没有新到期的单词，只更新 UI（倒计时）
    _updateReminderInfo();
    return;
  }

  debugPrint('ReviewReminder: 心跳检测到 ${newlyExpired.length} 个新到期单词');

  // 3. 异步处理到期单词（不阻塞心跳）
  _handleNewlyExpiredWords(newlyExpired);
}

/// 处理新到期的单词
Future<void> _handleNewlyExpiredWords(List<WordCard> words) async {
  if (_currentDictName == null) return;

  // 执行业务逻辑：追加到今日会话队列
  final db = DBHelper();
  final addedCount = await db.appendDueCardsToTodaySession(_currentDictName!);

  if (addedCount > 0) {
    debugPrint('ReviewReminder: 心跳处理，已追加 $addedCount 个到期单词到今日队列');
  }

  // 标记为已处理
  for (final word in words) {
    _processedWordIds.add(word.wordId);
  }

  // 更新统计信息并通知 UI
  _updateReminderInfo();
}
```

#### 3.2.4 更新统计信息

```dart
/// 更新统计信息（从内存计算，不查询数据库）
void _updateReminderInfo() {
  if (_todayDueWords.isEmpty) {
    _reminderInfo = const ReviewReminderInfo();
    notifyListeners();
    if (!_streamController.isClosed) {
      _streamController.add(_reminderInfo);
    }
    return;
  }

  final now = DateTime.now().toUtc();
  final yesterday = now.subtract(const Duration(hours: 24));

  // 统计已到期的单词
  int dueCount = 0;
  int urgentCount = 0;
  final dueWords = <DueWordInfo>[];
  DateTime? nextDueTime;

  for (final card in _todayDueWords) {
    final dueTime = card.card.due;
    final isDue = dueTime.isBefore(now) || dueTime.isAtSameMomentAs(now);

    if (isDue) {
      dueCount++;
      final isUrgent = dueTime.isBefore(yesterday);
      if (isUrgent) urgentCount++;

      if (dueWords.length < 5) {
        dueWords.add(DueWordInfo(
          wordId: card.wordId,
          word: card.word,
          dueTime: dueTime,
          isUrgent: isUrgent,
        ));
      }
    } else {
      // 第一个未到期的单词就是下一个到期时间
      if (nextDueTime == null) {
        nextDueTime = dueTime;
      }
    }
  }

  _reminderInfo = ReviewReminderInfo(
    dueCount: dueCount,
    urgentCount: urgentCount,
    nextDueTime: nextDueTime,
    dueWords: dueWords,
  );

  // 通知 UI
  notifyListeners();
  if (!_streamController.isClosed) {
    _streamController.add(_reminderInfo);
  }
}
```

#### 3.2.5 数据变更通知

```dart
/// 通知数据变更（供外部调用）
///
/// 当有新单词学习、复习完成等操作时调用此方法。
/// 会重新加载今日内存列表，确保数据同步。
Future<void> notifyChange() async {
  // 防抖
  final now = DateTime.now();
  if (_lastRefreshTime != null &&
      now.difference(_lastRefreshTime!) < _debounceInterval) {
    return;
  }
  _lastRefreshTime = now;

  debugPrint('ReviewReminder: 收到数据变更通知，重新加载今日内存列表');

  // 检查是否跨天
  final todayDate = _getTodayDateString();
  if (todayDate != _currentDate) {
    _currentDate = todayDate;
  }

  // 重新加载今日内存列表
  await _loadTodayDueWordsToMemory();

  // 清空已处理标记（因为数据可能变化）
  _processedWordIds.clear();

  // 更新统计信息
  _updateReminderInfo();
}

/// 强制刷新（重新加载内存列表）
Future<void> forceRefresh() async {
  _lastRefreshTime = null;
  await notifyChange();
}

/// 刷新（别名，兼容旧代码）
Future<void> refresh() => notifyChange();
```

#### 3.2.6 生命周期监听

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) {
    debugPrint('ReviewReminder: 应用恢复前台，检查日期并重新加载');

    // 检查是否跨天
    final todayDate = _getTodayDateString();
    if (todayDate != _currentDate) {
      _currentDate = todayDate;
      _processedWordIds.clear();
    }

    // 重新加载今日数据
    _loadTodayDueWordsToMemory().then((_) => _updateReminderInfo());
  }
}

@override
void dispose() {
  WidgetsBinding.instance.removeObserver(this);
  _heartbeatTimer?.cancel();
  _streamController.close();
  super.dispose();
}
```

### 3.3 数据库辅助方法

需要在 `DBHelper` 中添加新方法：

```dart
/// 获取今日到期的单词
///
/// [dictName] - 词典名称
/// [todayStart] - 今日开始时间（UTC）
/// [todayEnd] - 今日结束时间（UTC）
///
/// 返回 due 时间在 [todayStart, todayEnd] 范围内的所有单词
Future<List<WordCard>> getTodayDueCards(
  String dictName,
  DateTime todayStart,
  DateTime todayEnd,
) async {
  final db = await database;

  final results = await db.rawQuery(
    '''
    SELECT usp.word_id, usp.dict_name, usp.due, usp.stability, usp.difficulty,
           usp.elapsed_days, usp.scheduled_days, usp.reps, usp.lapses,
           usp.state, usp.last_review, w.word
    FROM user_study_progress usp
    JOIN words w ON usp.word_id = w.id
    WHERE usp.dict_name = ?
      AND usp.due IS NOT NULL AND usp.due != ''
      AND usp.due >= ? AND usp.due <= ?
    ORDER BY usp.due ASC
    ''',
    [dictName, todayStart.toIso8601String(), todayEnd.toIso8601String()],
  );

  return results.map((row) => WordCard.fromMap(row)).toList();
}
```

## 四、性能分析

### 4.0 时间精度说明

**关键要求：单词到期时间精确到秒**

#### 4.0.1 时间存储格式

数据库中的 `due` 字段存储格式：

```
ISO 8601 格式（UTC 时间）：2025-01-16T14:05:30.000Z
精度：毫秒级（实际使用秒级）
```

#### 4.0.2 时间比较逻辑

```dart
// 获取当前时间（UTC，精确到毫秒）
final now = DateTime.now().toUtc();

// 判断单词是否到期（精确到秒）
final isDue = card.card.due.isBefore(now) ||
              card.card.due.isAtSameMomentAs(now);

// 说明：
// - card.card.due: 单词的到期时间（UTC，精确到毫秒）
// - now: 当前时间（UTC，精确到毫秒）
// - isBefore: 严格小于（<）
// - isAtSameMomentAs: 严格等于（==）
// - 组合起来就是：card.card.due <= now
```

#### 4.0.3 时间精度示例

假设单词 apple 的到期时间是 `2025-01-16T14:05:30.000Z`：

| 当前时间                 | 是否到期 | 说明        |
| ------------------------ | -------- | ----------- |
| 2025-01-16T14:05:29.999Z | ❌ 否    | 差 1 毫秒   |
| 2025-01-16T14:05:30.000Z | ✅ 是    | 精确相等    |
| 2025-01-16T14:05:30.001Z | ✅ 是    | 超过 1 毫秒 |
| 2025-01-16T14:05:31.000Z | ✅ 是    | 超过 1 秒   |

**结论**：

- 时间比较精确到毫秒级
- 心跳每秒检测一次，最多延迟 1 秒
- 实际精度：秒级（满足需求）

#### 4.0.4 FSRS 算法的时间精度

FSRS 算法计算的 `due` 时间：

```dart
// FSRS 返回的 Card 对象
Card {
  due: DateTime(2025, 1, 16, 14, 5, 30),  // 精确到秒
  stability: 5.2,
  difficulty: 6.8,
  ...
}
```

**注意事项**：

1. FSRS 算法本身计算的时间精确到秒
2. 数据库存储时使用 ISO 8601 格式（包含毫秒）
3. 时间比较时使用 UTC 时间，避免时区问题
4. 心跳每秒检测，确保秒级响应

### 4.1 内存占用

假设今日有 100 个到期单词（通常情况）：

- 每个 WordCard 对象约 100 字节
- 总内存：100 × 100 = 10KB

极端情况（今日 1000 个到期单词）：

- 总内存：1000 × 100 = 100KB

**结论**：内存占用极小，完全可接受

### 4.2 CPU 占用

- 每秒扫描 100 个单词（通常情况）
- 每个单词只做时间比较（O(1) 操作）
- 总复杂度：O(n)，n = 今日单词数量

**结论**：CPU 占用极低，现代手机完全无压力

### 4.3 数据库查询

- 初始化时：1 次查询（加载今日单词）
- 数据变更时：1 次查询（重新加载今日单词）
- 前台恢复时：1 次查询（重新加载今日单词）
- 跨天时：1 次查询（加载新一天的单词）
- 运行时：0 次查询

**对比旧方案**：

- 旧方案：每 5 分钟 1 次 = 每小时 12 次 = 每天 288 次
- 新方案：每天约 10 次（启动 + 数据变更 + 前台恢复 + 跨天）

**结论**：减少 97% 的数据库查询

## 五、关键优势

### 5.1 精确性

✅ 每秒检测，最多延迟 1 秒  
✅ 动态插入的单词也能及时检测  
✅ 从后台切回前台时立即重新加载  
✅ 自动跨天处理，无需手动干预

### 5.2 性能

✅ 纯内存操作，无需频繁查询数据库  
✅ 只关注今日数据，内存占用极小（通常 10KB）  
✅ 单个 Timer，资源占用极低  
✅ 减少 97% 的数据库查询

### 5.3 可靠性

✅ 不依赖精确的 Timer 触发时间  
✅ 数据变更时自动同步  
✅ 生命周期感知，确保数据准确  
✅ 日期格式统一，避免时区问题

### 5.4 简洁性

✅ 初始化后无需单独处理已过期单词  
✅ 定时器第一次执行就会自动处理  
✅ 逻辑清晰：加载 → 心跳扫描 → 自动处理

## 六、实施步骤

### 6.1 第一阶段：数据库层

1. 在 `DBHelper` 中添加 `getTodayDueCards()` 方法
2. 测试方法正确性（注意时区和日期格式）

### 6.2 第二阶段：重构服务层

1. 修改 `ReviewReminderService`
   - 添加 `_todayDueWords`、`_currentDate`、`_processedWordIds` 字段
   - 添加日期辅助方法：`_getTodayDateString()`、`_getTodayStart()`、`_getTodayEnd()`
   - 实现 `_loadTodayDueWordsToMemory()`
   - 实现 `_startHeartbeat()` 和 `_onHeartbeat()`（包含跨天检测）
   - 实现 `_updateReminderInfo()`
   - 简化 `initialize()`（移除单独处理已过期单词的逻辑）
2. 移除旧的 `_checkTimer` 和 `_startPeriodicCheck()`
3. 更新 `notifyChange()` 方法（添加跨天检测）

### 6.3 第三阶段：测试验证

1. 单元测试：
   - 验证日期格式一致性
   - 验证跨天检测逻辑
   - 验证心跳扫描逻辑
2. 集成测试：
   - 验证业务逻辑保持不变
   - 验证动态插入单词的场景
   - 验证跨天场景
3. 性能测试：对比重构前后的性能

### 6.4 第四阶段：上线监控

1. 灰度发布
2. 监控性能指标
3. 收集用户反馈

## 七、风险评估

### 7.1 潜在风险

1. **时区和日期格式**
   - 风险：UTC 和本地时间转换可能导致日期判断错误
   - 缓解：统一使用本地时间判断日期，UTC 时间用于数据库查询
2. **跨天边界情况**
   - 风险：23:59:59 到 00:00:00 的边界情况
   - 缓解：每秒检测日期变化，确保及时切换
3. **Timer 在后台的行为**
   - 风险：iOS/Android 可能暂停后台 Timer
   - 缓解：使用生命周期监听，前台恢复时重新加载

### 7.2 回滚方案

- 保留旧代码作为备份
- 使用 feature flag 控制新旧方案切换
- 充分测试后再完全移除旧代码

## 八、总结

本方案完全采用 Listener.md 中的**方案一（全局倒计时管理器）**，并进行了关键优化：

✅ 只加载今日到期的单词到内存（减少内存占用）  
✅ 使用单个 Timer 每秒扫描（高效可靠）  
✅ 所有操作在内存中完成（无需频繁查询数据库）  
✅ 初始化后定时器自动处理已过期单词（无需单独处理）  
✅ 自动跨天检测和数据重新加载  
✅ 动态插入的单词也能及时检测  
✅ 日期格式统一，避免时区问题  
✅ 保持现有业务逻辑不变

相比现有方案，新方案在**精确性、性能、可靠性、简洁性**方面都有显著提升。

---

## 九、时间精度详细说明

### 9.1 为什么需要精确到秒？

FSRS 算法计算的复习间隔可以精确到秒级：

- 短间隔：1 分钟、5 分钟、10 分钟
- 中间隔：1 小时、6 小时、1 天
- 长间隔：3 天、7 天、30 天

对于短间隔（如 1 分钟、5 分钟），秒级精度非常重要。

### 9.2 时间精度实现

#### 9.2.1 数据库存储

```sql
-- user_study_progress 表
CREATE TABLE user_study_progress (
  ...
  due TEXT,  -- ISO 8601 格式：2025-01-16T06:05:30.000Z
  ...
);
```

**存储格式**：

- 格式：ISO 8601（UTC 时间）
- 示例：`2025-01-16T06:05:30.000Z`
- 精度：毫秒级（`.000` 表示毫秒）

#### 9.2.2 Dart 时间比较

```dart
// 获取当前时间（UTC，精确到毫秒）
final now = DateTime.now().toUtc();
// 示例：2025-01-16T06:05:30.123Z

// 单词到期时间（从数据库读取）
final dueTime = card.card.due;
// 示例：2025-01-16T06:05:30.000Z

// 判断是否到期（精确到毫秒）
final isDue = dueTime.isBefore(now) || dueTime.isAtSameMomentAs(now);
// 等价于：dueTime <= now
```

**Dart DateTime 比较方法**：

- `isBefore(other)`: 严格小于 `<`
- `isAfter(other)`: 严格大于 `>`
- `isAtSameMomentAs(other)`: 严格等于 `==`
- 精度：微秒级（Dart DateTime 内部精度）

#### 9.2.3 实际精度

虽然时间比较精确到毫秒级，但实际响应精度受心跳间隔限制：

| 层级         | 精度     | 说明                                 |
| ------------ | -------- | ------------------------------------ |
| 数据库存储   | 毫秒     | ISO 8601 格式                        |
| Dart 比较    | 微秒     | DateTime 内部精度                    |
| 心跳检测     | 1 秒     | Timer.periodic(Duration(seconds: 1)) |
| **实际响应** | **1 秒** | 最多延迟 1 秒                        |

### 9.3 时间精度测试用例

#### 测试用例 1：精确到秒的到期

```dart
// 单词到期时间：14:05:30
final dueTime = DateTime.utc(2025, 1, 16, 6, 5, 30);

// 测试不同的当前时间
test('14:05:29 - 未到期', () {
  final now = DateTime.utc(2025, 1, 16, 6, 5, 29);
  expect(dueTime.isBefore(now) || dueTime.isAtSameMomentAs(now), false);
});

test('14:05:30 - 到期', () {
  final now = DateTime.utc(2025, 1, 16, 6, 5, 30);
  expect(dueTime.isBefore(now) || dueTime.isAtSameMomentAs(now), true);
});

test('14:05:31 - 已过期', () {
  final now = DateTime.utc(2025, 1, 16, 6, 5, 31);
  expect(dueTime.isBefore(now) || dueTime.isAtSameMomentAs(now), true);
});
```

#### 测试用例 2：毫秒级精度

```dart
// 单词到期时间：14:05:30.000
final dueTime = DateTime.utc(2025, 1, 16, 6, 5, 30, 0);

test('14:05:29.999 - 未到期（差1毫秒）', () {
  final now = DateTime.utc(2025, 1, 16, 6, 5, 29, 999);
  expect(dueTime.isBefore(now) || dueTime.isAtSameMomentAs(now), false);
});

test('14:05:30.000 - 到期（精确相等）', () {
  final now = DateTime.utc(2025, 1, 16, 6, 5, 30, 0);
  expect(dueTime.isBefore(now) || dueTime.isAtSameMomentAs(now), true);
});

test('14:05:30.001 - 已过期（超过1毫秒）', () {
  final now = DateTime.utc(2025, 1, 16, 6, 5, 30, 1);
  expect(dueTime.isBefore(now) || dueTime.isAtSameMomentAs(now), true);
});
```

### 9.4 时间精度保证

#### 9.4.1 FSRS 算法侧

```dart
// FSRS 计算的 Card 对象
final result = fsrsService.reviewCard(card, Rating.good);

// result.card.due 的精度
print(result.card.due);
// 输出：2025-01-16 14:05:30.000Z
// 精度：秒级（毫秒部分为 .000）
```

FSRS 算法本身计算的时间精确到秒，毫秒部分始终为 0。

#### 9.4.2 数据库侧

```dart
// 保存到数据库
await db.saveWordCard(wordCard);

// 数据库中的存储
// due: "2025-01-16T06:05:30.000Z"
// 格式：ISO 8601（UTC）
// 精度：毫秒级（虽然毫秒部分为 0）
```

#### 9.4.3 心跳检测侧

```dart
// 每秒检测一次
Timer.periodic(Duration(seconds: 1), (timer) {
  final now = DateTime.now().toUtc();

  // 扫描内存列表
  for (final card in _todayDueWords) {
    if (card.card.due.isBefore(now) || card.card.due.isAtSameMomentAs(now)) {
      // 到期了！
      _handleExpiredWord(card);
    }
  }
});
```

**保证**：

- 心跳每秒触发一次
- 单词到期后最多 1 秒内被检测到
- 时间比较精确到毫秒级

### 9.5 时间精度优势

相比旧方案（5 分钟检测一次）：

| 指标     | 旧方案 | 新方案 | 改进     |
| -------- | ------ | ------ | -------- |
| 检测间隔 | 5 分钟 | 1 秒   | 300 倍 ↑ |
| 最大延迟 | 5 分钟 | 1 秒   | 99.7% ↓  |
| 时间精度 | 分钟级 | 秒级   | 60 倍 ↑  |

**实际效果**：

- 短间隔复习（1 分钟、5 分钟）：准时提醒
- 中间隔复习（1 小时、6 小时）：准时提醒
- 长间隔复习（1 天、7 天）：准时提醒

### 9.6 总结

✅ **存储精度**：毫秒级（ISO 8601 格式）  
✅ **比较精度**：毫秒级（Dart DateTime）  
✅ **检测精度**：秒级（心跳间隔 1 秒）  
✅ **响应精度**：秒级（最多延迟 1 秒）  
✅ **实际效果**：满足 FSRS 算法的所有复习间隔需求

**结论**：新方案完全满足"精确到秒"的需求！

---

## 十、时间精度修正说明

### 10.1 实际测试结果

通过测试 FSRS 包（v2.0.1），我们发现了一个重要事实：

```dart
// FSRS 返回的 due 时间
final result = scheduler.reviewCard(card, Rating.good);
print(result.card.due.toIso8601String());
// 实际输出：2026-01-16T12:59:45.517228Z
//           ^^^^^^^^^^^^^^^^^^^^^^^^
//           精确到微秒（6位小数）
```

**重要发现**：

- ❌ 之前假设：FSRS 返回的时间精确到秒（毫秒部分为 .000）
- ✅ 实际情况：FSRS 返回的时间精确到**微秒**（6 位小数）

### 10.2 为什么 FSRS 包含微秒？

FSRS 包使用当前时间 `DateTime.now()` 加上计算的间隔：

```dart
// FSRS 内部逻辑（简化）
final now = DateTime.now();  // 包含微秒：2026-01-16T12:49:45.517228Z
final interval = Duration(minutes: 10);
final due = now.add(interval);  // 保留微秒：2026-01-16T12:59:45.517228Z
```

`DateTime.now()` 返回的时间包含微秒精度，FSRS 直接使用，因此 `due` 也包含微秒。

### 10.3 这对我们的方案有影响吗？

**答案：没有影响，反而更好！**

#### 10.3.1 时间比较仍然精确

```dart
// 心跳检测（每秒一次）
final now = DateTime.now().toUtc();  // 2026-01-16T12:59:46.000000Z

// 单词到期时间（包含微秒）
final dueTime = card.card.due;  // 2026-01-16T12:59:45.517228Z

// 判断是否到期（微秒级比较）
final isDue = dueTime.isBefore(now) || dueTime.isAtSameMomentAs(now);
// 结果：true（因为 45.517228 < 46.000000）
```

**结论**：

- 时间比较精确到微秒级
- 心跳每秒检测，最多延迟 1 秒
- 实际精度：秒级（满足需求）

#### 10.3.2 数据库存储

```sql
-- user_study_progress 表
due TEXT  -- 存储 ISO 8601 格式

-- 实际存储的值（包含微秒）
'2026-01-16T12:59:45.517228Z'
```

**优势**：

- 保留完整的时间精度
- 避免精度损失
- 支持未来可能的更精确需求

### 10.4 修正后的时间精度层级

| 层级         | 精度     | 说明                                         |
| ------------ | -------- | -------------------------------------------- |
| FSRS 计算    | 微秒     | `DateTime.now()` 的精度                      |
| 数据库存储   | 微秒     | ISO 8601: `2026-01-16T12:59:45.517228Z`      |
| Dart 比较    | 微秒     | `DateTime.isBefore()` / `isAtSameMomentAs()` |
| 心跳检测     | 1 秒     | `Timer.periodic(Duration(seconds: 1))`       |
| **实际响应** | **1 秒** | 最多延迟 1 秒                                |

### 10.5 修正后的时间精度示例

假设单词到期时间是 `2025-01-16T06:05:30.123456Z`：

| 当前时间                    | 是否到期 | 说明        |
| --------------------------- | -------- | ----------- |
| 2025-01-16T06:05:30.123455Z | ❌ 否    | 差 1 微秒   |
| 2025-01-16T06:05:30.123456Z | ✅ 是    | 精确相等    |
| 2025-01-16T06:05:30.123457Z | ✅ 是    | 超过 1 微秒 |
| 2025-01-16T06:05:31.000000Z | ✅ 是    | 超过 1 秒   |

**实际场景**：

心跳每秒检测一次，假设单词在 `14:05:30.123456` 到期：

- **14:05:30** 心跳 → 当前时间约 `14:05:30.000000` → ❌ 未到期
- **14:05:31** 心跳 → 当前时间约 `14:05:31.000000` → ✅ 到期（延迟约 0.88 秒）

**最大延迟**：1 秒

### 10.6 对比旧方案（修正）

| 指标     | 旧方案 | 新方案 | 改进     |
| -------- | ------ | ------ | -------- |
| 存储精度 | 微秒   | 微秒   | 相同 ✅  |
| 比较精度 | 微秒   | 微秒   | 相同 ✅  |
| 检测间隔 | 5 分钟 | 1 秒   | 300 倍 ↑ |
| 最大延迟 | 5 分钟 | 1 秒   | 99.7% ↓  |
| 实际精度 | 分钟级 | 秒级   | 60 倍 ↑  |

### 10.7 总结（修正）

✅ **存储精度**：微秒级（ISO 8601 格式，6 位小数）  
✅ **比较精度**：微秒级（Dart DateTime）  
✅ **检测精度**：秒级（心跳间隔 1 秒）  
✅ **响应精度**：秒级（最多延迟 1 秒）  
✅ **实际效果**：满足 FSRS 算法的所有复习间隔需求

**关键点**：

1. FSRS 包返回的时间包含微秒，这是正常的（来自 `DateTime.now()`）
2. 数据库存储时保留完整精度，避免精度损失
3. 时间比较在微秒级别进行，非常精确
4. 心跳每秒检测，实际响应精度为秒级
5. 对于复习应用来说，秒级精度完全足够

**结论**：新方案完全满足"精确到秒"的需求，实际精度甚至更高（微秒级存储和比较）！
