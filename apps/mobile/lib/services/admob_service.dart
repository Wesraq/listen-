import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config/ad_config.dart';

enum AdShowResult {
  /// User finished the ad and earned the reward (monetisable).
  rewarded,
  /// Ad dismissed without a reward, or user declined the intro.
  skipped,
  /// No fill / load or show failure — resume playback without crediting.
  failed,
}

/// Loads and shows AdMob rewarded interstitial ads for free-with-ads breaks.
class AdMobService {
  AdMobService._();
  static final AdMobService instance = AdMobService._();

  bool _initialised = false;
  RewardedInterstitialAd? _ready;
  bool _loading = false;

  bool get isReady => _ready != null;

  Future<void> initialise() async {
    if (_initialised) return;
    if (kIsWeb) return;
    try {
      // Give the Activity a moment to attach before touching the Ads SDK.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await MobileAds.instance.initialize();
      _initialised = true;
      // Warm the first unit so preroll isn't blocked on cold load.
      unawaited(preload());
    } catch (error, stackTrace) {
      debugPrint('AdMob init failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _initialised = false;
    }
  }

  Future<void> preload() async {
    if (kIsWeb || !_initialised || _loading || _ready != null) return;
    _loading = true;
    final completer = Completer<void>();
    await RewardedInterstitialAd.load(
      adUnitId: AdConfig.rewardedInterstitialUnitId,
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _ready = ad;
          _loading = false;
          if (!completer.isCompleted) completer.complete();
        },
        onAdFailedToLoad: (error) {
          debugPrint('Rewarded interstitial failed to load: $error');
          _ready = null;
          _loading = false;
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );
    await completer.future;
  }

  /// Shows a rewarded interstitial. Loads on demand if the cache is empty.
  Future<AdShowResult> showRewardedInterstitial({
    Duration loadTimeout = const Duration(seconds: 12),
    String? userId,
    String? customData,
  }) async {
    if (kIsWeb || !_initialised) return AdShowResult.failed;

    if (_ready == null) {
      await preload().timeout(loadTimeout, onTimeout: () {});
    }
    final ad = _ready;
    if (ad == null) return AdShowResult.failed;
    _ready = null;

    if (userId != null || customData != null) {
      await ad.setServerSideOptions(
        ServerSideVerificationOptions(
          userId: userId,
          customData: customData,
        ),
      );
    }

    final result = Completer<AdShowResult>();
    var earned = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!result.isCompleted) {
          result.complete(earned ? AdShowResult.rewarded : AdShowResult.skipped);
        }
        unawaited(preload());
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('Rewarded interstitial failed to show: $error');
        ad.dispose();
        if (!result.isCompleted) result.complete(AdShowResult.failed);
        unawaited(preload());
      },
    );

    await ad.show(
      onUserEarnedReward: (ad, reward) {
        earned = true;
      },
    );

    return result.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () => earned ? AdShowResult.rewarded : AdShowResult.failed,
    );
  }

  void dispose() {
    _ready?.dispose();
    _ready = null;
  }
}
