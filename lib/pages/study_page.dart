import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ai_vocab/db_helper.dart';
import 'package:ai_vocab/models/study_settings.dart';
import 'package:ai_vocab/models/word_model.dart';
import 'package:just_audio/just_audio.dart';

class StudyPageWrapper extends StatefulWidget {
  const StudyPageWrapper({super.key});

  @override
  State<StudyPageWrapper> createState() => _StudyPageWrapperState();
}

class _StudyPageWrapperState extends State<StudyPageWrapper> {
  String? _currentDict;
  DictProgress? _progress;

  @override
  void initState() {
    super.initState();
    _loadCurrentDict();
  }

  Future<void> _loadCurrentDict() async {
    final db = DBHelper();
    final dicts = await db.getDictList();
    if (dicts.isNotEmpty) {
      final name = dicts.first['name'] as String;
      final progress = await db.getDictProgress(name);
      if (mounted)
        setState(() {
          _currentDict = name;
          _progress = progress;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentDict == null) {
      return const Scaffold(body: Center(child: Text('请先选择词典')));
    }
    return StudyContent(dictName: _currentDict!, settings: _progress!.settings);
  }
}

class StudyContent extends StatefulWidget {
  final String dictName;
  final StudySettings settings;
  const StudyContent({
    super.key,
    required this.dictName,
    required this.settings,
  });

  @override
  State<StudyContent> createState() => _StudyContentState();
}

class _StudyContentState extends State<StudyContent> {
  late PageController _pageController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<String> _wordList = [];
  int _currentIndex = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadWords();
  }

  Future<void> _loadWords() async {
    final db = DBHelper();
    final words = await db.getTodayWords(widget.dictName, widget.settings);
    if (mounted)
      setState(() {
        _wordList = words;
        _loading = false;
      });
  }

  void _playAudio(String? path) async {
    if (path == null) return;
    try {
      await _audioPlayer.setAudioSource(
        AudioSource.uri(Uri.parse("https://oss.timetbb.com/word.ai/$path")),
      );
      _audioPlayer.play();
    } catch (_) {}
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    if (_wordList.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.celebration, size: 80, color: Colors.amber[400]),
              const SizedBox(height: 24),
              const Text(
                '今日学习完成！',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '明天继续加油',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentIndex = i),
                itemCount: _wordList.length,
                itemBuilder: (context, index) => _WordCardPage(
                  wordText: _wordList[index],
                  onPlayAudio: _playAudio,
                  primaryColor: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            _buildFamiliarityButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.maybePop(context),
            child: const Icon(Icons.close, size: 24),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '今日进度',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_currentIndex + 1} / ${_wordList.length} 单词',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 24),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildFamiliarityButtons(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Row(
        children: [
          _buildFamiliarityBtn(
            context,
            '熟练',
            Icons.sentiment_satisfied_alt,
            Colors.teal,
          ),
          const SizedBox(width: 12),
          _buildFamiliarityBtn(
            context,
            '认识',
            Icons.sentiment_neutral,
            Colors.orange,
          ),
          const SizedBox(width: 12),
          _buildFamiliarityBtn(
            context,
            '陌生',
            Icons.sentiment_dissatisfied,
            Colors.grey,
          ),
        ],
      ),
    );
  }

  Widget _buildFamiliarityBtn(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_currentIndex < _wordList.length - 1) {
            _pageController.nextPage(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单词卡片页面（带倒计时）
class _WordCardPage extends StatefulWidget {
  final String wordText;
  final Function(String?) onPlayAudio;
  final Color primaryColor;

  const _WordCardPage({
    required this.wordText,
    required this.onPlayAudio,
    required this.primaryColor,
  });

  @override
  State<_WordCardPage> createState() => _WordCardPageState();
}

class _WordCardPageState extends State<_WordCardPage> {
  WordDetail? _word;
  int _countdown = 3;
  bool _showDetails = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadWord();
  }

  Future<void> _loadWord() async {
    final word = await DBHelper().getWordDetail(widget.wordText);
    if (mounted) {
      setState(() => _word = word);
      _startCountdown();
    }
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 1) {
        setState(() => _countdown--);
      } else {
        timer.cancel();
        setState(() => _showDetails = true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_word == null) return const Center(child: CircularProgressIndicator());
    return _showDetails ? _buildDetailView() : _buildCountdownView();
  }

  Widget _buildCountdownView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: widget.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '词汇背诵',
                style: TextStyle(
                  color: widget.primaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              _word!.word,
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _word!.phonetic,
              style: TextStyle(fontSize: 16, color: Colors.grey[500]),
            ),
            const SizedBox(height: 40),
            // 倒计时圆环
            SizedBox(
              width: 100,
              height: 100,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: CircularProgressIndicator(
                      value: _countdown / 3,
                      strokeWidth: 4,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation(widget.primaryColor),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_countdown.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: widget.primaryColor,
                        ),
                      ),
                      Text(
                        '秒',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '释义即将显示...',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailView() {
    final word = _word!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 单词 + 音标 + 发音
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        word.word,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        word.phonetic,
                        style: TextStyle(fontSize: 15, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => widget.onPlayAudio(word.ttsPath),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: widget.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.volume_up, color: widget.primaryColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 中文释义
            _buildSectionTitle('中文释义', widget.primaryColor),
            const SizedBox(height: 8),
            Text(
              word.definitions.join('；'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),

            // 助记
            _buildMnemonicCard(word.mnemonic),
            const SizedBox(height: 24),

            // 例句
            _buildSectionTitle('例句', widget.primaryColor),
            const SizedBox(height: 12),
            ...word.usageStacks.map((s) => _buildSentenceItem(s)),

            // 常用短语
            if (word.allCollocations.isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildSectionTitle('常用短语', widget.primaryColor),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: word.allCollocations
                    .map((p) => _buildPhraseChip(p))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, Color color) {
    return Text(
      title,
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
    );
  }

  Widget _buildMnemonicCard(String mnemonic) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💡', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '助记',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  mnemonic,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSentenceItem(UsageStack stack) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '"${stack.enSentence}"',
                  style: const TextStyle(fontSize: 15, height: 1.5),
                ),
              ),
              GestureDetector(
                onTap: () => widget.onPlayAudio(stack.sentenceTts),
                child: Icon(
                  Icons.play_circle_outline,
                  size: 22,
                  color: Colors.grey[400],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '"${stack.zhSentence}"',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhraseChip(String phrase) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        phrase,
        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
      ),
    );
  }
}
