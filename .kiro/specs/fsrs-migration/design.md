# Design Document: FSRS Migration

## Overview

本设计文档描述了将 AI Vocab 应用的记忆算法从 SM-2 迁移到 FSRS 2.0 的技术方案。FSRS（Free Spaced Repetition Scheduler）是一种基于机器学习的现代间隔重复算法，相比 SM-2 具有更精准的记忆预测能力。

### 核心变更

1. **算法层**：从自实现的 SM-2 切换到 `fsrs` Dart 包
2. **数据层**：数据库表结构迁移，支持 FSRS 卡片状态
3. **UI 层**：评分按钮映射到 FSRS Rating，显示预测复习间隔

### 设计原则

- **最小侵入**：保持现有 UI 交互不变，仅替换底层算法
- **数据安全**：迁移前备份，失败可回滚
- **渐进迁移**：支持新旧数据共存，逐步迁移

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        UI Layer                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ StudyPage   │  │ StatsPage   │  │ RatingButtons       │  │
│  │ (unchanged) │  │ (unchanged) │  │ (interval preview)  │  │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘  │
└─────────┼────────────────┼───────────────────┼──────────────┘
          │                │                   │
┌─────────▼────────────────▼───────────────────▼──────────────┐
│                     Service Layer                            │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              FSRSService (NEW)                       │    │
│  │  - scheduler: FSRS                                   │    │
│  │  - reviewCard(card, rating) -> SchedulingInfo        │    │
│  │  - previewIntervals(card) -> Map<Rating, Duration>   │    │
│  │  - formatInterval(duration) -> String                │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
          │
┌─────────▼───────────────────────────────────────────────────┐
│                      Data Layer                              │
│  ┌─────────────────┐  ┌─────────────────────────────────┐   │
│  │   WordCard      │  │        DBHelper                  │   │
│  │   (NEW model)   │  │  - FSRS card CRUD                │   │
│  │                 │  │  - Migration service             │   │
│  │  - wordId       │  │  - ReviewLog storage             │   │
│  │  - word         │  │  - Session queue (unchanged)     │   │
│  │  - dictName     │  └─────────────────────────────────┘   │
│  │  - card: Card   │                                        │
│  └─────────────────┘                                        │
└─────────────────────────────────────────────────────────────┘
          │
┌─────────▼───────────────────────────────────────────────────┐
│                    Database Layer                            │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  user_study_progress (MODIFIED)                      │    │
│  │  + due, stability, difficulty, elapsed_days,         │    │
│  │    scheduled_days, reps, lapses, state, last_review  │    │
│  ├─────────────────────────────────────────────────────┤    │
│  │  review_logs (NEW)                                   │    │
│  │  - word_id, dict_name, rating, state, due,           │    │
│  │    stability, difficulty, elapsed_days,              │    │
│  │    scheduled_days, review_datetime                   │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## Components and Interfaces

### 1. FSRSService

新增的服务类，封装 FSRS 调度器的所有操作。

```dart
/// FSRS 服务 - 封装间隔重复调度逻辑
class FSRSService {
  late final FSRS _scheduler;

  FSRSService() {
    _scheduler = FSRS(
      parameters: Parameters(
        requestRetention: 0.9,  // 90% 目标保留率
        maximumInterval: 36500, // 100 年最大间隔
      ),
    );
  }

  /// 复习卡片并返回调度结果
  SchedulingInfo reviewCard(Card card, Rating rating, DateTime now) {
    final result = _scheduler.repeat(card, now);
    return result[rating]!;
  }

  /// 预览所有评分选项的下次复习间隔
  Map<Rating, Duration> previewIntervals(Card card, DateTime now) {
    final result = _scheduler.repeat(card, now);
    return {
      Rating.again: result[Rating.again]!.card.due.difference(now),
      Rating.hard: result[Rating.hard]!.card.due.difference(now),
      Rating.good: result[Rating.good]!.card.due.difference(now),
      Rating.easy: result[Rating.easy]!.card.due.difference(now),
    };
  }

  /// 格式化间隔为可读字符串
  String formatInterval(Duration duration) {
    final minutes = duration.inMinutes;
    if (minutes < 60) return '$minutes 分钟';
    if (minutes < 1440) return '${duration.inHours} 小时';

    final days = duration.inDays;
    if (days < 30) return '$days 天';
    if (days < 365) return '${(days / 30).round()} 月';
    return '${(days / 365).round()} 年';
  }
}
```

### 2. WordCard Model

新的单词卡片模型，包装 FSRS Card 对象。

```dart
/// FSRS 单词卡片模型
class WordCard {
  final int wordId;
  final String word;
  final String dictName;
  Card card;  // FSRS Card 对象

  WordCard({
    required this.wordId,
    required this.word,
    required this.dictName,
    Card? card,
  }) : card = card ?? Card();

  /// 是否到期需要复习
  bool get isDue => card.due.isBefore(DateTime.now()) ||
                    card.due.isAtSameMomentAs(DateTime.now());

  /// 是否是复习卡片（非新卡）
  bool get isReview => card.state != State.newState;

  /// 从数据库 Map 创建
  factory WordCard.fromMap(Map<String, dynamic> map) {
    return WordCard(
      wordId: map['word_id'] as int,
      word: map['word'] as String? ?? '',
      dictName: map['dict_name'] as String? ?? '',
      card: Card(
        due: DateTime.parse(map['due'] as String),
        stability: (map['stability'] as num).toDouble(),
        difficulty: (map['difficulty'] as num).toDouble(),
        elapsedDays: map['elapsed_days'] as int,
        scheduledDays: map['scheduled_days'] as int,
        reps: map['reps'] as int,
        lapses: map['lapses'] as int,
        state: State.values[map['state'] as int],
        lastReview: map['last_review'] != null
            ? DateTime.parse(map['last_review'] as String)
            : null,
      ),
    );
  }

  /// 转换为数据库 Map
  Map<String, dynamic> toMap() {
    return {
      'word_id': wordId,
      'dict_name': dictName,
      'due': card.due.toIso8601String(),
      'stability': card.stability,
      'difficulty': card.difficulty,
      'elapsed_days': card.elapsedDays,
      'scheduled_days': card.scheduledDays,
      'reps': card.reps,
      'lapses': card.lapses,
      'state': card.state.index,
      'last_review': card.lastReview?.toIso8601String(),
    };
  }
}
```

### 3. Rating Mapping

评分按钮到 FSRS Rating 的映射：

| UI 按钮 | 原 SM-2 Quality | FSRS Rating  | 说明                   |
| ------- | --------------- | ------------ | ---------------------- |
| 太简单  | 5               | Rating.easy  | 轻松记住，大幅延长间隔 |
| 有困难  | 3               | Rating.good  | 正常记住，标准间隔增长 |
| 不认识  | 1               | Rating.again | 忘记了，重新学习       |

注意：FSRS 有 4 个评分等级（Again, Hard, Good, Easy），我们简化为 3 个以保持 UI 一致性。

### 4. DBHelper 扩展

```dart
// 新增方法
class DBHelper {
  // ... 现有方法 ...

  /// 获取 FSRS 卡片
  Future<WordCard?> getWordCard(int wordId, String dictName);

  /// 保存 FSRS 卡片
  Future<void> saveWordCard(WordCard card);

  /// 获取待复习的 FSRS 卡片
  Future<List<WordCard>> getDueCards(String dictName, {int limit = 100});

  /// 记录复习日志
  Future<void> logReview(ReviewLog log);

  /// 迁移 SM-2 数据到 FSRS
  Future<void> migrateToFSRS();

  /// 备份数据库
  Future<String> backupDatabase();
}
```

## Data Models

### 数据库表结构变更

#### user_study_progress 表（修改）

```sql
-- 新增 FSRS 字段，保留旧字段用于迁移
ALTER TABLE user_study_progress ADD COLUMN due TEXT;
ALTER TABLE user_study_progress ADD COLUMN stability REAL DEFAULT 0;
ALTER TABLE user_study_progress ADD COLUMN difficulty REAL DEFAULT 0;
ALTER TABLE user_study_progress ADD COLUMN elapsed_days INTEGER DEFAULT 0;
ALTER TABLE user_study_progress ADD COLUMN scheduled_days INTEGER DEFAULT 0;
ALTER TABLE user_study_progress ADD COLUMN reps INTEGER DEFAULT 0;
ALTER TABLE user_study_progress ADD COLUMN lapses INTEGER DEFAULT 0;
ALTER TABLE user_study_progress ADD COLUMN last_review TEXT;

-- 注意：state 字段含义变更
-- 旧: 0=newWord, 1=learning, 2=mastered
-- 新: 0=New, 1=Learning, 2=Review, 3=Relearning
```

#### review_logs 表（新增）

```sql
CREATE TABLE IF NOT EXISTS review_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  word_id INTEGER NOT NULL,
  dict_name TEXT NOT NULL,
  rating INTEGER NOT NULL,
  state INTEGER NOT NULL,
  due TEXT NOT NULL,
  stability REAL NOT NULL,
  difficulty REAL NOT NULL,
  elapsed_days INTEGER NOT NULL,
  scheduled_days INTEGER NOT NULL,
  review_datetime TEXT NOT NULL,
  FOREIGN KEY (word_id) REFERENCES words(id)
);

CREATE INDEX idx_review_logs_word ON review_logs(word_id, dict_name);
CREATE INDEX idx_review_logs_datetime ON review_logs(review_datetime);
```

### 数据迁移策略

SM-2 到 FSRS 的字段映射：

| SM-2 字段          | FSRS 字段      | 转换规则                            |
| ------------------ | -------------- | ----------------------------------- |
| interval           | stability      | `stability = interval * 0.9` (估算) |
| ease_factor        | difficulty     | `difficulty = 5.0` (固定中等难度)   |
| repetition         | reps           | 直接复制                            |
| next_review_date   | due            | 直接复制                            |
| state (0=new)      | state          | 0 -> State.newState                 |
| state (1=learning) | state          | 1 -> State.review                   |
| state (2=mastered) | state          | 2 -> State.review                   |
| -                  | lapses         | 0 (无历史数据)                      |
| -                  | elapsed_days   | 0 (无历史数据)                      |
| -                  | scheduled_days | interval                            |
| last_modified      | last_review    | 直接复制                            |

## Correctness Properties

_A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees._

### Property 1: WordCard Serialization Round-Trip

_For any_ valid WordCard object, serializing it to a Map using `toMap()` and then deserializing using `WordCard.fromMap()` SHALL produce an equivalent WordCard with identical wordId, word, dictName, and all Card properties (due, stability, difficulty, elapsedDays, scheduledDays, reps, lapses, state, lastReview).

**Validates: Requirements 3.2**

### Property 2: Migration Correctness

_For any_ valid SM-2 progress record with interval I, repetition R, and state S:

- The migrated FSRS card SHALL have stability approximately equal to `I * 0.9`
- The migrated FSRS card SHALL have difficulty equal to 5.0
- The migrated FSRS card SHALL have reps equal to R
- If S >= 1, the migrated FSRS card SHALL have state = State.review
- If S == 0, the word SHALL remain without an FSRS record (new card)

**Validates: Requirements 2.2, 2.3, 8.1, 8.2, 8.3, 8.4, 8.6**

### Property 3: Interval Formatting Correctness

_For any_ Duration d:

- If d.inMinutes < 60, formatInterval(d) SHALL return a string containing "分钟"
- If 60 <= d.inMinutes < 1440, formatInterval(d) SHALL return a string containing "小时"
- If 1 <= d.inDays < 30, formatInterval(d) SHALL return a string containing "天"
- If 30 <= d.inDays < 365, formatInterval(d) SHALL return a string containing "月"
- If d.inDays >= 365, formatInterval(d) SHALL return a string containing "年"

**Validates: Requirements 5.3, 5.4, 5.5**

### Property 4: Due Cards Query Correctness

_For any_ set of WordCards in the database and current time T:

- `getDueCards()` SHALL return exactly those cards where `card.due <= T`
- The returned cards SHALL be ordered by due date ascending (oldest first)
- The count of returned cards SHALL equal the "待复习" statistic

**Validates: Requirements 6.1, 6.2, 6.3**

### Property 5: Statistics Calculation Correctness

_For any_ set of WordCards in the database:

- "已学习" count SHALL equal cards where `state != State.newState OR reps > 0`
- "今日新词" count SHALL equal cards where first review date equals today
- "待复习" count SHALL equal cards where `due <= now AND state in (Review, Relearning)`

**Validates: Requirements 7.1, 7.2, 7.3**

### Property 6: ReviewLog Completeness

_For any_ card review action with rating R:

- A ReviewLog entry SHALL be created
- The ReviewLog SHALL contain all required fields: word_id, dict_name, rating (= R), state, due, stability, difficulty, elapsed_days, scheduled_days, review_datetime
- All numeric fields SHALL be non-negative
- review_datetime SHALL be within 1 second of the actual review time

**Validates: Requirements 9.1, 9.2**

### Property 7: Session Queue Management

_For any_ study session:

- The queue SHALL contain valid WordCard objects
- When a session is resumed, all cards' isDue status SHALL reflect current time
- Adding a card to the queue SHALL increase queue length by exactly 1
- After reviewing a card, its is_done flag SHALL be true
- When all cards have is_done = true, the session SHALL be marked complete

**Validates: Requirements 10.1, 10.2, 10.3, 10.4, 10.5**

### Property 8: Preview Interval Immutability

_For any_ WordCard and DateTime:

- Calling `previewIntervals(card, now)` SHALL NOT modify the original card's properties
- The card's due, stability, difficulty, reps, lapses, and state SHALL remain unchanged after preview

**Validates: Requirements 5.2**

## Error Handling

### 数据库迁移错误

```dart
Future<void> migrateToFSRS() async {
  // 1. 备份数据库
  final backupPath = await backupDatabase();

  try {
    // 2. 开始事务
    await db.transaction((txn) async {
      // 3. 添加新列
      await _addFSRSColumns(txn);

      // 4. 迁移数据
      await _migrateProgressData(txn);

      // 5. 创建 review_logs 表
      await _createReviewLogsTable(txn);
    });
  } catch (e) {
    // 6. 回滚：恢复备份
    await _restoreFromBackup(backupPath);
    rethrow;
  }
}
```

### FSRS 计算错误

```dart
SchedulingInfo reviewCard(Card card, Rating rating, DateTime now) {
  try {
    final result = _scheduler.repeat(card, now);
    return result[rating]!;
  } catch (e) {
    // 降级处理：返回默认间隔
    return SchedulingInfo(
      card: card.copyWith(
        due: now.add(Duration(days: 1)),
      ),
      reviewLog: ReviewLog(...),
    );
  }
}
```

### 数据一致性检查

```dart
Future<void> validateCardData(WordCard card) async {
  assert(card.card.stability >= 0, 'Stability must be non-negative');
  assert(card.card.difficulty >= 1 && card.card.difficulty <= 10,
         'Difficulty must be between 1 and 10');
  assert(card.card.reps >= 0, 'Reps must be non-negative');
  assert(card.card.lapses >= 0, 'Lapses must be non-negative');
}
```

## Testing Strategy

### 测试框架

- **单元测试**: `flutter_test`
- **属性测试**: `glados` (Dart property-based testing library)

### 单元测试

1. **FSRSService 测试**

   - 初始化配置验证
   - 各评分等级的间隔计算
   - 间隔格式化边界值

2. **WordCard 测试**

   - 序列化/反序列化
   - isDue 和 isReview 属性
   - 新卡片默认值

3. **数据库迁移测试**

   - SM-2 数据转换
   - 回滚机制
   - 表结构验证

4. **集成测试**
   - 完整学习流程
   - 会话恢复
   - 统计数据一致性

### 属性测试

使用 `glados` 库实现属性测试，每个属性测试运行至少 100 次迭代。

```dart
// 示例：WordCard 序列化往返测试
Glados<WordCard>(any.wordCard).test(
  'WordCard serialization round-trip',
  (card) {
    final map = card.toMap();
    final restored = WordCard.fromMap(map);
    expect(restored.wordId, equals(card.wordId));
    expect(restored.word, equals(card.word));
    expect(restored.card.stability, equals(card.card.stability));
    // ... 验证所有字段
  },
);
```

### 测试覆盖要求

- 核心算法逻辑：100% 覆盖
- 数据迁移路径：100% 覆盖
- UI 交互：关键路径覆盖
- 错误处理：所有异常分支覆盖
