改进后的 SM-2 算法是目前主流背单词软件（如 Anki、墨墨等）的核心灵魂。它不仅仅是简单的“错一次看一遍”，而是通过**数学公式计算每一个单词的个性化“遗忘临界点”**。

为了让你在 Flutter 客户端能精准实现，我们复习一下其核心公式和逻辑流。

---

### 一、 核心数学公式

算法的核心在于两个变量：**EF (Ease Factor，简单系数)** 和 **Interval (I，复习间隔)**。

#### 1. 计算复习间隔 (Interval)

下一次复习的天数 取决于该词当前的复习次数 ：

- ** (第一次记准)**： 天
- ** (第二次记准)**： 天（或根据难度设为 3-6 天）
- \*\*\*\*：
- _例如：上一次间隔是 10 天，EF 是 2.5，那么下次就是 25 天后。_

#### 2. 更新简单系数 (EF)

EF 决定了间隔增长的速度。用户反馈越简单，EF 增长越快；越难，EF 越小。
用户评分 (Quality)：0 (完全不认识) 到 5 (完美秒杀)。

- **关键限制**：EF 的最小值不能低于 **1.3**。如果 EF 太小，单词会频繁出现，导致用户产生厌烦心理。

---

### 二、 业务逻辑：三种单词状态

在 Flutter 客户端的 SQLite 中，你需要通过 `state` 字段来管理单词的流转：

| 状态                  | 定义                       | 行为                                                             |
| --------------------- | -------------------------- | ---------------------------------------------------------------- |
| **New (新词)**        | 词典中未开始学习的词       | 每天从词库按顺序或权重取出 N 个。                                |
| **Learning (学习中)** | 处于 SM-2 周期内的词       | 每天计算 `next_review_date <= 今天` 的词。                       |
| **Lapsed (记错词)**   | 刚才复习时选了“不认识”的词 | 进入**临时内存队列**，在当前学习组结束前反复出现，直到答对为止。 |

---

### 三、 客户端伪代码实现 (Dart 风格)

假设你有一个 `WordProgress` 对象，这是处理算法更新的逻辑：

```dart
class SM2Algorithm {
  // 处理复习反馈
  // q: 用户评分 (0-5)
  // currentEF: 当前简单系数
  // currentInterval: 当前间隔
  // repetition: 第几次成功复习
  static Map<String, dynamic> calculateNextReview(int q, double currentEF, int currentInterval, int repetition) {
    int nextInterval;
    double nextEF;
    int nextRepetition;

    if (q >= 3) { // 答对了 (3: 困难, 4: 一般, 5: 简单)
      if (repetition == 0) {
        nextInterval = 1;
        nextRepetition = 1;
      } else if (repetition == 1) {
        nextInterval = 4; // 第二次间隔通常跳到4天
        nextRepetition = 2;
      } else {
        nextInterval = (currentInterval * currentEF).round();
        nextRepetition = repetition + 1;
      }

      // 更新 EF 系数
      nextEF = currentEF + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02));
    } else { // 答错了 (0, 1, 2)
      nextRepetition = 0; // 重置复习次数
      nextInterval = 1;   // 明天必须复习
      nextEF = currentEF - 0.2; // 降低 EF，让它出现更频繁
    }

    // 边界保护
    if (nextEF < 1.3) nextEF = 1.3;

    return {
      'interval': nextInterval,
      'ef': nextEF,
      'repetition': nextRepetition,
      'nextReviewDate': DateTime.now().add(Duration(days: nextInterval)),
    };
  }
}

```

---

### 四、 针对你产品的“加强版”优化建议

既然你有 AI 生成的 **Mnemonic（助记）** 和 **Usage Stacks（用法）**，算法可以更智能：

1. **首记刺激**：对于 `New` 状态的单词，第一遍强制展示“助记”，第二遍隐藏助记要求拼写或选义。
2. **权重干扰**：如果一个词在 3 个词典（如 CET4, CET6, IELTS）里都出现了，在算法初始化时，可以给它更高的 `Priority`，让它在 `New` 词库中优先被学习。
3. **失败惩罚**：如果一个单词连续 3 次复习失败（Lapses > 3），触发“深度复习”，不仅看释义，还要强制用户阅读 AI 生成的所有例句。

---
