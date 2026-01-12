import 'package:ai_vocab/db_helper.dart';
import 'package:ai_vocab/word_model.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';

class StudyPage extends StatefulWidget {
  final String dictName;
  const StudyPage({super.key, required this.dictName});

  @override
  _StudyPageState createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  late PageController _pageController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<String> _wordList = [];
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadWordList();
  }

  // 加载所选词典的所有单词
  Future<void> _loadWordList() async {
    print("DEBUG: 开始加载词典 ${widget.dictName}...");
    try {
      final dbHelper = DBHelper();
      // 强制触发数据库初始化
      await dbHelper.database;
      print("DEBUG: 数据库初始化完成");

      final list = await dbHelper.getWordListByDict(widget.dictName);
      print("DEBUG: 获取到单词列表长度: ${list.length}");

      if (mounted) {
        setState(() {
          _wordList = list;
        });
      }
    } catch (e) {
      print("DEBUG: 加载单词列表发生错误: $e");
    }
  }

  // 播放音频（0延迟感：音频已存储在本地或OSS）
  void _playAudio(String? path) async {
    if (path == null) return;
    try {
      // 如果是 OSS 链接则用 Url，如果是本地文件则用 DeviceFile
      await _audioPlayer.setAudioSource(
        AudioSource.uri(Uri.parse("https://oss.timetbb.com/word.ai/$path")),
      );
      _audioPlayer.play();
    } catch (e) {
      print("播放失败: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_wordList.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB), // 极简浅灰背景
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "${_currentIndex + 1} / ${_wordList.length}",
          style: GoogleFonts.notoSans(color: Colors.grey, fontSize: 14),
        ),
        centerTitle: true,
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemCount: _wordList.length,
        itemBuilder: (context, index) {
          return FutureBuilder<WordDetail?>(
            future: DBHelper().getWordDetail(_wordList[index]),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox();
              final word = snapshot.data!;
              return _buildWordCard(word);
            },
          );
        },
      ),
    );
  }

  Widget _buildWordCard(WordDetail word) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          // 单词与音标
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      word.word,
                      style: GoogleFonts.poppins(
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF2D3142),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      word.phonetic,
                      style: GoogleFonts.notoSans(
                        fontSize: 18,
                        color: Colors.blueGrey,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                iconSize: 48,
                icon: const Icon(Icons.volume_up_rounded, color: Colors.blue),
                onPressed: () => _playAudio(word.ttsPath),
              ),
            ],
          ),
          const SizedBox(height: 40),

          // AI 助记模块（特异性体现）
          _buildAISection(word.mnemonic),

          const SizedBox(height: 30),

          // 例句部分
          Text(
            "例句 Context",
            style: GoogleFonts.notoSans(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...word.usageStacks.map((s) => _buildSentenceTile(s)),

          const SizedBox(height: 100), // 留白，防止到底部被遮挡
        ],
      ),
    );
  }

  Widget _buildAISection(String mnemonic) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blue.withOpacity(0.1),
            Colors.purple.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                size: 18,
                color: Colors.blueAccent,
              ),
              const SizedBox(width: 8),
              Text(
                "AI 智能记忆",
                style: GoogleFonts.notoSans(
                  fontWeight: FontWeight.bold,
                  color: Colors.blueAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            mnemonic,
            style: GoogleFonts.notoSans(
              fontSize: 15,
              color: const Color(0xFF4F5D75),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSentenceTile(UsageStack stack) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stack.definition,
            style: const TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            stack.enSentence,
            style: GoogleFonts.poppins(
              fontSize: 16,
              color: const Color(0xFF2D3142),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            stack.zhSentence,
            style: GoogleFonts.notoSans(fontSize: 14, color: Colors.grey[600]),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: const Icon(
                Icons.play_circle_outline,
                size: 20,
                color: Colors.grey,
              ),
              onPressed: () => _playAudio(stack.sentenceTts),
            ),
          ),
          const Divider(),
        ],
      ),
    );
  }
}
