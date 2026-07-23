import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/api_service.dart';
import '../pages/home_page.dart';
import '../pages/dashboard_details_pages.dart';
import '../pages/my_support_tickets_screen.dart';
import '../pages/ride_history_screen.dart';
import '../pages/saved_addresses_screen.dart';
import '../pages/legal_screen.dart';
import '../pages/about_screen.dart';
import '../pages/rewards_screen.dart';

class SidebarMenu extends StatelessWidget {
  final String role;
  final Function(int)? onSelectedIndexChanged;
  
  const SidebarMenu({
    super.key, 
    required this.role,
    this.onSelectedIndexChanged,
  });

  @override
  Widget build(BuildContext context) {
    final ApiService apiService = Get.find<ApiService>();
    final user = apiService.getUser();
    final name = (user?['name'] ?? 'Guest User').toString();
    final mobile = (user?['mobile'] ?? '').toString();
    final photoUrl =
        ApiService.fileUrl((user?['image'] ?? user?['profile_image']) as String?);

    return Drawer(
      child: Column(
        children: [
          // Scrollable menu area
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // Header: avatar on the left, name + phone stacked beside it.
                Container(
                  color: const Color(0xFF10713C),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: Colors.white,
                            backgroundImage:
                                photoUrl != null ? NetworkImage(photoUrl) : null,
                            child: photoUrl == null
                                ? const Icon(Icons.person,
                                    size: 34, color: Color(0xFF10713C))
                                : null,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
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
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 13),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.public, color: Color(0xFF10713C)),
                  title: const Text('Main Portal'),
                  onTap: () {
                    Get.offAll(() => HomePage());
                  },
                ),
                const Divider(),
                ..._buildRoleSpecificMenus(context),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.lock_outline, color: Color(0xFF10713C)),
                  title: const Text('Change Password'),
                  onTap: () {
                    Navigator.pop(context);
                    Get.toNamed('/change-password');
                  },
                ),
                // Rewards & referral — everyone except admins earns points/invites.
                if (role != 'admin')
                  ListTile(
                    leading: const Icon(Icons.card_giftcard, color: Color(0xFF10713C)),
                    title: const Text('Rewards & Invite'),
                    onTap: () {
                      Navigator.pop(context);
                      Get.to(() => const RewardsScreen());
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.help, color: Colors.grey),
                  title: const Text('Help & Support'),
                  onTap: () {
                    Navigator.pop(context);
                    Get.to(() => const MySupportTicketsScreen());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined, color: Colors.grey),
                  title: const Text('Terms of Service'),
                  onTap: () {
                    Navigator.pop(context);
                    Get.to(() => LegalScreen.terms());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined, color: Colors.grey),
                  title: const Text('Privacy Policy'),
                  onTap: () {
                    Navigator.pop(context);
                    Get.to(() => LegalScreen.privacy());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline, color: Colors.grey),
                  title: const Text('About'),
                  onTap: () {
                    Navigator.pop(context);
                    Get.to(() => const AboutScreen());
                  },
                ),
              ],
            ),
          ),

          // Logout pinned to the bottom (always visible, clears the system nav bar)
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
              onTap: () async {
                await apiService.logout();
                Get.offAllNamed('/');
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildRoleSpecificMenus(BuildContext context) {
    switch (role) {
      case 'driver':
        return [
          _menuItem(Icons.dashboard, 'Dashboard', () {
            Navigator.pop(context);
            onSelectedIndexChanged?.call(0);
          }),
          _menuItem(Icons.local_offer, 'My Bids', () {
            Navigator.pop(context);
            onSelectedIndexChanged?.call(1);
          }),
          _menuItem(Icons.directions_car, 'My Vehicle', () {
            Navigator.pop(context);
            Get.to(() => const MyVehiclesScreen());
          }),
          _menuItem(Icons.trending_up, 'Earnings', () {
            Navigator.pop(context);
            onSelectedIndexChanged?.call(2);
          }),
          _menuItem(Icons.history, 'Trip History', () {
            Navigator.pop(context);
            Get.to(() => const RideHistoryScreen());
          }),
        ];
      case 'owner':
        return [
          _menuItem(Icons.dashboard, 'Dashboard', () {
            Navigator.pop(context);
            onSelectedIndexChanged?.call(0);
          }),
          _menuItem(Icons.directions_car, 'My Fleet', () {
            Navigator.pop(context);
            onSelectedIndexChanged?.call(1);
          }),
          _menuItem(Icons.people, 'Rider Management', () {
            Navigator.pop(context);
            // Handle specific navigation if available
          }),
          _menuItem(Icons.account_balance_wallet, 'Earnings', () {
            Navigator.pop(context);
            onSelectedIndexChanged?.call(2);
          }),
        ];
      case 'corporate':
        return [
          _menuItem(Icons.dashboard, 'Dashboard', () {
            Navigator.pop(context);
            onSelectedIndexChanged?.call(0);
          }),
          _menuItem(Icons.business, 'Company Fleet', () {
            Navigator.pop(context);
            onSelectedIndexChanged?.call(1);
          }),
          _menuItem(Icons.receipt, 'Billing & Invoices', () {
            Navigator.pop(context);
            onSelectedIndexChanged?.call(2);
          }),
          _menuItem(Icons.group, 'Employee Management', () {
            Navigator.pop(context);
            // Handle Employee Management
          }),
        ];
      case 'admin':
        return [
          _menuItem(Icons.admin_panel_settings, 'Admin Panel', () {
            Navigator.pop(context);
            onSelectedIndexChanged?.call(0);
          }),
          _menuItem(Icons.people, 'User Management', () {
            Navigator.pop(context);
            Get.to(() => const UserManagementScreen());
          }),
          _menuItem(Icons.directions_car, 'Vehicle Management', () {
            Navigator.pop(context);
            Get.to(() => const VehicleManagementScreen());
          }),
          _menuItem(Icons.payment, 'Payment Management', () {
            Navigator.pop(context);
            Get.to(() => const PaymentManagementScreen());
          }),
          _menuItem(Icons.support_agent, 'Support Tickets', () {
            Navigator.pop(context);
            Get.to(() => const SupportTicketsScreen());
          }),
          _menuItem(Icons.bar_chart, 'Reports', () {
            Navigator.pop(context);
            Get.to(() => const ReportsAnalyticsScreen());
          }),
        ];
      case 'solo': // passenger / customer
      case 'user':
        return [
          _menuItem(Icons.home, 'Home', () {
            Navigator.pop(context);
            onSelectedIndexChanged?.call(0);
          }),
          _menuItem(Icons.history, 'My Trips', () {
            Navigator.pop(context);
            Get.to(() => const RideHistoryScreen());
          }),
          _menuItem(Icons.bookmark_border, 'Saved Places', () {
            Navigator.pop(context);
            Get.to(() => const SavedAddressesScreen());
          }),
        ];
      default:
        return [];
    }
  }

  ListTile _menuItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF10713C)),
      title: Text(title),
      onTap: onTap,
    );
  }
}
