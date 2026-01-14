# 修复：队列新词学习结束后，队尾复习单词倒计时无法启动

## 问题描述

当用户学习完队列中的新词后，点击"不认识"将单词加入队列末尾作为复习单词。但是当跳转到这个复习单词时，倒计时无法启动，页面停留在加载状态。

## 问题分析

### 时序问题

1. **用户点击"不认识"**

   - `_handleFamiliarity` 方法被调用
   - 单词被添加到 `_session!.queue` 末尾
   - 调用 `setState` 触发 PageView 重建
   - 调用 `_goToNextWord()` 跳转到下一页

2. **PageView 重建**

   - `itemCount` 增加（包含新添加的单词）
   - 所有页面（包括新页面）被重建
   - 新页面的 `_WordCardPage` 被创建，此时 `isActive = false`（因为 `_currentIndex` 还没更新）

3. **新页面初始化**

   - `initState` 被调用
   - `_loadWord()` 异步加载单词数据
   - 此时 `widget.isActive` 是 `false`，所以不会启动倒计时

4. **PageController.nextPage() 执行**

   - 页面动画开始
   - 动画完成后，`onPageChanged` 被调用
   - `_currentIndex` 更新为新页面的索引
   - `setState` 触发重建

5. **didUpdateWidget 被调用**
   - `widget.isActive` 从 `false` 变为 `true`
   - 但此时 `_word` 可能还是 `null`（如果 `_loadWord` 还没完成）
   - 如果 `_word` 是 `null`，倒计时不会启动

### 根本原因

**异步加载和页面激活的时序不确定性**：

- 如果 `_loadWord` 在 `didUpdateWidget` 之前完成，倒计时可以正常启动
- 如果 `_loadWord` 在 `didUpdateWidget` 之后完成，倒计时不会启动（因为 `_loadWord` 中检查 `widget.isActive` 时还是 `false`）

## 解决方案

### 修改 1: 优化 `_loadWord` 方法

确保单词加载完成后，如果页面是活跃的且还没显示详情，就启动倒计时。

```dart
Future<void> _loadWord() async {
  print('DEBUG _WordCardPage: 开始加载单词 - word=${widget.wordText}, isActive=${widget.isActive}');
  final word = await DBHelper().getWordDetail(widget.wordText);
  if (mounted) {
    setState(() => _word = word);
    print('DEBUG _WordCardPage: 单词加载完成 - word=${widget.wordText}, isActive=${widget.isActive}, _showDetails=$_showDetails');
    // 单词加载完成后，如果页面是活跃的且还没显示详情，启动倒计时
    if (widget.isActive && !_showDetails) {
      print('DEBUG _WordCardPage: 单词加载后启动倒计时 - word=${widget.wordText}');
      widget.onPlayAudio(word?.ttsPath, word: word?.word);
      _startCountdown();
    }
  }
}
```

**关键改进**：

- 添加 `!_showDetails` 检查，避免重复启动倒计时
- 在单词加载完成后再次检查 `widget.isActive`

### 修改 2: 优化 `didUpdateWidget` 方法

当页面从不活跃变为活跃时，如果单词已加载且还没显示详情，就启动倒计时。

```dart
@override
void didUpdateWidget(_WordCardPage oldWidget) {
  super.didUpdateWidget(oldWidget);
  if (widget.isActive && !oldWidget.isActive) {
    // 页面从不活跃变为活跃
    print('DEBUG _WordCardPage: 页面激活 - word=${widget.wordText}, _word=${_word?.word}, _showDetails=$_showDetails');
    if (_word != null) {
      widget.onPlayAudio(_word?.ttsPath, word: _word?.word);
      // 如果还没有显示详情，且倒计时未启动，则启动倒计时
      if (!_showDetails) {
        print('DEBUG _WordCardPage: 启动倒计时 - word=${widget.wordText}');
        _startCountdown();
      }
    } else {
      print('DEBUG _WordCardPage: 单词尚未加载，等待 _loadWord 完成 - word=${widget.wordText}');
    }
  } else if (!widget.isActive && oldWidget.isActive) {
    // 页面从活跃变为不活跃
    print('DEBUG _WordCardPage: 页面失活 - word=${widget.wordText}');
    _timer?.cancel();
    _animationController.stop();
  }
}
```

**关键改进**：

- 添加 `!_showDetails` 检查，避免重复启动倒计时
- 添加调试日志，便于追踪问题

### 修改 3: 优化 `_startCountdown` 方法

添加调试日志，便于追踪倒计时的启动和结束。

```dart
void _startCountdown() {
  print('DEBUG _WordCardPage: _startCountdown 被调用 - word=${widget.wordText}');
  // 确保先取消之前可能存在的计时器
  _timer?.cancel();

  // 重置状态并更新 UI
  setState(() {
    _countdown = _totalSeconds;
    _showDetails = false;
  });

  // 重置并启动动画控制器
  _animationController.reset();
  _animationController.forward();

  _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
    if (_countdown > 1) {
      setState(() => _countdown--);
    } else {
      timer.cancel();
      print('DEBUG _WordCardPage: 倒计时结束，显示详情 - word=${widget.wordText}');
      setState(() => _showDetails = true);
      widget.onShowDetails?.call();
    }
  });
}
```

## 时序图（修复后）

```
用户点击"不认识"
    │
    ▼
_handleFamiliarity
    │
    ├─ 添加单词到队列
    ├─ setState (触发 PageView 重建)
    └─ _goToNextWord()
         │
         ▼
    PageView 重建
         │
         ├─ 创建新页面 (_WordCardPage)
         │   │
         │   ├─ initState
         │   └─ _loadWord() [异步]
         │
         └─ nextPage() [动画]
              │
              ▼
         onPageChanged
              │
              ├─ _currentIndex 更新
              └─ setState (触发重建)
                   │
                   ▼
              didUpdateWidget
                   │
                   ├─ isActive: false → true
                   │
                   ├─ 情况1: _word != null
                   │   └─ 启动倒计时 ✅
                   │
                   └─ 情况2: _word == null
                       └─ 等待 _loadWord 完成
                            │
                            ▼
                       _loadWord 完成
                            │
                            ├─ _word 赋值
                            ├─ 检查 isActive && !_showDetails
                            └─ 启动倒计时 ✅
```

## 测试步骤

1. **启动应用并开始学习**

   ```
   - 选择一个词典
   - 点击"开始背诵"
   ```

2. **学习新词并点击"不认识"**

   ```
   - 学习第一个新词
   - 点击"没记住"按钮
   - 观察控制台日志
   ```

3. **继续学习到队列末尾**

   ```
   - 继续学习其他新词
   - 当到达之前点击"不认识"的单词时
   - 观察倒计时是否正常启动
   ```

4. **检查控制台日志**

   ```
   应该看到类似的日志：

   DEBUG _WordCardPage: 开始加载单词 - word=apple, isActive=false
   DEBUG _WordCardPage: 单词加载完成 - word=apple, isActive=false, _showDetails=false
   DEBUG _WordCardPage: 页面激活 - word=apple, _word=apple, _showDetails=false
   DEBUG _WordCardPage: 启动倒计时 - word=apple
   DEBUG _WordCardPage: _startCountdown 被调用 - word=apple
   ```

## 预期结果

- ✅ 倒计时正常启动（5 秒倒计时）
- ✅ 倒计时结束后显示单词详情
- ✅ 可以正常选择熟悉度
- ✅ 控制台日志显示正确的执行顺序

## 相关文件

- `lib/pages/study_page.dart` - 修改了 `_WordCardPage` 的生命周期管理

## 注意事项

1. **调试日志**：修复后的代码包含详细的调试日志，可以在生产环境中移除
2. **性能影响**：修复不会影响性能，只是优化了时序逻辑
3. **兼容性**：修复不会影响其他功能，所有现有功能保持不变

## 总结

这个问题的根本原因是异步加载和页面激活的时序不确定性。通过在两个关键点（`_loadWord` 完成和 `didUpdateWidget`）都检查并启动倒计时，确保无论哪个先执行，倒计时都能正常启动。
