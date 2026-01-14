# 单词学习交互逻辑优化完成报告

## 优化目标

根据 REFACTORING_ANALYSIS.md 文档和用户需求，优化单词学习中的交互逻辑：

1. ✅ 对于新出现的单词，用户点击"不认识"，立即变成复习单词加入今日学习会话的队列尾端
2. ✅ 系统每次进入学习页面对于待复习单词的处理必须准确
3. ✅ 学习页面的各项数据统计必须和单词卡片展示页面的数据同源对齐

---

## 核心修改

### 1. 优化 `getDictProgress` 方法 - 统一数据源

**文件**: `lib/db_helper.dart`

**修改内容**:

- 简化今日新词统计逻辑：直接统计今日 `last_modified` 的所有单词
- 移除动态分母计算，使用原始设置值
- 优化注释，明确数据来源

**关键代码**:

```dart
// 2. 获取今日新词统计 - 统计今日首次学习的单词数量
// 关键：只统计今日 last_modified 的词（不区分状态，因为都是今日学过的）
final todayStatsResult = await db.rawQuery(
  '''
  SELECT COUNT(*) as count
  FROM user_study_progress
  WHERE dict_name = ? AND DATE(last_modified) = ?
  ''',
  [dictName, today],
);

final todayNewCount = (todayStatsResult.first['count'] as int?) ?? 0;
```

**数据来源说明**:

- `totalCount`: 词典总词数（从 `words` 和 `word_dict_rel` 表）
- `learnedCount`: 已学习单词数（从 `user_study_progress` 表，`state >= 1`）
- `todayNewCount`: 今日新词数（从 `user_study_progress` 表，今日 `last_modified`）
- `todayReviewCount`: 待复习数（两部分：1. `user_study_progress` 中到期的词；2. 今日会话队列中未完成的复习任务）

---

### 2. 优化 `_handleFamiliarity` 方法 - 确保"不认识"立即加入队列

**文件**: `lib/pages/study_page.dart`

**修改内容**:

- 增强"不认识"逻辑：明确标记为复习单词
- 添加调试日志，便于追踪
- 优化撤销状态管理

**关键代码**:

```dart
// 关键逻辑：点击"不认识"时，立即将单词加入队列末尾作为复习
bool addedToQueue = false;
if (level == FamiliarityLevel.unfamiliar) {
  final repeatWord = WordProgress(
    wordId: currentWordProgress.wordId,
    word: currentWordProgress.word,
    dictName: widget.dictName,
    easeFactor: progress.easeFactor,
    interval: progress.interval,
    repetition: progress.repetition,
    nextReviewDate: progress.nextReviewDate,
    state: progress.state,
    lastModified: progress.lastModified,
    isReview: true, // 标记为复习单词
  );
  setState(() {
    _session!.queue.add(repeatWord);
  });
  // 添加到数据库队列
  await db.addWordToSessionQueue(_session!.id, repeatWord.wordId);
  addedToQueue = true;

  print('DEBUG: 单词 "${currentWordProgress.word}" 点击不认识，已加入队列末尾 (isNewWord: $isNewWord)');
}
```

**行为说明**:

- 无论是新词还是复习词，点击"不认识"都会加入队列末尾
- 加入队列的单词标记为 `isReview: true`，在 UI 上显示为复习单词
- 支持撤销操作

---

### 3. 优化 `getOrCreateTodaySession` 方法 - 准确处理待复习单词

**文件**: `lib/db_helper.dart`

**修改内容**:

- 增强动态追加逻辑：确保所有到期的复习词都在队列中
- 添加详细的调试日志
- 优化注释，明确每个步骤的作用

**关键逻辑**:

**A. 动态追加待复习单词**:

```dart
// A. 动态追加待复习单词：确保所有到期的复习词都在队列中
// 从 user_study_progress 表获取所有到期的复习词（state=1, next_review_date <= today）
final currentDueWords = await getReviewWords(dictName, limit: 100);
final wordIdsInQueue = queue.map((w) => w.wordId).toSet();

int addedReviewCount = 0;
for (var word in currentDueWords) {
  if (!wordIdsInQueue.contains(word.wordId)) {
    await db.insert('study_session_queue', {
      'session_id': sessionId,
      'word_id': word.wordId,
      'queue_index': nextIdx++,
      'is_review': 1,
      'is_done': 0,
    });
    queue.add(word);
    addedReviewCount++;
  }
}
```

**B. 动态补全新词**:

```dart
// B. 动态补全新词：如果每日目标调整，补充新词到目标数量
final currentNewCount = queue.where((w) => !w.isReview).length;
int addedNewCount = 0;
if (currentNewCount < settings.dailyWords) {
  int wordsToFill = settings.dailyWords - currentNewCount;
  for (int i = 0; i < wordsToFill; i++) {
    final nextNew = await getNextNewWord(dictName, settings, queue);
    if (nextNew == null) break;
    // ... 添加到队列
    addedNewCount++;
  }
}
```

**C. 重新校准索引**:

```dart
// C. 重新校准当前索引：指向第一个未完成的单词
final firstUndoneResult = await db.rawQuery(
  'SELECT MIN(queue_index) as idx FROM study_session_queue WHERE session_id = ? AND is_done = 0',
  [sessionId],
);
```

---

### 4. 优化 UI 显示 - 确保数据同源对齐

**文件**: `lib/pages/study_page.dart`

**修改内容**:

- 优化今日任务卡片的注释，明确数据来源
- 优化学习会话头部的注释，说明动态特性

**今日任务卡片**:

```dart
Widget _buildTodayTaskCard(BuildContext context, Color primaryColor) {
  // 数据来源：widget.progress (DictProgress) - 由 getDictProgress 方法统一计算
  // 今日新词：今日首次学习的单词数量（来自 user_study_progress 表）
  final learnedNewToday = widget.progress.todayNewCount;
  final newWordsGoal = widget.progress.settings.dailyWords;

  // 待复习数：包含两部分
  // 1. user_study_progress 中到期的词（state=1）
  // 2. 今日会话队列中未完成的复习任务
  final remainingReview = widget.progress.todayReviewCount;
  // ...
}
```

**学习会话头部**:

```dart
Widget _buildHeader(BuildContext context) {
  final session = _session;
  // 队列统计：显示当前会话队列中的新词和复习词数量
  // 注意：这是动态数据，会随着"不认识"操作而增加复习词数量
  final newWordsCount = session?.newWordsCount ?? 0;
  final reviewWordsCount = session?.reviewWordsCount ?? 0;
  final totalCount = session?.queue.length ?? 0;
  // ...
}
```

---

## 数据流图

```
┌─────────────────────────────────────────────────────────────┐
│                      数据统一来源                              │
│                   user_study_progress 表                      │
│                                                               │
│  - word_id: 单词ID                                            │
│  - dict_name: 词典名称                                        │
│  - state: 学习状态 (0:新词 1:学习中 2:已掌握)                  │
│  - next_review_date: 下次复习日期                             │
│  - last_modified: 最后修改时间                                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────┐
        │      getDictProgress 方法            │
        │   (统一计算所有统计数据)              │
        └─────────────────────────────────────┘
                              │
                ┌─────────────┼─────────────┐
                ▼             ▼             ▼
        ┌──────────┐  ┌──────────┐  ┌──────────┐
        │ 总词数    │  │ 已学数    │  │ 今日新词  │
        │          │  │          │  │          │
        │ totalCount│  │learnedCount│ │todayNewCount│
        └──────────┘  └──────────┘  └──────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │  待复习数         │
                    │ todayReviewCount │
                    │                  │
                    │ 来源1: 到期的词   │
                    │ 来源2: 队列中的词 │
                    └──────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────┐
        │         UI 显示层                    │
        │                                     │
        │  - 学习统计页面 (_StudyStatsPage)    │
        │  - 今日任务卡片 (_buildTodayTaskCard)│
        │  - 学习会话头部 (_buildHeader)        │
        └─────────────────────────────────────┘
```

---

## 交互流程

### 场景 1: 新词点击"不认识"

```
用户学习新词 "apple"
    │
    ▼
点击"不认识"按钮 (FamiliarityLevel.unfamiliar)
    │
    ▼
_handleFamiliarity 方法处理
    │
    ├─ 1. 更新 user_study_progress 表
    │     - state: 0 → 1 (新词 → 学习中)
    │     - interval: 1 (明天复习)
    │     - next_review_date: 明天
    │
    ├─ 2. 标记当前队列位置为已完成
    │     - study_session_queue.is_done = 1
    │
    ├─ 3. 创建复习副本加入队列末尾
    │     - WordProgress(isReview: true)
    │     - 添加到 study_session_queue 表
    │
    └─ 4. 自动跳转到下一个单词
```

### 场景 2: 进入学习页面

```
用户点击"开始背诵"
    │
    ▼
getOrCreateTodaySession 方法
    │
    ├─ 检查今日会话是否存在
    │
    ├─ 如果存在：
    │   │
    │   ├─ A. 动态追加待复习单词
    │   │     - 从 user_study_progress 获取到期的词
    │   │     - 排除已在队列中的词
    │   │     - 添加到队列末尾
    │   │
    │   ├─ B. 动态补全新词
    │   │     - 检查新词数量是否达标
    │   │     - 补充到每日目标数量
    │   │
    │   └─ C. 重新校准索引
    │         - 指向第一个未完成的单词
    │
    └─ 如果不存在：
        │
        └─ 创建新会话
              - 调用 getTodayStudyQueue 生成队列
              - 穿插新词和复习词 (2:1 比例)
```

---

## 测试建议

### 1. 测试"不认识"功能

```
步骤：
1. 开始学习，遇到新词
2. 点击"不认识"
3. 继续学习，观察队列末尾是否出现该词
4. 学习到队列末尾，确认该词显示为"复习单词"

预期结果：
- 单词立即加入队列末尾
- 显示"复习单词"标签
- 可以正常学习和评分
```

### 2. 测试待复习单词处理

```
步骤：
1. 使用 debugReduceReviewDate 方法提前复习日期
2. 退出并重新进入学习页面
3. 观察待复习数量是否正确
4. 开始学习，确认复习词在队列中

预期结果：
- 统计页面显示正确的待复习数量
- 学习队列包含所有到期的复习词
- 复习词显示"复习巩固"标签
```

### 3. 测试数据同源对齐

```
步骤：
1. 在统计页面查看"今日新词"和"待复习"数量
2. 进入学习会话
3. 对比会话头部显示的"新词"和"复习"数量
4. 学习几个单词后返回统计页面
5. 刷新数据，确认数量变化一致

预期结果：
- 统计页面和学习页面数据来源一致
- 数量变化实时同步
- 不会出现数据不一致的情况
```

---

## 调试日志

优化后的代码包含详细的调试日志，便于追踪问题：

```dart
// getDictProgress 方法
print('DEBUG getDictProgress: 词典=$dictName, 总词数=$totalCount, 已学=$learnedCount, 今日新词=$todayNewCount, 待复习=$reviewCount');

// getOrCreateTodaySession 方法
print('DEBUG getOrCreateTodaySession: 恢复会话 $sessionId, 当前队列长度: ${queue.length}');
print('DEBUG: 动态追加了 $addedReviewCount 个待复习单词');
print('DEBUG: 动态补充了 $addedNewCount 个新词');
print('DEBUG: 会话已刷新 - 队列总数: ${queue.length}, 当前索引: $currentIndex, 新词: ${newCount}, 复习: ${reviewCount}');

// _handleFamiliarity 方法
print('DEBUG: 单词 "${currentWordProgress.word}" 点击不认识，已加入队列末尾 (isNewWord: $isNewWord)');
```

---

## 总结

本次优化完成了以下目标：

1. ✅ **"不认识"立即加入队列**: 新词和复习词点击"不认识"后，立即作为复习单词加入队列末尾
2. ✅ **待复习单词处理准确**: 每次进入学习页面时，动态追加所有到期的复习词
3. ✅ **数据统计同源对齐**: 所有统计数据来自 `getDictProgress` 方法，确保一致性

**核心改进**:

- 简化了数据统计逻辑，移除冗余计算
- 增强了待复习单词的动态追加机制
- 优化了代码注释和调试日志
- 确保了 UI 显示与数据源的一致性

**代码质量**:

- 无编译错误
- 无类型错误
- 逻辑清晰，易于维护
