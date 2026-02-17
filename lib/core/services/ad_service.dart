import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

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
      return 'ca-app-pub-1274598295446847/3374869571'; // PRODUCTION ID
    } else if (Platform.isIOS) {
      return 'ca-app-pub-1274598295446847/3374869571'; // Keeping same ID for iOS if user intended cross-platform or separate. Based on request, using provided ID.
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
