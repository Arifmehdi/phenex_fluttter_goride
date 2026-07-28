import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/api_service.dart';
import '../services/notification_badge_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _api = Get.find<ApiService>();
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _api.getNotifications();
      if (res.statusCode == 200) {
        final data = res.data['notifications'] ?? res.data['data'] ?? [];
        setState(() {
          _notifications = List<Map<String, dynamic>>.from(
            (data is List ? data : (data['data'] ?? [])).map((e) => Map<String, dynamic>.from(e as Map)));
        });
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  /// Keeps the app-bar bell badge in step with what's been read here.
  void _syncBadge() {
    if (Get.isRegistered<NotificationBadgeService>()) {
      Get.find<NotificationBadgeService>().refresh();
    }
  }

  Future<void> _markAllRead() async {
    await _api.markAllNotificationsRead();
    setState(() {
      for (final n in _notifications) { n['is_read'] = 1; }
    });
    if (Get.isRegistered<NotificationBadgeService>()) {
      Get.find<NotificationBadgeService>().clear();
    }
  }

  Future<void> _markRead(Map<String, dynamic> notif) async {
    if (notif['is_read'] == 1) return;
    await _api.markNotificationRead(notif['id'] as int);
    setState(() => notif['is_read'] = 1);
    _syncBadge();
  }

  IconData _iconFor(String? type) {
    switch (type) {
      case 'ride_request':   return Icons.directions_car;
      case 'ride_accepted':  return Icons.check_circle;
      case 'trip_completed': return Icons.flag;
      case 'payment':        return Icons.payments;
      case 'promo':          return Icons.local_offer;
      default:               return Icons.notifications;
    }
  }

  Color _colorFor(String? type) {
    switch (type) {
      case 'ride_request':   return Colors.blue;
      case 'ride_accepted':  return Colors.green;
      case 'trip_completed': return const Color(0xFF10713C);
      case 'payment':        return Colors.purple;
      case 'promo':          return Colors.orange;
      default:               return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications.where((n) => n['is_read'] != 1).length;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: const Color(0xFF10713C),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read', style: TextStyle(color: Colors.white, fontSize: 13)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10713C)))
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_off_outlined, size: 72, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text('No notifications yet',
                          style: TextStyle(fontSize: 16, color: Colors.grey[500])),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: const Color(0xFF10713C),
                  child: ListView.builder(
                    itemCount: _notifications.length,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemBuilder: (ctx, i) {
                      final n = _notifications[i];
                      final isRead = n['is_read'] == 1;
                      final type = n['type'] as String?;
                      return GestureDetector(
                        onTap: () => _markRead(n),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isRead ? Colors.white : const Color(0xFF10713C).withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isRead ? Colors.grey.shade100 : const Color(0xFF10713C).withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: _colorFor(type).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(_iconFor(type), color: _colorFor(type), size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      n['title'] ?? 'Notification',
                                      style: TextStyle(
                                        fontWeight: isRead ? FontWeight.w500 : FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (n['message'] != null) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        n['message'] as String,
                                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Text(
                                      _timeAgo(n['created_at'] as String?),
                                      style: TextStyle(color: Colors.grey[400], fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              if (!isRead)
                                Container(
                                  width: 8, height: 8,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF10713C),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso);
      final diff = DateTime.now().difference(dt);
      if (diff.inDays > 0) return '${diff.inDays}d ago';
      if (diff.inHours > 0) return '${diff.inHours}h ago';
      if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
      return 'Just now';
    } catch (_) { return ''; }
  }
}
