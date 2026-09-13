import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

// Firebase Analytics collection is gated purely on Apple's native App
// Tracking Transparency dialog — the single tracking-consent mechanism for
// now. Other platforms have no such gate, so collection stays on there.

/// Shows the native ATT dialog if the user hasn't decided yet (a no-op if
/// they already have) and syncs Firebase Analytics collection with the
/// result. Call once the UI is visible (e.g. from SplashScreen) — showing
/// it before the first frame can fail to present on iOS.
Future<void> requestTrackingPermissionAndSyncAnalytics() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
    return;
  }
  final status = await AppTrackingTransparency.requestTrackingAuthorization();
  await FirebaseAnalytics.instance
      .setAnalyticsCollectionEnabled(status == TrackingStatus.authorized);
}

/// Re-applies the last-known ATT status without prompting — call on every
/// cold start so a decision (or a later change in iOS Settings) is
/// reflected before any analytics event could fire.
Future<void> resyncAnalyticsWithTrackingPermission() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
    return;
  }
  final status = await AppTrackingTransparency.trackingAuthorizationStatus;
  await FirebaseAnalytics.instance
      .setAnalyticsCollectionEnabled(status == TrackingStatus.authorized);
}
