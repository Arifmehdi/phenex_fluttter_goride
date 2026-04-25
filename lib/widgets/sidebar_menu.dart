import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/api_service.dart';
import '../main.dart';
import '../pages/home_page.dart';

class SidebarMenu extends StatelessWidget {
  final String role;
  const SidebarMenu({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    final ApiService apiService = Get.find<ApiService>();
    final user = apiService.getUser();
    final name = user?['name'] ?? 'Guest User';
    final mobile = user?['mobile'] ?? '';

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(
              color: Color(0xFF10713C),
            ),
            currentAccountPicture: const CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.person, size: 40, color: Color(0xFF10713C)),
            ),
            accountName: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            accountEmail: Text(mobile),
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
            leading: const Icon(Icons.settings, color: Colors.grey),
            title: const Text('Settings'),
            onTap: () {
              // Navigate to settings
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.help, color: Colors.grey),
            title: const Text('Help & Support'),
            onTap: () {
              // Navigate to help
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout'),
            onTap: () async {
              await apiService.logout();
              Get.offAll(() => const SplashScreen());
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _buildRoleSpecificMenus(BuildContext context) {
    switch (role) {
      case 'driver':
        return [
          _menuItem(Icons.dashboard, 'Dashboard', () => Navigator.pop(context)),
          _menuItem(Icons.local_offer, 'My Bids', () => Navigator.pop(context)),
          _menuItem(Icons.directions_car, 'My Vehicle', () => Navigator.pop(context)),
          _menuItem(Icons.trending_up, 'Earnings', () => Navigator.pop(context)),
          _menuItem(Icons.history, 'Trip History', () => Navigator.pop(context)),
        ];
      case 'owner':
        return [
          _menuItem(Icons.dashboard, 'Dashboard', () => Navigator.pop(context)),
          _menuItem(Icons.directions_car, 'My Fleet', () => Navigator.pop(context)),
          _menuItem(Icons.people, 'Driver Management', () => Navigator.pop(context)),
          _menuItem(Icons.account_balance_wallet, 'Earnings', () => Navigator.pop(context)),
        ];
      case 'corporate':
        return [
          _menuItem(Icons.dashboard, 'Dashboard', () => Navigator.pop(context)),
          _menuItem(Icons.business, 'Company Fleet', () => Navigator.pop(context)),
          _menuItem(Icons.receipt, 'Billing & Invoices', () => Navigator.pop(context)),
          _menuItem(Icons.group, 'Employee Management', () => Navigator.pop(context)),
        ];
      case 'admin':
        return [
          _menuItem(Icons.admin_panel_settings, 'Admin Panel', () => Navigator.pop(context)),
          _menuItem(Icons.people, 'User Management', () => Navigator.pop(context)),
          _menuItem(Icons.bar_chart, 'Reports', () => Navigator.pop(context)),
          _menuItem(Icons.settings_applications, 'Platform Settings', () => Navigator.pop(context)),
        ];
      case 'solo': // Rider
        return [
          _menuItem(Icons.home, 'Home', () => Navigator.pop(context)),
          _menuItem(Icons.history, 'My Trips', () => Navigator.pop(context)),
          _menuItem(Icons.payment, 'Payments', () => Navigator.pop(context)),
          _menuItem(Icons.card_giftcard, 'Promos', () => Navigator.pop(context)),
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
