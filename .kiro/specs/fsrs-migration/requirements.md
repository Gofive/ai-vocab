# Requirements Document

## Introduction

本文档定义了将 AI Vocab 应用的记忆算法从 SM-2 迁移到 FSRS 2.0 的需求规范。FSRS（Free Spaced Repetition Scheduler）是一种更现代、更精准的间隔重复算法，能够根据用户的学习历史动态调整复习间隔，提供更好的记忆效果。

## Glossary

- **FSRS**: Free Spaced Repetition Scheduler，自由间隔重复调度算法
- **SM-2**: SuperMemo 2 算法，传统的间隔重复算法
- **Stability**: 记忆稳定性，表示遗忘速率，值越大遗忘越慢
- **Difficulty**: 单词难度，范围 1-10
- **Retrievability**: 记忆保留率，当前能回忆起该单词的概率
- **Rating**: 用户评分，1=Again, 2=Hard, 3=Good, 4=Easy
- **State**: 卡片状态，Learning/Review/Relearning
- **Due**: 下次复习到期时间
- **Scheduler**: FSRS 调度器，负责计算下次复习时间
- **Card**: FSRS 卡片对象，存储单词的记忆状态
- **ReviewLog**: 复习日志，记录每次复习的详细信息

## Requirements

### Requirement 1: 集成 FSRS 包

**User Story:** As a developer, I want to integrate the FSRS Dart package, so that I can use the FSRS algorithm for spaced repetition scheduling.

#### Acceptance Criteria

1. WHEN the application starts, THE System SHALL initialize the FSRS Scheduler with default parameters
2. THE System SHALL use fsrs package version 2.0.1 or higher from pub.dev
3. THE Scheduler SHALL be configured with desiredRetention of 0.9 (90% target retention rate)
4. THE Scheduler SHALL support learningSteps of [1 minute, 10 minutes]
5. THE Scheduler SHALL support relearningSteps of [10 minutes]
6. THE Scheduler SHALL have maximumInterval set to 36500 days (100 years)

### Requirement 2: 数据库结构迁移

**User Story:** As a developer, I want to migrate the database schema from SM-2 to FSRS format, so that the application can store FSRS-specific card data.

#### Acceptance Criteria

1. THE Database SHALL create a new table structure for FSRS card data with fields: word_id, dict_name, due, stability, difficulty, elapsed_days, scheduled_days, reps, lapses, state, last_review
2. WHEN the application detects old SM-2 data, THE Migration_Service SHALL convert existing progress to FSRS format
3. THE Migration_Service SHALL preserve the user's learning history during migration
4. IF migration fails, THEN THE System SHALL rollback changes and preserve original data
5. THE System SHALL create a review_logs table to store review history for future parameter optimization

### Requirement 3: 单词卡片模型重构

**User Story:** As a developer, I want to refactor the WordProgress model to use FSRS Card, so that the application uses FSRS data structures.

#### Acceptance Criteria

1. THE WordCard model SHALL wrap the FSRS Card object with word metadata (wordId, word, dictName)
2. THE WordCard model SHALL provide serialization methods (toMap, fromMap) for database storage
3. THE WordCard model SHALL expose isDue property to check if the card needs review
4. THE WordCard model SHALL expose isReview property to distinguish new words from review words
5. WHEN a WordCard is created for a new word, THE System SHALL initialize it with FSRS default values

### Requirement 4: 评分系统重构

**User Story:** As a user, I want to rate my recall of words using a simplified rating system, so that the algorithm can accurately schedule my reviews.

#### Acceptance Criteria

1. THE UI SHALL display three rating buttons: "记住了" (Easy), "有印象" (Good), "没记住" (Again)
2. WHEN user clicks "记住了", THE System SHALL call scheduler.reviewCard with Rating.easy
3. WHEN user clicks "有印象", THE System SHALL call scheduler.reviewCard with Rating.good
4. WHEN user clicks "没记住", THE System SHALL call scheduler.reviewCard with Rating.again
5. THE System SHALL display the predicted next review interval for each rating option
6. WHEN user rates a card as "没记住" (Again), THE System SHALL add the card to the end of today's queue as a review card

### Requirement 5: 复习间隔预览

**User Story:** As a user, I want to see the predicted next review time for each rating option, so that I can make informed decisions about my recall.

#### Acceptance Criteria

1. THE UI SHALL show the next review interval below each rating button
2. THE Scheduler SHALL calculate preview intervals using scheduler.reviewCard without persisting
3. THE System SHALL format intervals as "X 分钟", "X 天", "X 月", or "X 年" based on duration
4. WHEN interval is less than 1 day, THE System SHALL display in minutes or hours
5. WHEN interval is 1 day or more, THE System SHALL display in days, months, or years

### Requirement 6: 待复习单词查询

**User Story:** As a user, I want to see all words that are due for review, so that I can complete my daily review tasks.

#### Acceptance Criteria

1. THE Database_Helper SHALL query words where due <= current_time
2. THE System SHALL order review words by due date (oldest first)
3. THE System SHALL accurately count pending review words for display on the study page
4. WHEN entering the study page, THE System SHALL dynamically add any newly due words to the session queue

### Requirement 7: 学习进度统计

**User Story:** As a user, I want to see accurate statistics about my learning progress, so that I can track my vocabulary growth.

#### Acceptance Criteria

1. THE System SHALL count "已学习" as words with state != Learning OR reps > 0
2. THE System SHALL count "今日新词" as words first reviewed today
3. THE System SHALL count "待复习" as words where due <= now AND state in (Review, Relearning)
4. THE Statistics SHALL be calculated from the same data source as the study session

### Requirement 8: 数据迁移策略

**User Story:** As a user with existing learning progress, I want my progress to be preserved when upgrading to FSRS, so that I don't lose my learning history.

#### Acceptance Criteria

1. WHEN migrating from SM-2, THE System SHALL estimate FSRS stability from the old interval value
2. WHEN migrating from SM-2, THE System SHALL set difficulty to 5.0 (medium) for all existing words
3. WHEN migrating from SM-2, THE System SHALL preserve the repetition count as reps
4. WHEN migrating from SM-2, THE System SHALL set state to Review for words with old state >= 1
5. THE System SHALL backup the database before migration
6. IF the user has never studied a word, THE System SHALL keep it as a new card

### Requirement 9: 复习日志记录

**User Story:** As a developer, I want to log all review actions, so that FSRS parameters can be optimized in the future.

#### Acceptance Criteria

1. WHEN a card is reviewed, THE System SHALL create a ReviewLog entry
2. THE ReviewLog SHALL contain: word_id, dict_name, rating, state, due, stability, difficulty, elapsed_days, scheduled_days, review_datetime
3. THE System SHALL store ReviewLogs in a separate database table
4. THE ReviewLog data SHALL be exportable for parameter optimization

### Requirement 10: 学习会话兼容

**User Story:** As a user, I want the study session to work seamlessly with FSRS, so that my learning experience remains smooth.

#### Acceptance Criteria

1. THE Study_Session SHALL continue to support queue-based learning with FSRS cards
2. WHEN a session is resumed, THE System SHALL recalculate due status for all queued cards
3. THE System SHALL support adding cards to the queue dynamically during a session
4. THE System SHALL mark cards as done in the session queue after review
5. WHEN all cards in the queue are done, THE System SHALL complete the session
