import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdMob 广告服务
class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  bool _isInitialized = false;
  InterstitialAd? _interstitialAd;
  RewardedAd? _rewardedAd;
  int _studyCount = 0; // 学习计数，用于控制插屏广告频率

  // 测试广告单元ID（发布前替换为真实ID）
  static String get bannerAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/9214589741'; // Android 测试
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/2934735716'; // iOS 测试
    }
    return '';
  }

  static String get interstitialAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/1033173712'; // Android 测试
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/4411468910'; // iOS 测试
    }
    return '';
  }

  static String get rewardedAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/5224354917'; // Android 测试
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/1712485313'; // iOS 测试
    }
    return '';
  }

  static String get nativeAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/2247696110'; // Android 测试
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/3986624511'; // iOS 测试
    }
    return '';
  }

  /// 初始化 AdMob
  Future<void> initialize() async {
    if (_isInitialized) return;
    if (!Platform.isAndroid && !Platform.isIOS) return; // 桌面端不支持

    await MobileAds.instance.initialize();
    _isInitialized = true;

    // 预加载广告
    _loadInterstitialAd();
    _loadRewardedAd();
  }

  /// 加载插屏广告
  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _interstitialAd!.fullScreenContentCallback =
              FullScreenContentCallback(
                onAdDismissedFullScreenContent: (ad) {
                  ad.dispose();
                  _loadInterstitialAd(); // 重新加载
                },
                onAdFailedToShowFullScreenContent: (ad, error) {
                  ad.dispose();
                  _loadInterstitialAd();
                },
              );
        },
        onAdFailedToLoad: (error) {
          debugPrint('插屏广告加载失败: $error');
        },
      ),
    );
  }

  /// 加载激励广告
  void _loadRewardedAd() {
    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _loadRewardedAd();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _loadRewardedAd();
            },
          );
        },
        onAdFailedToLoad: (error) {
          debugPrint('激励广告加载失败: $error');
        },
      ),
    );
  }

  /// 记录学习次数，每学习 N 个单词显示一次插屏广告
  void recordStudy() {
    _studyCount++;
    if (_studyCount >= 5) {
      // 每学习5个单词
      showInterstitialAd();
      _studyCount = 0;
    }
  }

  /// 显示插屏广告
  Future<bool> showInterstitialAd() async {
    if (_interstitialAd == null) return false;
    await _interstitialAd!.show();
    _interstitialAd = null;
    return true;
  }

  /// 显示激励广告（用于获取额外功能，如跳过等待时间）
  Future<bool> showRewardedAd({Function(int amount)? onRewarded}) async {
    if (_rewardedAd == null) return false;

    await _rewardedAd!.show(
      onUserEarnedReward: (ad, reward) {
        onRewarded?.call(reward.amount.toInt());
      },
    );
    _rewardedAd = null;
    return true;
  }

  /// 创建 Banner 广告
  BannerAd createBannerAd({Function()? onLoaded}) {
    return BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) => onLoaded?.call(),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('Banner广告加载失败: $error');
        },
      ),
    );
  }

  /// 检查是否支持广告（桌面端不支持）
  bool get isSupported => Platform.isAndroid || Platform.isIOS;

  /// 释放资源
  void dispose() {
    _interstitialAd?.dispose();
    _rewardedAd?.dispose();
  }
}
