import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_service.dart';

class AdNotifier extends ChangeNotifier {
  static const Duration _inactivityTimeout = Duration(minutes: 30);

  bool _bannerHiddenForSession = false;
  bool get bannerHiddenForSession => _bannerHiddenForSession;
  bool get showBanner => !_bannerHiddenForSession;

  RewardedAd? _rewardedAd;
  bool _isRewardedAdReady = false;
  bool get isRewardedAdReady => _isRewardedAdReady;

  Timer? _inactivityTimer;

  AdNotifier() {
    _loadRewardedAd();
  }

  void _loadRewardedAd() {
    RewardedAd.load(
      adUnitId: AdService().rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isRewardedAdReady = true;
          notifyListeners();
        },
        onAdFailedToLoad: (error) {
          debugPrint('Rewarded ad failed to load: $error');
          _isRewardedAdReady = false;
          // Retry after a delay
          Future.delayed(const Duration(seconds: 30), _loadRewardedAd);
        },
      ),
    );
  }

  /// Show the rewarded ad. Returns true if reward was earned.
  Future<bool> showRewardedAd() async {
    if (_rewardedAd == null || !_isRewardedAdReady) return false;

    final completer = Completer<bool>();

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        _isRewardedAdReady = false;
        _loadRewardedAd(); // Preload next one
        if (!completer.isCompleted) completer.complete(false);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('Rewarded ad failed to show: $error');
        ad.dispose();
        _rewardedAd = null;
        _isRewardedAdReady = false;
        _loadRewardedAd();
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    _rewardedAd!.show(
      onUserEarnedReward: (ad, reward) {
        _bannerHiddenForSession = true;
        _startInactivityTimer();
        notifyListeners();
        if (!completer.isCompleted) completer.complete(true);
      },
    );

    return completer.future;
  }

  /// Call when TTS starts playing to reset the inactivity timer.
  void onAudioPlaying() {
    if (!_bannerHiddenForSession) return;
    _startInactivityTimer();
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_inactivityTimeout, () {
      _bannerHiddenForSession = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _rewardedAd?.dispose();
    super.dispose();
  }
}
