这份产品与算法文档已经进入了**工程化落地阶段**。为了满足你对“离线优先、云端同步”的要求，我们将重点放在 **数据流转架构** 和 **进度同步逻辑** 上。

---

## 英语学习应用：核心逻辑与同步算法文档 (v2.0)

### 一、 业务架构：多字典初始化流 (Init Workflow)

用户选择词典后，客户端需完成从“云端 JSON”到“本地关系型数据库”的转化，以保证查询效率。

#### 1. 初始化流程 (Initialization)

1. **词典元数据拉取**：客户端请求服务器，获取词典列表及其对应的 `version`（版本号）和 `download_url`（OSS 地址）。
2. **数据包下载**：客户端下载经过 Qwen-30b 增强后的 `Vocab_30b_Enhanced.json`。
3. **本地持久化 (Flutter/SQLite)**：

- **字典表 (`dictionaries`)**：插入词典 ID 和名称。
- **单词表 (`words`)**：批量插入单词、音标、助记、以及作为 `TEXT` 存储的 `usage_stacks` (JSON 字符串)。
- **映射表 (`word_dict_mapping`)**：建立单词与该词典的关联。

4. **状态标记**：设置本地 `is_initialized = true`。

---

### 二、 用户数据同步逻辑：OSS-JSON 方案

为了降低服务端压力并保证用户数据安全，我们采用 **“增量更新 + OSS 快照”** 方案。

#### 1. 服务端用户表结构

服务端只需维护一个轻量级的 JSON 字段（或关联表）：

```json
{
  "user_id": "1001",
  "sync_files": {
    "CET4": "https://oss-bucket.com/users/1001/CET4_v20240315.json",
    "CET6": "https://oss-bucket.com/users/1001/CET6_v20240315.json"
  }
}
```

#### 2. 进度文件格式 (Progress JSON)

保存在 OSS 上的 `.json` 文件记录了该用户在这本词典下的所有“动态数据”：

```json
{
  "dict_name": "CET4",
  "last_sync_time": "2026-01-11T23:00:00",
  "progress_data": [
    {
      "w": "cancel", // 单词
      "ef": 2.5, // Ease Factor (SM-2 算法参数)
      "iv": 4, // Interval (复习间隔天数)
      "nd": "2026-01-15", // Next Date (下次复习日期)
      "s": 2 // State (0:新词, 1:学习中, 2:已掌握)
    }
  ]
}
```

---

### 三、 算法文档：记忆复习与调度

#### 1. 记忆调度算法 (Modified SM-2)

复习逻辑基于用户的反馈（Quality: 0-5 分）。

- **新间隔 (I)** 计算公式：
- 如果 (记不住)： 天。
- 如果 (记得)：。

- **简单系数 (EF)** 动态调整：

_注：EF 最小不低于 1.3，防止复习间隔过长。_

#### 2. 学习/复习队列划分

客户端根据数据库字段将单词分为三个逻辑池：

- **待学池 (New)**：`word_id` 在 `word_dict_mapping` 中但不在 `user_progress` 中。
- **复习池 (Review)**：`next_review <= CURRENT_DATE`。
- **待巩固池 (Lapses)**：刚才复习错过的单词（存放在内存队列，10 分钟后重现）。

---

### 四、 客户端数据一致性保护 (Data Integrity)

由于引入了 OSS 进度文件，客户端需要处理“版本冲突”：

1. **同步触发时机**：应用启动时、学习完一组单词时、手动点击同步时。
2. **冲突处理 (Merge Strategy)**：

- **本地优先**：如果本地 `last_review_time` 晚于 OSS 文件的 `last_sync_time`，则上传覆盖。
- **远程优先**：如果是新设备登录，本地为空，则从 OSS 下载并解压到 SQLite。

---

### 五、 核心表结构设计 (Flutter/SQLite)

```sql
-- 用户进度表
CREATE TABLE user_study_progress (
    word_id INTEGER PRIMARY KEY,
    dict_tag TEXT,             -- 冗余字段，方便按字典拉取进度
    ease_factor REAL DEFAULT 2.5,
    interval INTEGER DEFAULT 0,
    next_review_date TEXT,     -- 存储为 ISO8601 格式
    state INTEGER DEFAULT 0,    -- 0:New, 1:Learning, 2:Mastered
    last_modified TEXT         -- 用于同步冲突判断
);

```
