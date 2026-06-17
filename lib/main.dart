import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:dio/dio.dart';
import 'package:goride/locale_controller.dart';
import 'package:goride/registration_screens.dart';
import 'package:goride/pages/home_page.dart';
import 'package:goride/pages/dashboard_page.dart';
import 'package:goride/pages/approval_pending_screen.dart';
import 'package:goride/approval_helper.dart';
import 'package:goride/pages/location_selection_screen.dart';
import 'package:goride/pages/rent_car_booking_screen.dart';
import 'package:goride/services/api_service.dart';
import 'package:goride/services/firebase_service.dart';
import 'package:goride/services/location_service.dart';
import 'package:goride/services/notification_service.dart';
import 'package:goride/services/ride_service.dart';
import 'package:goride/services/routing_service.dart';
import 'package:goride/services/sslcommerz_service.dart';
import 'package:goride/pages/login_page.dart';
import 'package:goride/pages/register_screen.dart';
import 'package:goride/pages/forgot_password_screen.dart';
import 'package:goride/pages/reset_password_screen.dart';
import 'package:goride/widgets/sidebar_menu.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();

  // Initialize core services
  Get.put(ApiService());
  Get.put(LocaleController());
  Get.put(SslCommerzService());

  // Initialize Firebase for real-time features
  final firebaseService = Get.put(FirebaseService());
  // Start initialization in background, but await it briefly for critical startup
  await firebaseService.init().timeout(const Duration(seconds: 10), onTimeout: () {
    debugPrint('Firebase initialization timed out, continuing...');
  });

  // Initialize location & ride services
  final locationService = Get.put(LocationService());
  locationService.initFirebase(firebaseService);
  
  Get.put(RideService());
  Get.put(RoutingService());

  // Initialize notification service for ride request alerts
  final notificationService = NotificationService();
  await notificationService.init();
  try {
    // Request Android 13+ notification permission
    await notificationService.requestPermission();
  } catch (e) {
    debugPrint('Notification permission request error: $e');
  }

  runApp(const GoRideApp());
}

class GoRideApp extends StatelessWidget {
  const GoRideApp({Key? key}) : super(key: key);

  static const String splashRoute = '/';

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'GoRide',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF10713C),
        secondaryHeaderColor: const Color(0xFFED1C24),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF10713C),
          foregroundColor: Colors.white,
        ),
      ),
      initialRoute: splashRoute,
      getPages: [
        GetPage(name: splashRoute, page: () => const SplashScreen()),
        GetPage(name: '/home', page: () => const HomePage()),
        GetPage(name: '/login', page: () => const LoginPage()),
        GetPage(name: '/registration', page: () => const RegisterScreen()),
        GetPage(name: '/forgot-password', page: () => const ForgotPasswordScreen()),
        GetPage(name: '/reset-password', page: () => const ResetPasswordScreen()),
      ],
    );
  }

  static Widget getDashboardForRole(String? role) {
    switch (role) {
      case 'admin':
        return const UnifiedDashboard(role: 'admin');
      case 'corporate':
        return const UnifiedDashboard(role: 'corporate');
      case 'owner':
        return const UnifiedDashboard(role: 'owner');
      case 'driver':
        return const UnifiedDashboard(role: 'driver');
      case 'user':
      case 'solo':
        return const HomePage();
      default:
        // If role is unknown but logged in, show home as default
        return const HomePage();
    }
  }
}

// ============== SPLASH SCREEN ==============
class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final ApiService _apiService = Get.find<ApiService>();

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  void _checkSession() {
    final ApiService apiService = Get.find<ApiService>();
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;

      if (apiService.isLoggedIn()) {
        final user = apiService.getUser();
        final role = apiService.getToken() != null ? (GetStorage().read('role') as String?) : null;
        final bool isApproved = GetStorage().read('is_approved') ?? true;
        final storedUser = apiService.getUser();
        
        if (role != null && (role == 'admin' || role == 'driver' || role == 'corporate' || role == 'owner')) {
          // Check approval from stored is_approved AND user status as fallback
          final isPending = !isApproved || (storedUser != null && (storedUser['status'] == 0 || storedUser['status'] == '0' || storedUser['status'] == 'pending'));
          if (isPending) {
            Get.offAll(() => ApprovalPendingScreen(role: role));
          } else {
            Get.offAll(() => GoRideApp.getDashboardForRole(role));
          }
        } else {
          Get.offAll(() => const HomePage());
        }
      } else {
        Get.offAll(() => const LoginPage());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: const Color(0xFF10713C),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top section - Logo, Title, Slogan
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/go_ride_logo.png',
                        height: 100,
                        width: 100,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.directions_car,
                            size: 80,
                            color: Colors.white,
                          );
                        },
                      ),
                      const SizedBox(height: 30),
                      const Text(
                        'GoRide',
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Your Journey, Our Priority',
                        style: TextStyle(fontSize: 16, color: Colors.white70),
                      ),
                      const SizedBox(height: 40),
                      const CircularProgressIndicator(color: Colors.white),
                    ],
                  ),
                ),
              ),
              // Footer at bottom
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: const Text(
                  '© 2026 Phenexsoft IT. All rights reserved.',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============== ROLE SELECTION SCREEN ==============
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Your Role'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'How would you like to use GoRide?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            _roleCard(
              context,
              icon: Icons.person,
              title: 'Book a Ride',
              description: 'Find and book rides easily',
              onTap: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const RiderHomeScreen()),
              ),
            ),
            const SizedBox(height: 20),
            _roleCard(
              context,
              icon: Icons.drive_eta,
              title: 'Rider',
              description: 'Earn by driving your own car',
              onTap: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => const UnifiedDashboard(role: 'driver'),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _roleCard(
              context,
              icon: Icons.car_rental,
              title: 'Car Owner',
              description: 'Manage your fleet of cars',
              onTap: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => const UnifiedDashboard(role: 'owner'),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _roleCard(
              context,
              icon: Icons.business,
              title: 'Corporate',
              description: 'Manage fleet and billing',
              onTap: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => const UnifiedDashboard(role: 'corporate'),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _roleCard(
              context,
              icon: Icons.admin_panel_settings,
              title: 'Admin',
              description: 'Manage platform & users',
              onTap: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => const UnifiedDashboard(role: 'admin'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _roleCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 4,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF10713C), width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, size: 50, color: const Color(0xFF10713C)),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      description,
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward, color: Color(0xFF10713C)),
            ],
          ),
        ),
      ),
    );
  }
}

// ============== RIDER HOME SCREEN ==============
class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({Key? key}) : super(key: key);

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  int _selectedIndex = 0;
  final ApiService _apiService = Get.find<ApiService>();

  @override
  Widget build(BuildContext context) {
    final user = _apiService.getUser();
    final name = user?['name']?.split(' ')[0] ?? 'User';

    return Scaffold(
      drawer: SidebarMenu(
        role: 'solo',
        onSelectedIndexChanged: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
      ),
      appBar: AppBar(
        backgroundColor: const Color(0xFF10713C),
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_open, color: Colors.white, size: 28),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text(
          'Hello, $name',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded, color: Colors.white),
            onPressed: () {},
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          SingleChildScrollView(child: _buildModernBookingTab()),
          SingleChildScrollView(child: _buildHistoryTab()),
          SingleChildScrollView(child: _buildProfileTab()),
        ],
      ),
      bottomNavigationBar: _buildModernBottomNav(),
    );
  }

  Widget _buildModernBottomNav() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex + 1,
        elevation: 0,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF10713C),
        unselectedItemColor: Colors.grey[400],
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        onTap: (index) {
          if (index == 0) {
            Get.offAll(() => HomePage());
          } else {
            setState(() => _selectedIndex = index - 1);
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: 'Portal'),
          BottomNavigationBarItem(icon: Icon(Icons.explore_rounded), label: 'Explore'),
          BottomNavigationBarItem(icon: Icon(Icons.history_rounded), label: 'Trips'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline_rounded), label: 'Account'),
        ],
      ),
    );
  }

  void _showLocationPopup(BuildContext context, {String? rideType}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Material(
        color: Colors.transparent,
        child: LocationSelectionScreen(initialRideType: rideType),
      ),
    );
  }

  void _showRideTypeSelection(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Material(
        color: Colors.transparent,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Select Ride Type',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF10713C),
                ),
              ),
              const Text(
                'Choose how you want to travel today',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: _buildRideTypeCard(
                      context,
                      title: 'Car',
                      subtitle: 'Comfortable trips',
                      icon: Icons.directions_car,
                      color: const Color(0xFF10713C),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildRideTypeCard(
                      context,
                      title: 'Bike',
                      subtitle: 'Faster in traffic',
                      icon: Icons.two_wheeler,
                      color: const Color(0xFFED1C24),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildRideTypeListItem(
                context,
                title: 'Rent a Car',
                subtitle: 'For long trips and outstation',
                icon: Icons.car_rental,
                color: Colors.blue,
                onTap: () {
                  Navigator.pop(context);
                  _showRentCarTypeSelection(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRideTypeCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        _showLocationPopup(context, rideType: title);
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRideTypeListItem(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.all(12),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
      ),
    );
  }

  Widget _buildModernBookingTab() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search/Booking Bar
          GestureDetector(
            onTap: () => _showRideTypeSelection(context),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
                border: Border.all(color: Colors.grey.shade100),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Color(0xFF10713C), size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Where to go?',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          'Select your ride type',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10713C).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Search',
                      style: TextStyle(
                        color: Color(0xFF10713C),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          
          const Text(
            'Vehicle Categories',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildCategoryGrid(),
          
          const SizedBox(height: 32),
          const Text(
            'Quick Actions',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildQuickActionCard('Airport', Icons.local_airport, const Color(0xFF10713C))),
              const SizedBox(width: 16),
              Expanded(child: _buildQuickActionCard('Hourly', Icons.timer, const Color(0xFFED1C24))),
              const SizedBox(width: 16),
              Expanded(child: _buildQuickActionCard('Intercity', Icons.location_city, Colors.blue)),
            ],
          ),
          
          const SizedBox(height: 32),
          _buildPromoBanner(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showRentCarTypeSelection(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Material(
        color: Colors.transparent,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Rent a Car',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF10713C),
                ),
              ),
              const Text(
                'Choose the trip type that fits your needs',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: _buildRentalTypeCard(
                      context,
                      title: 'One Way',
                      subtitle: 'Without Return',
                      icon: Icons.trending_flat,
                      color: const Color(0xFF10713C),
                      isWithReturn: false,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildRentalTypeCard(
                      context,
                      title: 'Round Trip',
                      subtitle: 'With Return',
                      icon: Icons.sync,
                      color: const Color(0xFFED1C24),
                      isWithReturn: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRentalTypeCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isWithReturn,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RentCarBookingScreen(initialWithReturn: isWithReturn),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryGrid() {
    final List<Map<String, dynamic>> categories = [
      {'name': 'Car', 'subtitle': 'Daily commute', 'icon': Icons.directions_car, 'color': const Color(0xFF10713C)},
      {'name': 'Bike', 'subtitle': 'Quick & fast', 'icon': Icons.two_wheeler, 'color': const Color(0xFFED1C24)},
      {'name': 'Rent Car', 'subtitle': 'Long trips', 'icon': Icons.car_rental, 'color': Colors.blue},
      {'name': 'Parcel', 'subtitle': 'Send items', 'icon': Icons.inventory_2_outlined, 'color': Colors.amber[800]},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.4,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final cat = categories[index];
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                color: (cat['color'] as Color).withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                if (cat['name'] == 'Rent Car') {
                  _showRentCarTypeSelection(context);
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LocationSelectionScreen(initialRideType: cat['name']),
                    ),
                  );
                }
              },
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (cat['color'] as Color).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(cat['icon'], color: cat['color'], size: 24),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cat['name'],
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          cat['subtitle'],
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickActionCard(String title, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromoBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF10713C), Color(0xFF1D9755)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        image: DecorationImage(
          image: const AssetImage('assets/banner/banner_01.jpg'),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            const Color(0xFF10713C).withOpacity(0.8),
            BlendMode.darken,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFED1C24),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'PROMO',
              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '30% OFF on your\nfirst 3 intercity trips',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF10713C),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Claim Offer'),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Trip History',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () {},
              child: const Text('View All', style: TextStyle(color: Color(0xFF10713C))),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _tripCard('Dhaka Airport → Gulshan', '৳ 450', '30 mins', 'Completed', Icons.check_circle_rounded, Colors.green),
        _tripCard('Motijheel → Mirpur', '৳ 280', '25 mins', 'Completed', Icons.check_circle_rounded, Colors.green),
        _tripCard('Banani → Dhanmondi', '৳ 320', '20 mins', 'Cancelled', Icons.cancel_rounded, Colors.red),
      ],
    );
  }

  Widget _tripCard(String route, String price, String time, String status, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  route,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              Text(
                price,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF10713C)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.access_time_filled, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(time, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
              Text(
                status,
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfileTab() {
    final user = _apiService.getUser();
    final name = user?['name'] ?? 'User';
    final email = user?['email'] ?? 'user@example.com';

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                Stack(
                  children: [
                    const CircleAvatar(
                      radius: 45,
                      backgroundColor: Color(0xFF10713C),
                      child: Icon(Icons.person, size: 45, color: Colors.white),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Color(0xFFED1C24), shape: BoxShape.circle),
                        child: const Icon(Icons.edit, color: Colors.white, size: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                Text(
                  email,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildUserStat('4.9', 'Rating'),
                    _buildUserStat('124', 'Trips'),
                    _buildUserStat('৳2.4k', 'Saved'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _profileMenuTile(Icons.wallet_rounded, 'GoRide Wallet', '৳ 1,250.00'),
          _profileMenuTile(Icons.card_giftcard_rounded, 'Promotions', '3 available'),
          _profileMenuTile(Icons.support_agent_rounded, 'Help & Support', ''),
          _profileMenuTile(Icons.settings_suggest_rounded, 'Settings', ''),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () async {
                await _apiService.logout();
                Get.offAll(() => const SplashScreen());
              },
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFED1C24),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Logout Account', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserStat(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF10713C))),
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      ],
    );
  }

  Widget _profileMenuTile(IconData icon, String title, String trailing) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: const Color(0xFF10713C), size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailing.isNotEmpty)
            Text(
              trailing,
              style: const TextStyle(color: Color(0xFF10713C), fontWeight: FontWeight.bold, fontSize: 13),
            ),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
        ],
      ),
      onTap: () {},
    );
  }
}

// ============== BOOKING FORM SCREEN ==============
class BookingFormScreen extends StatefulWidget {
  const BookingFormScreen({Key? key}) : super(key: key);

  @override
  State<BookingFormScreen> createState() => _BookingFormScreenState();
}

class _BookingFormScreenState extends State<BookingFormScreen> {
  String selectedCarType = 'Sedan';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Book a Ride')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Trip Details',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildInputField('Pickup Location', 'Enter pickup location'),
              const SizedBox(height: 12),
              _buildInputField('Destination', 'Enter destination'),
              const SizedBox(height: 12),
              _buildInputField('Date & Time', '10 April 2026, 2:00 PM'),
              const SizedBox(height: 12),
              _buildInputField('Passengers', '2'),
              const SizedBox(height: 24),
              const Text(
                'Select Car Type',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: [
                  _selectableCarType('Sedan', '৳50/km'),
                  _selectableCarType('SUV', '৳70/km'),
                  _selectableCarType('Microbus', '৳40/km'),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Estimated Fare',
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '৳ 450',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFED1C24),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Distance: 15 km | Duration: 30 mins',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const BookingConfirmationScreen(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10713C),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'Confirm Booking',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputField(String label, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          decoration: InputDecoration(
            hintText: hint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Icon(
              label.contains('Location')
                  ? Icons.location_on
                  : label.contains('Destination')
                  ? Icons.flag
                  : label.contains('Time')
                  ? Icons.access_time
                  : Icons.people,
            ),
          ),
        ),
      ],
    );
  }

  Widget _selectableCarType(String name, String price) {
    bool isSelected = selectedCarType == name;
    return GestureDetector(
      onTap: () => setState(() => selectedCarType = name),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? const Color(0xFF10713C) : Colors.grey,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected
              ? const Color(0xFF10713C).withOpacity(0.1)
              : Colors.white,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.directions_car,
              color: isSelected ? const Color(0xFF10713C) : Colors.grey,
              size: 30,
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected ? const Color(0xFF10713C) : Colors.grey,
                fontSize: 12,
              ),
            ),
            Text(
              price,
              style: const TextStyle(fontSize: 10, color: Color(0xFFED1C24)),
            ),
          ],
        ),
      ),
    );
  }
}

// ============== BOOKING CONFIRMATION SCREEN ==============
class BookingConfirmationScreen extends StatelessWidget {
  const BookingConfirmationScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking Confirmed'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 80, color: Color(0xFF10713C)),
            const SizedBox(height: 24),
            const Text(
              'Booking Confirmed!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Your ride has been confirmed',
              style: TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Booking ID:', style: TextStyle(fontSize: 14)),
                      const Text(
                        'GR-2026-0410-001',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Pickup:', style: TextStyle(fontSize: 14)),
                      const Text(
                        'Dhaka Airport',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Destination:',
                        style: TextStyle(fontSize: 14),
                      ),
                      const Text(
                        'Gulshan 2',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Est. Fare:', style: TextStyle(fontSize: 14)),
                      const Text(
                        '৳ 450',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFED1C24),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.chat),
                label: const Text('Contact via WhatsApp'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const RiderHomeScreen()),
                  );
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Back to Home'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============== DRIVER DASHBOARD SCREEN ==============
class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({Key? key}) : super(key: key);

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  final ApiService _apiService = Get.find<ApiService>();
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: SidebarMenu(
        role: 'driver',
        onSelectedIndexChanged: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
      ),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: const Text('Rider Dashboard'),
        actions: [
          IconButton(icon: const Icon(Icons.notifications), onPressed: () {}),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildDashboardTab(),
          _buildCarsTab(),
          _buildEarningsTab(),
          _buildProfileTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex + 1,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF10713C),
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          if (index == 0) {
            Get.offAll(() => HomePage());
          } else {
            setState(() => _selectedIndex = index - 1);
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.public), label: 'Portal'),
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.directions_car),
            label: 'Cars',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.trending_up),
            label: 'Earnings',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _buildDashboardTab() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              radius: 40,
              backgroundColor: Color(0xFF10713C),
              child: Icon(Icons.person, size: 40, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Welcome, ${_apiService.getUser()?['name'] ?? 'User'}!',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // Stats cards
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _statCard('Trips', '24', const Color(0xFF10713C)),
                _statCard('Rating', '4.8', const Color(0xFFED1C24)),
                _statCard('Earnings', '৳ 8,500', Colors.orange),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Profile Completion',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: 0.85,
                minHeight: 10,
                backgroundColor: Colors.grey[300],
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF10713C),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '85% Complete - Upload remaining documents',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            const Text(
              'Pending Tasks',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _taskCard('Upload Insurance Document', Icons.file_present),
            _taskCard('Vehicle Registration', Icons.note),
            _taskCard('License Verification', Icons.verified_user),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10713C),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'Go Online',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String title, String value, Color color) {
    return Expanded(
      child: Card(
        elevation: 0,
        color: color.withOpacity(0.1),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(title, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _taskCard(String title, IconData icon) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF10713C)),
            const SizedBox(width: 12),
            Expanded(child: Text(title)),
            const Icon(Icons.arrow_forward, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildCarsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            'My Cars',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        _carCard(
          'Toyota Prius',
          'DH-1234',
          'Active',
          Icons.check_circle,
          Colors.green,
        ),
        _carCard(
          'Honda Civic',
          'DH-5678',
          'Inactive',
          Icons.pause_circle,
          Colors.orange,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add),
            label: const Text('Add New Car'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10713C),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _carCard(
    String name,
    String plate,
    String status,
    IconData icon,
    Color statusColor,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Plate: $plate',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Icon(icon, color: statusColor),
                    const SizedBox(width: 8),
                    Text(
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.image),
                    label: const Text('Photos'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEarningsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            'Earnings',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF10713C),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total Earnings', style: TextStyle(color: Colors.white70)),
              SizedBox(height: 8),
              Text(
                '৳ 24,500',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 8),
              Text('This Month', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Recent Trips',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _earningCard('Dhaka City → Gulshan', '৳ 450', '+4.8★'),
        _earningCard('Airport → Dhanmondi', '৳ 520', '+5.0★'),
        _earningCard('Motijheel → Banani', '৳ 380', '+4.7★'),
      ],
    );
  }

  Widget _earningCard(String trip, String amount, String rating) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trip, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  rating,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            Text(
              amount,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFFED1C24),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 24),
          child: Center(
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 50,
                  backgroundColor: Color(0xFF10713C),
                  child: Icon(Icons.person, size: 50, color: Colors.white),
                ),
                const SizedBox(height: 16),
                Text(
                  _apiService.getUser()?['name'] ?? 'User',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text('+880 1700-000000', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ),
        _profileOption(Icons.edit, 'Edit Profile'),
        _profileOption(Icons.document_scanner, 'Documents'),
        _profileOption(Icons.payment, 'Payment Methods'),
        _profileOption(Icons.history, 'Trip History'),
        _profileOption(Icons.help, 'Help & Support'),
        const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                final apiService = Get.find<ApiService>();
                await apiService.logout();
                Get.offAll(() => const SplashScreen());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFED1C24),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                'Logout',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _profileOption(IconData icon, String title) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF10713C)),
      title: Text(title),
      trailing: const Icon(Icons.arrow_forward, color: Colors.grey),
      onTap: () {},
    );
  }
}

// ============== CORPORATE DASHBOARD SCREEN ==============
class CorporateDashboardScreen extends StatefulWidget {
  const CorporateDashboardScreen({Key? key}) : super(key: key);

  @override
  State<CorporateDashboardScreen> createState() =>
      _CorporateDashboardScreenState();
}

class _CorporateDashboardScreenState extends State<CorporateDashboardScreen> {
  final ApiService _apiService = Get.find<ApiService>();
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: SidebarMenu(
        role: 'corporate',
        onSelectedIndexChanged: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
      ),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: const Text('Corporate Dashboard'),
        actions: [
          IconButton(icon: const Icon(Icons.notifications), onPressed: () {}),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildDashboardTab(),
          _buildFleetTab(),
          _buildBillingTab(),
          _buildProfileTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex + 1,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF10713C),
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          if (index == 0) {
            Get.offAll(() => HomePage());
          } else {
            setState(() => _selectedIndex = index - 1);
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.public), label: 'Portal'),
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_shipping),
            label: 'Fleet',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.receipt), label: 'Billing'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _buildDashboardTab() {
    final user = _apiService.getUser();
    final companyName = user?['name'] ?? 'TechCorp Ltd.';
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              companyName,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // Stats grid
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: [
                _corporateStatCard(
                  'Active Cars',
                  '12',
                  const Color(0xFF10713C),
                ),
                _corporateStatCard('Riders', '15', Colors.blue),
                _corporateStatCard('Pending Trips', '8', Colors.orange),
                _corporateStatCard(
                  'This Month Bill',
                  '৳ 45,000',
                  const Color(0xFFED1C24),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Billing Summary',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('This Month:'),
                      const Text(
                        '৳ 45,000',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFED1C24),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Status:'),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Paid',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10713C),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'Request New Car',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _corporateStatCard(String title, String value, Color color) {
    return Card(
      elevation: 0,
      color: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFleetTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            'Fleet Management',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        _fleetCard('Toyota Prius', 'Karim Ahmed', 'DH-1234', 'Active'),
        _fleetCard('Honda Civic', 'Rahim Khan', 'DH-5678', 'Active'),
        _fleetCard('Nissan Leaf', 'Jamal Singh', 'DH-9012', 'In Review'),
        _fleetCard('Toyota Innova', 'Rashed Ahmed', 'DH-3456', 'Active'),
      ],
    );
  }

  Widget _fleetCard(String car, String driver, String plate, String status) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  car,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: status == 'Active'
                        ? Colors.green.withOpacity(0.2)
                        : Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: status == 'Active' ? Colors.green : Colors.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Rider: $driver', style: const TextStyle(fontSize: 12)),
            Text('Plate: $plate', style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildBillingTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            'Invoices',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        _invoiceCard('INV-2026-0410-001', '৳ 45,000', 'March 2026', 'Paid'),
        _invoiceCard('INV-2026-0320-001', '৳ 42,500', 'February 2026', 'Paid'),
        _invoiceCard('INV-2026-0220-001', '৳ 48,000', 'January 2026', 'Paid'),
        _invoiceCard('INV-2025-1220-001', '৳ 50,000', 'December 2025', 'Paid'),
      ],
    );
  }

  Widget _invoiceCard(String id, String amount, String period, String status) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      id,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      period,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      amount,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFED1C24),
                      ),
                    ),
                    Text(
                      status,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.download),
                  label: const Text('Download'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileTab() {
    final user = _apiService.getUser();
    final companyName = user?['name'] ?? 'TechCorp Ltd.';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 24),
          child: Center(
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 50,
                  backgroundColor: Color(0xFF10713C),
                  child: Icon(Icons.business, size: 50, color: Colors.white),
                ),
                const SizedBox(height: 16),
                Text(
                  companyName,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text('Corporate Account', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ),
        _profileOption(Icons.edit, 'Edit Company Info'),
        _profileOption(Icons.account_box, 'Account Manager'),
        _profileOption(Icons.payment, 'Payment Methods'),
        _profileOption(Icons.receipt, 'Tax Info'),
        _profileOption(Icons.help, 'Help & Support'),
        const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                final apiService = Get.find<ApiService>();
                await apiService.logout();
                Get.offAll(() => const SplashScreen());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFED1C24),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                'Logout',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _profileOption(IconData icon, String title) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF10713C)),
      title: Text(title),
      trailing: const Icon(Icons.arrow_forward, color: Colors.grey),
      onTap: () {},
    );
  }
}
