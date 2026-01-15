# Implementation Plan: FSRS Migration

## Overview

本实现计划将 AI Vocab 应用的记忆算法从 SM-2 迁移到 FSRS 2.0。采用渐进式迁移策略，确保数据安全和功能稳定。

## Tasks

- [x] 1. 添加 FSRS 依赖和创建服务层

  - [x] 1.1 添加 fsrs 和 glados 依赖到 pubspec.yaml

    - 添加 `fsrs: ^2.0.1` 到 dependencies
    - 添加 `glados: ^1.1.1` 到 dev_dependencies（属性测试）
    - 运行 `flutter pub get`
    - _Requirements: 1.2_

  - [x] 1.2 创建 FSRSService 服务类

    - 创建 `lib/services/fsrs_service.dart`
    - 实现 FSRS 调度器初始化（desiredRetention=0.9, maximumInterval=36500）
    - 实现 `reviewCard(card, rating, now)` 方法
    - 实现 `previewIntervals(card, now)` 方法
    - 实现 `formatInterval(duration)` 方法
    - _Requirements: 1.1, 1.3, 1.4, 1.5, 1.6, 5.2, 5.3_

  - [ ]\* 1.3 编写 FSRSService 单元测试
    - 测试调度器初始化配置
    - 测试各评分等级的间隔计算
    - 测试间隔格式化边界值
    - _Requirements: 1.1, 5.3_

- [x] 2. 创建 WordCard 数据模型

  - [x] 2.1 创建 WordCard 模型类

    - 创建 `lib/models/word_card.dart`
    - 实现 WordCard 类，包装 FSRS Card 对象
    - 实现 `isDue` 和 `isReview` 属性
    - 实现 `toMap()` 和 `fromMap()` 序列化方法
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

  - [ ]\* 2.2 编写 WordCard 属性测试
    - **Property 1: WordCard Serialization Round-Trip**
    - **Validates: Requirements 3.2**

- [ ] 3. Checkpoint - 确保基础组件测试通过

  - 确保所有测试通过，如有问题请询问用户

- [x] 4. 数据库结构迁移

  - [x] 4.1 修改 DBHelper 添加 FSRS 表结构

    - 在 `_ensureProgressTable` 中添加 FSRS 字段到 user_study_progress 表
    - 创建 review_logs 表
    - 实现表结构版本检测和升级逻辑
    - _Requirements: 2.1, 2.5, 9.3_

  - [x] 4.2 实现数据迁移服务

    - 实现 `backupDatabase()` 方法
    - 实现 `migrateToFSRS()` 方法
    - 实现 SM-2 到 FSRS 的数据转换逻辑
    - 实现迁移失败回滚机制
    - _Requirements: 2.2, 2.3, 2.4, 8.1, 8.2, 8.3, 8.4, 8.5, 8.6_

  - [ ]\* 4.3 编写数据迁移属性测试
    - **Property 2: Migration Correctness**
    - **Validates: Requirements 2.2, 2.3, 8.1, 8.2, 8.3, 8.4, 8.6**

- [x] 5. 实现 FSRS 卡片 CRUD 操作

  - [x] 5.1 实现 WordCard 数据库操作

    - 实现 `getWordCard(wordId, dictName)` 方法
    - 实现 `saveWordCard(card)` 方法
    - 实现 `getDueCards(dictName, limit)` 方法
    - 修改现有查询方法支持 FSRS 字段
    - _Requirements: 6.1, 6.2_

  - [x] 5.2 实现复习日志记录

    - 实现 `logReview(ReviewLog)` 方法
    - 实现 ReviewLog 数据模型
    - _Requirements: 9.1, 9.2, 9.4_

  - [ ]\* 5.3 编写 FSRS 查询属性测试

    - **Property 4: Due Cards Query Correctness**
    - **Validates: Requirements 6.1, 6.2, 6.3**

  - [ ]\* 5.4 编写 ReviewLog 属性测试
    - **Property 6: ReviewLog Completeness**
    - **Validates: Requirements 9.1, 9.2**

- [ ] 6. Checkpoint - 确保数据层测试通过

  - 确保所有测试通过，如有问题请询问用户

- [x] 7. 重构学习统计计算

  - [x] 7.1 修改 getDictProgress 方法

    - 更新 "已学习" 统计逻辑（state != New OR reps > 0）
    - 更新 "今日新词" 统计逻辑（首次复习日期 = 今天）
    - 更新 "待复习" 统计逻辑（due <= now AND state in Review/Relearning）
    - _Requirements: 7.1, 7.2, 7.3, 7.4_

  - [ ]\* 7.2 编写统计计算属性测试
    - **Property 5: Statistics Calculation Correctness**
    - **Validates: Requirements 7.1, 7.2, 7.3**

- [x] 8. 重构学习会话管理

  - [x] 8.1 修改会话队列支持 FSRS

    - 修改 `getOrCreateTodaySession` 使用 WordCard
    - 修改 `_getSessionQueue` 返回 WordCard 列表
    - 修改 `getTodayStudyQueue` 使用 FSRS 查询
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_

  - [ ]\* 8.2 编写会话管理属性测试
    - **Property 7: Session Queue Management**
    - **Validates: Requirements 10.1, 10.2, 10.3, 10.4, 10.5**

- [x] 9. 重构 UI 评分逻辑

  - [x] 9.1 修改 StudyPage 评分处理

    - 修改 `_handleFamiliarity` 使用 FSRSService
    - 映射 FamiliarityLevel 到 FSRS Rating
    - 调用 `fsrsService.reviewCard()` 更新卡片
    - 保存更新后的 WordCard 到数据库
    - 记录 ReviewLog
    - _Requirements: 4.2, 4.3, 4.4, 4.6_

  - [x] 9.2 实现复习间隔预览显示

    - 在评分按钮下方显示预测间隔
    - 调用 `fsrsService.previewIntervals()` 获取预览
    - 使用 `fsrsService.formatInterval()` 格式化显示
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_

  - [ ]\* 9.3 编写间隔格式化属性测试

    - **Property 3: Interval Formatting Correctness**
    - **Validates: Requirements 5.3, 5.4, 5.5**

  - [ ]\* 9.4 编写预览不可变性属性测试
    - **Property 8: Preview Interval Immutability**
    - **Validates: Requirements 5.2**

- [x] 10. 集成和清理

  - [x] 10.1 更新应用初始化流程

    - 在应用启动时检测是否需要迁移
    - 显示迁移进度提示
    - 处理迁移失败情况
    - _Requirements: 1.1, 2.4_

  - [x] 10.2 清理废弃代码
    - 标记 WordProgress 类为 @Deprecated
    - 更新所有引用使用 WordCard
    - 移除未使用的 SM-2 相关方法
    - _Requirements: 3.1_

- [ ] 11. Final Checkpoint - 确保所有测试通过
  - 运行完整测试套件
  - 验证迁移流程
  - 确保所有测试通过，如有问题请询问用户

## Notes

- 任务标记 `*` 的为可选测试任务，可跳过以加快 MVP 开发
- 每个属性测试引用设计文档中的正确性属性
- Checkpoint 任务用于增量验证
- 迁移过程中保留旧数据结构，确保可回滚
