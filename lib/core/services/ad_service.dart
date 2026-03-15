import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  // Production ad unit IDs from compile-time environment (--dart-define).
  // Fallback values are test ad unit IDs.
  static const String _androidBannerEnv = String.fromEnvironment(
    'AD_BANNER_ANDROID',
    defaultValue: '',
  );
  static const String _iosBannerEnv = String.fromEnvironment(
    'AD_BANNER_IOS',
    defaultValue: '',
  );
  static const String _androidRewardedEnv = String.fromEnvironment(
    'AD_REWARDED_ANDROID',
    defaultValue: '',
  );
  static const String _iosRewardedEnv = String.fromEnvironment(
    'AD_REWARDED_IOS',
    defaultValue: '',
  );

  Future<void> initialize() async {
    await MobileAds.instance.initialize();
  }

  String get bannerAdUnitId {
    if (kDebugMode) {
      if (Platform.isAndroid) {
        return 'ca-app-pub-3940256099942544/6300978111'; // Test Android Banner
      } else if (Platform.isIOS) {
        return 'ca-app-pub-3940256099942544/2934735716'; // Test iOS Banner
      }
    }

    if (Platform.isAndroid) {
      return _androidBannerEnv.isNotEmpty
          ? _androidBannerEnv
          : 'ca-app-pub-3940256099942544/6300978111'; // fallback to test
    } else if (Platform.isIOS) {
      return _iosBannerEnv.isNotEmpty
          ? _iosBannerEnv
          : 'ca-app-pub-3940256099942544/2934735716'; // fallback to test
    }
    throw UnsupportedError('Unsupported platform');
  }

  String get rewardedAdUnitId {
    if (kDebugMode) {
      if (Platform.isAndroid) {
        return 'ca-app-pub-3940256099942544/5224354917'; // Test Android Rewarded
      } else if (Platform.isIOS) {
        return 'ca-app-pub-3940256099942544/1712485313'; // Test iOS Rewarded
      }
    }

    if (Platform.isAndroid) {
      return _androidRewardedEnv.isNotEmpty
          ? _androidRewardedEnv
          : 'ca-app-pub-3940256099942544/5224354917'; // fallback to test
    } else if (Platform.isIOS) {
      return _iosRewardedEnv.isNotEmpty
          ? _iosRewardedEnv
          : 'ca-app-pub-3940256099942544/1712485313'; // fallback to test
    }
    throw UnsupportedError('Unsupported platform');
  }

  BannerAd createBannerAd({required Function() onAdLoaded}) {
    return BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => onAdLoaded(),
        onAdFailedToLoad: (ad, error) {
          debugPrint('Ad failed to load: $error');
          ad.dispose();
        },
      ),
    );
  }
}
