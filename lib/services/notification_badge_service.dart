import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'api_service.dart';

/// Holds the unread-notification count for the bell badge.
///
/// One source of truth for every bell in the app (rider, driver, corporate,
/// owner, admin), so they can never disagree. The count refreshes when:
///   • the app starts / returns to the foreground
///   • a push notification arrives while the app is open
///   • the user opens or clears the notifications screen
///   • a slow poll ticks (safety net for pushes that never arrive)
class NotificationBadgeService extends GetxService with WidgetsBindingObserver {
  final RxInt unread = 0.obs;

  Timer? _poll;
  bool _loggedIn = false;

  /// Slow on purpose — pushes do the real-time work, this is just a backstop.
  static const _pollInterval = Duration(minutes: 2);

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);

    // Follow the session: poll while signed in, go quiet on sign-out.
    final api = Get.find<ApiService>();
    if (api.isLoggedIn()) start();
    ever<bool>(api.loggedIn, (v) => v ? start() : stop());
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  /// Call after login so polling only runs for signed-in users.
  void start() {
    _loggedIn = true;
    refresh();
    _poll?.cancel();
    _poll = Timer.periodic(_pollInterval, (_) => refresh());
  }

  /// Call on logout — stops polling and clears the badge.
  void stop() {
    _loggedIn = false;
    _poll?.cancel();
    _poll = null;
    unread.value = 0;
  }

  /// Re-reads the count from the server.
  Future<void> refresh() async {
    if (!_loggedIn) return;
    try {
      final res = await Get.find<ApiService>().getUnreadNotificationCount();
      if (res.statusCode == 200 && res.data is Map) {
        final n = res.data['unread'];
        unread.value = n is int ? n : int.tryParse('$n') ?? 0;
      }
    } catch (_) {
      // Offline or server hiccup — keep the last known value.
    }
  }

  /// Optimistic bump when a push lands while the app is open, so the badge
  /// reacts instantly; the next refresh reconciles with the server.
  void increment() => unread.value = unread.value + 1;

  /// Called when the user clears everything on the notifications screen.
  void clear() => unread.value = 0;
}
