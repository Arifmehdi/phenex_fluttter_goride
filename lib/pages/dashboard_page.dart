import '../main.dart';
import 'home_page.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import '../locale_controller.dart';
import '../registration_screens.dart' show OwnerProfileScreen;
import 'dashboard_details_pages.dart';
import '../services/api_service.dart';
import '../widgets/sidebar_menu.dart';

class UnifiedDashboard extends StatefulWidget {
  final String role; // 'driver', 'owner', 'corporate', 'admin'
  const UnifiedDashboard({super.key, required this.role});

  @override
  State<UnifiedDashboard> createState() => _UnifiedDashboardState();
}

class _UnifiedDashboardState extends State<UnifiedDashboard> {
  final LocaleController localeController = Get.find<LocaleController>();
  bool _isOnline = false;
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Scaffold(
        key: _scaffoldKey,
        appBar: _buildAppBar(),
        drawer: SidebarMenu(
          role: widget.role,
          onSelectedIndexChanged: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
        ),
        body: IndexedStack(
          index: _selectedIndex,
          children: [
            _buildHomeTab(),
            _buildSecondaryTab(), // 'Bids' for Driver, 'Fleet' for Owner/Corporate/Admin
            _buildEarningsTab(),
            _buildProfileTab(),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex + 1,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFF10713C),
          onTap: (index) {
            if (index == 0) {
              Get.offAll(() => HomePage());
            } else {
              setState(() => _selectedIndex = index - 1);
            }
          },
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.public),
              label: 'Portal',
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.dashboard),
              label: localeController.get('Home', 'হোম'),
            ),
            BottomNavigationBarItem(
              icon: Icon(
                widget.role == 'driver'
                    ? Icons.local_offer
                    : (widget.role == 'admin'
                          ? Icons.admin_panel_settings
                          : Icons.directions_car),
              ),
              label: widget.role == 'driver'
                  ? localeController.get('Bids', 'বিড')
                  : (widget.role == 'admin'
                        ? localeController.get('Admin', 'অ্যাডমিন')
                        : localeController.get('Fleet', 'বহর')),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.account_balance_wallet),
              label: localeController.get('Wallet', 'ওয়ালেট'),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.person),
              label: localeController.get('Profile', 'প্রোফাইল'),
            ),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    String title = '';
    if (widget.role == 'driver')
      title = localeController.get('Driver Dashboard', 'ড্রাইভার ড্যাশবোর্ড');
    if (widget.role == 'owner')
      title = localeController.get('Owner Dashboard', 'মালিক ড্যাশবোর্ড');
    if (widget.role == 'corporate')
      title = localeController.get(
        'Corporate Dashboard',
        'কর্পোরেট ড্যাশবোর্ড',
      );
    if (widget.role == 'admin')
      title = localeController.get('Admin Dashboard', 'অ্যাডমিন ড্যাশবোর্ড');

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.menu),
        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      backgroundColor: const Color(0xFF10713C),
      actions: [
        if (widget.role == 'driver')
          Row(
            children: [
              Text(
                _isOnline ? 'Online' : 'Offline',
                style: const TextStyle(fontSize: 12),
              ),
              Switch(
                value: _isOnline,
                onChanged: (v) => setState(() => _isOnline = v),
                activeColor: Colors.white,
                activeTrackColor: Colors.lightGreenAccent,
              ),
            ],
          ),
        IconButton(
          icon: const Icon(Icons.notifications_none),
          onPressed: () {},
        ),
        if (widget.role == 'admin')
          IconButton(icon: const Icon(Icons.settings), onPressed: () {}),
      ],
    );
  }

  Widget _buildHomeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWelcomeHeader(),
          const SizedBox(height: 20),
          if (widget.role != 'admin') _buildProgressTracker(),
          const SizedBox(height: 24),
          _buildStatsGrid(),
          const SizedBox(height: 24),
          if (widget.role == 'driver') _buildPendingBidsSection(),
          if (widget.role == 'owner') _buildCarStatusSection(),
          if (widget.role == 'corporate') _buildCorporateAlerts(),
          if (widget.role == 'admin') _buildAdminManagementSection(),
        ],
      ),
    );
  }

  Widget _buildWelcomeHeader() {
    String name = widget.role == 'corporate' ? 'TechCorp Ltd.' : 'Karim Ahmed';
    return Row(
      children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: const Color(0xFF10713C),
          child: Icon(
            widget.role == 'corporate' ? Icons.business : Icons.person,
            color: Colors.white,
            size: 30,
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${localeController.get('Hello', 'হ্যালো')}, $name',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              localeController.get(
                'Manage your business today',
                'আপনার ব্যবসা পরিচালনা করুন',
              ),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProgressTracker() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10713C).withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF10713C).withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                localeController.get('Profile Completion', 'প্রোফাইল সম্পন্ন'),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const Text(
                '65%',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF10713C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: const LinearProgressIndicator(
              value: 0.65,
              minHeight: 8,
              backgroundColor: Colors.white,
              valueColor: AlwaysStoppedAnimation(Color(0xFF10713C)),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            localeController.get(
              'Finish Phase 3 to start receiving trips',
              'ট্রিপ পাওয়া শুরু করতে ৩য় ধাপ শেষ করুন',
            ),
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    List<Map<String, dynamic>> stats = [];
    if (widget.role == 'driver') {
      stats = [
        {
          'label': localeController.get('Today Trips', 'আজকের ট্রিপ'),
          'value': '5',
          'icon': Icons.directions_car,
          'color': Colors.blue,
        },
        {
          'label': localeController.get('Rating', 'রেটিং'),
          'value': '4.9',
          'icon': Icons.star,
          'color': Colors.orange,
        },
        {
          'label': localeController.get('Total Earn', 'মোট আয়'),
          'value': '৳ 2.5k',
          'icon': Icons.payments,
          'color': Colors.green,
        },
        {
          'label': localeController.get('Cancelled', 'বাতিল'),
          'value': '0',
          'icon': Icons.cancel,
          'color': Colors.red,
        },
      ];
    } else if (widget.role == 'owner') {
      stats = [
        {
          'label': localeController.get('Total Cars', 'মোট গাড়ি'),
          'value': '3',
          'icon': Icons.directions_car,
          'color': Colors.blue,
        },
        {
          'label': localeController.get('Active', 'সক্রিয়'),
          'value': '2',
          'icon': Icons.check_circle,
          'color': Colors.green,
        },
        {
          'label': localeController.get('Drivers', 'ড্রাইভার'),
          'value': '3',
          'icon': Icons.people,
          'color': Colors.purple,
        },
        {
          'label': localeController.get('Revenue', 'মোট আয়'),
          'value': '৳ 45k',
          'icon': Icons.trending_up,
          'color': Colors.orange,
        },
      ];
    } else if (widget.role == 'corporate') {
      stats = [
        {
          'label': localeController.get('Active Rides', 'চলতি ট্রিপ'),
          'value': '8',
          'icon': Icons.map,
          'color': Colors.blue,
        },
        {
          'label': localeController.get('Fleet Size', 'মোট গাড়ি'),
          'value': '12',
          'icon': Icons.airport_shuttle,
          'color': Colors.indigo,
        },
        {
          'label': localeController.get('Unpaid Bill', 'বকেয়া বিল'),
          'value': '৳ 12k',
          'icon': Icons.receipt_long,
          'color': Colors.red,
        },
        {
          'label': localeController.get('Employees', 'কর্মচারী'),
          'value': '150',
          'icon': Icons.groups,
          'color': Colors.teal,
        },
      ];
    } else if (widget.role == 'admin') {
      stats = [
        {
          'label': localeController.get('Total Users', 'মোট ব্যবহারকারী'),
          'value': '1,250',
          'icon': Icons.people,
          'color': Colors.blue,
        },
        {
          'label': localeController.get('Active Drivers', 'সক্রিয় ড্রাইভার'),
          'value': '85',
          'icon': Icons.drive_eta,
          'color': Colors.green,
        },
        {
          'label': localeController.get('Total Trips', 'মোট ট্রিপ'),
          'value': '3,420',
          'icon': Icons.route,
          'color': Colors.purple,
        },
        {
          'label': localeController.get('Revenue', 'মোট আয়'),
          'value': '৳ 1.2M',
          'icon': Icons.account_balance,
          'color': Colors.orange,
        },
      ];
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.6,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: stats.length,
      itemBuilder: (context, index) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10),
          ],
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(
                  stats[index]['icon'],
                  size: 16,
                  color: stats[index]['color'],
                ),
                const SizedBox(width: 8),
                Text(
                  stats[index]['label'],
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              stats[index]['value'],
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingBidsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localeController.get('Live Market', 'মার্কেটপ্লেস'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _buildRequestCard('Airport to Uttara', '12 km', '৳ 600'),
        _buildRequestCard('Gulshan to Banani', '4 km', '৳ 250'),
      ],
    );
  }

  Widget _buildRequestCard(String route, String dist, String fare) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        title: Text(route, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('$dist • $fare'),
        trailing: ElevatedButton(
          onPressed: () {},
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10713C),
            minimumSize: const Size(60, 30),
          ),
          child: const Text(
            'Bid',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildCarStatusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              localeController.get('My Fleet Status', 'গাড়ির অবস্থা'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () {},
              child: Text(localeController.get('Add Car', 'গাড়ি যোগ করুন')),
            ),
          ],
        ),
        const ListTile(
          leading: Icon(Icons.directions_car, color: Colors.green),
          title: Text('Toyota Prius (DH-1234)'),
          subtitle: Text('On Trip - Dhaka City'),
        ),
        const ListTile(
          leading: Icon(Icons.directions_car, color: Colors.orange),
          title: Text('Honda Civic (DH-5678)'),
          subtitle: Text('Idle - Waiting for trip'),
        ),
      ],
    );
  }

  Widget _buildCorporateAlerts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localeController.get('Recent Monthly Bill', 'মাসিক বিল'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.red.shade100),
            borderRadius: BorderRadius.circular(12),
            color: Colors.red.shade50,
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.red),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'March 2026 invoice is pending. Please pay to avoid service interruption.',
                  style: TextStyle(fontSize: 12, color: Colors.red),
                ),
              ),
              TextButton(onPressed: () {}, child: const Text('Pay Now')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAdminManagementSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localeController.get('Management', 'ব্যবস্থাপনা'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _buildAdminCard(
          Icons.people,
          'User Management',
          'Manage drivers, owners & corporates',
          Colors.blue,
        ),
        _buildAdminCard(
          Icons.directions_car,
          'Vehicle Management',
          'Approve & manage vehicles',
          Colors.green,
        ),
        _buildAdminCard(
          Icons.payment,
          'Payment Management',
          'View transactions & payouts',
          Colors.orange,
        ),
        _buildAdminCard(
          Icons.support_agent,
          'Support Tickets',
          '15 pending tickets',
          Colors.red,
        ),
        _buildAdminCard(
          Icons.analytics,
          'Reports & Analytics',
          'View detailed analytics',
          Colors.purple,
        ),
        _buildAdminCard(
          Icons.settings,
          'System Settings',
          'App configuration',
          Colors.teal,
        ),
      ],
    );
  }

  Widget _buildAdminCard(
    IconData icon,
    String title,
    String subtitle,
    Color color,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: () => _navigateToAdminPage(title),
      ),
    );
  }

  void _navigateToAdminPage(String title) {
    Widget screen;
    switch (title) {
      case 'User Management':
        screen = const UserManagementScreen();
        break;
      case 'Vehicle Management':
        screen = const VehicleManagementScreen();
        break;
      case 'Payment Management':
        screen = const PaymentManagementScreen();
        break;
      case 'Support Tickets':
        screen = const SupportTicketsScreen();
        break;
      case 'Reports & Analytics':
        screen = const ReportsAnalyticsScreen();
        break;
      case 'System Settings':
        screen = const SystemSettingsScreen();
        break;
      default:
        return;
    }
    Get.to(() => screen);
  }

  Widget _buildSecondaryTab() {
    return Center(
      child: Text(
        widget.role == 'driver'
            ? 'No Active Bids'
            : 'Fleet Management Full View Coming Soon',
      ),
    );
  }

  Widget _buildEarningsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF10713C), Color(0xFF0D5A30)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Text(
                  localeController.get('Balance', 'ব্যালেন্স'),
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 8),
                const Text(
                  '৳ 14,250.00',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF10713C),
                  ),
                  child: Text(
                    localeController.get('Withdraw to bKash', 'বিকাশে উত্তোলন'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildTransactionItem('Trip #4521', '৳ 450', 'Success'),
          _buildTransactionItem('Withdrawal', '-৳ 2000', 'Pending'),
          _buildTransactionItem('Trip #4518', '৳ 320', 'Success'),
        ],
      ),
    );
  }

  Widget _buildTransactionItem(String title, String amt, String status) {
    return ListTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(status),
      trailing: Text(
        amt,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: amt.startsWith('-') ? Colors.red : Colors.green,
        ),
      ),
    );
  }

  Widget _buildProfileTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _profileMenuItem(
          Icons.person_outline,
          localeController.get('Edit Profile', 'প্রোফাইল এডিট'),
          onTap: () => Get.to(() => const EditProfileScreen()),
        ),
        _profileMenuItem(
          Icons.document_scanner_outlined,
          localeController.get('Documents', 'নথিপত্র'),
          onTap: () => Get.to(() => const DocumentsScreen()),
        ),
        _profileMenuItem(
          Icons.directions_car_filled_outlined,
          localeController.get('My Vehicles', 'আমার গাড়ি'),
          onTap: () => Get.to(() => const MyVehiclesScreen()),
        ),
        _profileMenuItem(
          Icons.history,
          localeController.get('Trip History', 'ট্রিপ হিস্ট্রি'),
          onTap: () => Get.to(() => const TripHistoryScreen()),
        ),
        _profileMenuItem(
          Icons.settings_outlined,
          localeController.get('Settings', 'সেটিংস'),
          onTap: () {},
        ),
        const Divider(),
        _profileMenuItem(
          Icons.logout,
          localeController.get('Logout', 'লগআউট'),
          color: Colors.red,
          onTap: () async {
            final apiService = Get.find<ApiService>();
            await apiService.logout();
            Get.offAll(() => const SplashScreen());
          },
        ),
      ],
    );
  }

  Widget _profileMenuItem(
    IconData icon,
    String title, {
    Color color = Colors.black87,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
      onTap: onTap,
    );
  }
}

