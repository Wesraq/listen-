import 'dart:io';

/// AdMob app / unit IDs.
///
/// Defaults to Google's official **test** IDs so debug builds never generate
/// invalid traffic. Pass production IDs at build time:
///
/// ```
/// flutter run --dart-define=ADMOB_ANDROID_APP_ID=ca-app-pub-xxxx~yyyy \
///   --dart-define=ADMOB_IOS_APP_ID=ca-app-pub-xxxx~yyyy \
///   --dart-define=ADMOB_ANDROID_REWARDED_INTERSTITIAL_ID=ca-app-pub-xxxx/yyyy \
///   --dart-define=ADMOB_IOS_REWARDED_INTERSTITIAL_ID=ca-app-pub-xxxx/yyyy \
///   --dart-define=ADMOB_USE_TEST_ADS=false
/// ```
///
/// Create apps + rewarded interstitial units in AdMob for:
/// - Android applicationId `com.listenplus.listen_plus`
/// - iOS bundle `io.listen.listen`
class AdConfig {
  AdConfig._();

  static const bool useTestAds = bool.fromEnvironment(
    'ADMOB_USE_TEST_ADS',
    defaultValue: true,
  );

  static const String _androidAppId = String.fromEnvironment(
    'ADMOB_ANDROID_APP_ID',
    defaultValue: 'ca-app-pub-3940256099942544~3347511713',
  );
  static const String _iosAppId = String.fromEnvironment(
    'ADMOB_IOS_APP_ID',
    defaultValue: 'ca-app-pub-3940256099942544~1458002511',
  );

  static const String _androidRewardedInterstitial = String.fromEnvironment(
    'ADMOB_ANDROID_REWARDED_INTERSTITIAL_ID',
    defaultValue: 'ca-app-pub-3940256099942544/5354046379',
  );
  static const String _iosRewardedInterstitial = String.fromEnvironment(
    'ADMOB_IOS_REWARDED_INTERSTITIAL_ID',
    defaultValue: 'ca-app-pub-3940256099942544/6978759866',
  );

  /// Google demo app IDs (safe defaults until real AdMob apps are registered).
  static const String testAndroidAppId = 'ca-app-pub-3940256099942544~3347511713';
  static const String testIosAppId = 'ca-app-pub-3940256099942544~1458002511';

  static String get appId {
    if (useTestAds) {
      return Platform.isIOS ? testIosAppId : testAndroidAppId;
    }
    return Platform.isIOS ? _iosAppId : _androidAppId;
  }

  static String get rewardedInterstitialUnitId {
    if (useTestAds) {
      return Platform.isIOS
          ? 'ca-app-pub-3940256099942544/6978759866'
          : 'ca-app-pub-3940256099942544/5354046379';
    }
    return Platform.isIOS ? _iosRewardedInterstitial : _androidRewardedInterstitial;
  }
}
