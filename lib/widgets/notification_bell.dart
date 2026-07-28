import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../pages/notifications_screen.dart';
import '../services/notification_badge_service.dart';

/// The notification bell used in every dashboard app bar.
///
/// Shows a red count badge when there is unread mail, with a soft pulse ring
/// so a new alert catches the eye without the jitter of a hard blink. Reads
/// [NotificationBadgeService], so every bell in the app stays in sync.
class NotificationBell extends StatefulWidget {
  const NotificationBell({
    super.key,
    this.color = Colors.white,
    this.icon = Icons.notifications_rounded,
    this.onOpen,
  });

  /// Icon colour — pass a dark colour for light app bars.
  final Color color;
  final IconData icon;

  /// Defaults to opening the notifications screen.
  final VoidCallback? onOpen;

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// Only animate while something is actually unread — a permanently pulsing
  /// icon is noise, and it would keep the device awake for nothing.
  void _syncPulse(int unread) {
    if (unread > 0 && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (unread == 0 && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  void _open() {
    if (widget.onOpen != null) {
      widget.onOpen!();
    } else {
      Get.to(() => const NotificationsScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    // If the service isn't registered (e.g. a screen shown before login),
    // fall back to a plain bell rather than crashing.
    if (!Get.isRegistered<NotificationBadgeService>()) {
      return IconButton(
        icon: Icon(widget.icon, color: widget.color),
        onPressed: _open,
      );
    }

    final badge = Get.find<NotificationBadgeService>();

    return Obx(() {
      final unread = badge.unread.value;
      _syncPulse(unread);

      return Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            icon: Icon(widget.icon, color: widget.color),
            tooltip: unread > 0 ? '$unread new notifications' : 'Notifications',
            onPressed: _open,
          ),
          if (unread > 0)
            Positioned(
              right: 4,
              top: 4,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, child) {
                    // One expanding, fading ring per cycle.
                    final t = _pulse.value;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 18 + (t * 14),
                          height: 18 + (t * 14),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.red.withValues(alpha: (1 - t) * 0.35),
                          ),
                        ),
                        child!,
                      ],
                    );
                  },
                  child: _countChip(unread),
                ),
              ),
            ),
        ],
      );
    });
  }

  Widget _countChip(int unread) {
    final label = unread > 99 ? '99+' : '$unread';
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: EdgeInsets.symmetric(horizontal: unread > 9 ? 5 : 0),
      decoration: BoxDecoration(
        color: const Color(0xFFE53935),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          height: 1.1,
        ),
      ),
    );
  }
}
