import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/api_service.dart';
import '../pages/ride_history_screen.dart';
import '../pages/saved_addresses_screen.dart';
import '../pages/notifications_screen.dart';
import '../pages/my_support_tickets_screen.dart';
import '../pages/quick_action_screens.dart' show MembershipScreen, PointsScreen;
import '../pages/dashboard_details_pages.dart' show EditProfileScreen;
import '../pages/legal_screen.dart';
import '../pages/about_screen.dart';

/// Customer (passenger) side drawer — styled like Uber / Pathao / inDrive:
/// a profile header the user can tap to edit, then passenger-relevant
/// shortcuts (trips, saved places, rewards, membership, notifications, help),
/// and the standard account/legal footer.
class CustomerDrawer extends StatelessWidget {
  /// Optional: jump to one of the home bottom-nav tabs (0=Home).
  final void Function(int index)? onSelectTab;

  const CustomerDrawer({super.key, this.onSelectTab});

  static const _brand = Color(0xFF10713C);

  @override
  Widget build(BuildContext context) {
    final api = Get.find<ApiService>();
    final user = api.getUser() ?? {};
    final name = (user['name'] ?? 'Guest User').toString();
    final mobile = (user['mobile'] ?? '').toString();
    final photo = ApiService.fileUrl(
        (user['image'] ?? user['profile_image']) as String?);

    return Drawer(
      child: Column(
        children: [
          // ── Profile header (tap to edit) ──
          Material(
            color: _brand,
            child: InkWell(
              onTap: () {
                Navigator.pop(context);
                Get.to(() => const EditProfileScreen());
              },
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.white,
                        backgroundImage:
                            photo != null ? NetworkImage(photo) : null,
                        child: photo == null
                            ? const Icon(Icons.person,
                                size: 32, color: _brand)
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (mobile.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                mobile,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 13),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Row(
                              children: const [
                                Text('View profile',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                                SizedBox(width: 2),
                                Icon(Icons.chevron_right,
                                    color: Colors.white, size: 16),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Menu ──
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _item(context, Icons.home_rounded, 'Home', () {
                  Navigator.pop(context);
                  onSelectTab?.call(0);
                }),
                _item(context, Icons.receipt_long_rounded, 'My Trips',
                    () => _go(context, const RideHistoryScreen())),
                _item(context, Icons.bookmark_rounded, 'Saved Places',
                    () => _go(context, const SavedAddressesScreen())),
                _item(context, Icons.card_giftcard_rounded, 'Rewards & Points',
                    () => _go(context, const PointsScreen())),
                _item(context, Icons.workspace_premium_rounded, 'GoRide Membership',
                    () => _go(context, const MembershipScreen())),
                _item(context, Icons.notifications_rounded, 'Notifications',
                    () => _go(context, const NotificationsScreen())),
                _item(context, Icons.support_agent_rounded, 'Help & Support',
                    () => _go(context, const MySupportTicketsScreen())),
                const Divider(height: 24),
                _item(context, Icons.lock_outline_rounded, 'Change Password',
                    () {
                  Navigator.pop(context);
                  Get.toNamed('/change-password');
                }),
                _item(context, Icons.description_outlined, 'Terms of Service',
                    () => _go(context, LegalScreen.terms())),
                _item(context, Icons.privacy_tip_outlined, 'Privacy Policy',
                    () => _go(context, LegalScreen.privacy())),
                _item(context, Icons.info_outline_rounded, 'About',
                    () => _go(context, const AboutScreen())),
              ],
            ),
          ),

          // ── Logout ──
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: ListTile(
              leading: const Icon(Icons.logout_rounded, color: Colors.red),
              title: const Text('Logout',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
              onTap: () async {
                await api.logout();
                Get.offAllNamed('/');
              },
            ),
          ),
        ],
      ),
    );
  }

  void _go(BuildContext context, Widget screen) {
    Navigator.pop(context);
    Get.to(() => screen);
  }

  Widget _item(
      BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: _brand.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: _brand, size: 20),
      ),
      title: Text(label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
      onTap: onTap,
    );
  }
}
