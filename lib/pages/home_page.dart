import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/places_service.dart';

import 'quick_action_screens.dart';
import 'location_selection_screen.dart';
import 'rent_car_booking_screen.dart';
import 'dashboard_page.dart';
import 'dashboard_details_pages.dart' show EditProfileScreen;
import 'my_support_tickets_screen.dart';
import 'rewards_screen.dart';
import 'ride_history_screen.dart';
import 'saved_addresses_screen.dart';
import '../main.dart' show GoRideApp, SplashScreen;
import 'register_screen.dart';
import 'login_page.dart';
import 'notifications_screen.dart';
import '../widgets/ongoing_ride_banner.dart';
import '../widgets/customer_drawer.dart';
import '../utils/notification_permission_prompt.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  late PageController _bannerPageController;
  int _currentBannerPage = 0;

  /// Number of banner slides currently shown — DB banners when present,
  /// otherwise the fallback assets. Auto-scroll and the PageView must use
  /// this same value, never a hardcoded count.
  int get _bannerCount =>
      _apiBanners.isNotEmpty ? _apiBanners.length : _fallbackBanners.length;
  List<Map<String, dynamic>> _apiBanners = [];
  static const List<String> _fallbackBanners = [
    'assets/banner/banner_01.jpg',
    'assets/banner/banner_02.jpg',
    'assets/banner/banner_03.jpg',
  ];

  // Current location detected on the home page
  String _currentLocationText = 'Detecting location...';
  double? _currentLat;
  double? _currentLng;
  bool _isRefreshingLocation = false;
  StreamSubscription<ServiceStatus>? _serviceStatusSubscription;

  // Opens the passenger drawer from the Account (dashboard) tab's ☰ button.
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isDrawerOpen = false;

  // Customer dashboard data (Account tab)
  Map<String, dynamic>? _riderStats;
  List<Map<String, dynamic>> _recentTrips = [];
  bool _statsLoading = true;

  final List<ServiceItem> services = [
    ServiceItem(
      title: 'Car',
      imagePath: 'assets/car.png',
      icon: Icons.directions_car,
    ),
    ServiceItem(
      title: 'Bike',
      imagePath: 'assets/motor.png',
      icon: Icons.two_wheeler,
    ),
    ServiceItem(
      title: 'Ambulance',
      imagePath: 'assets/ambulance.png', // Assuming assets/ambulance.png might be added or used icon
      icon: Icons.medical_services,
    ),
    ServiceItem(
      title: 'Corporate',
      imagePath: 'assets/corporate.png',
      icon: Icons.business,
    ),
    ServiceItem(
      title: 'Rent Car',
      imagePath: 'assets/rent_car.png',
      icon: Icons.domain,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _bannerPageController = PageController();
    _startAutoScroll();
    _detectCurrentLocation();
    _loadBanners();
    _loadRiderStats();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) primeNotificationPermissions(context);
    });

    // Listen for location service status changes (enabled/disabled)
    _serviceStatusSubscription = Geolocator.getServiceStatusStream().listen((ServiceStatus status) {
      if (status == ServiceStatus.enabled) {
        // Automatically refresh location when user turns it on
        _detectCurrentLocation();
      } else if (status == ServiceStatus.disabled) {
        if (mounted) {
          setState(() {
            _currentLocationText = 'Location off';
            _currentLat = null;
            _currentLng = null;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _bannerPageController.dispose();
    _serviceStatusSubscription?.cancel();
    super.dispose();
  }

  void _startAutoScroll() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _bannerPageController.hasClients) {
        final count = _bannerCount;
        // With 0/1 slides there is nothing to scroll — just keep the loop alive
        // so it resumes if banners load later.
        if (count > 1) {
          final nextPage = (_bannerPageController.page!.round() + 1) % count;
          _bannerPageController.animateToPage(
            nextPage,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
        _startAutoScroll();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      // Inner Scaffold hosts the drawer so it opens BELOW the app bar, keeping
      // the hamburger/app bar visible on top for the open/close toggle.
      body: Scaffold(
        key: _scaffoldKey,
        onDrawerChanged: (isOpen) {
          if (mounted) setState(() => _isDrawerOpen = isOpen);
        },
        drawer: CustomerDrawer(
          onSelectTab: (index) => setState(() => _selectedIndex = index),
        ),
        body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildHomeTab(context),
          _buildServicesTab(context),
          _buildActivityTab(context),
          _buildAccountTab(context),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _selectedIndex,
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: const Color(0xFF10713C),
          unselectedItemColor: Colors.grey,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          onTap: (index) {
            if (index == 3) {
              final role = GetStorage().read('role') as String?;
              // Only redirect if it's NOT a regular passenger role
              if (role != null && role != 'user' && role != 'solo') {
                Get.offAll(() => GoRideApp.getDashboardForRole(role));
              } else {
                setState(() {
                  _selectedIndex = index;
                });
              }
            } else {
              setState(() {
                _selectedIndex = index;
              });
            }
          },
          items: [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.miscellaneous_services_outlined),
              activeIcon: Icon(Icons.miscellaneous_services),
              label: 'Services',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_outlined),
              activeIcon: Icon(Icons.history),
              label: 'Activity',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_circle_outlined),
              activeIcon: Icon(Icons.account_circle),
              label: 'Account',
            ),
          ],
        ),
      ),
      ),
    );
  }

  AppBar _buildAppBar() {
    // Frontend browsing tabs (Home / Services / Activity): plain header — no
    // hamburger, no profile. Stays exactly as before.
    if (_selectedIndex != 3) {
      return AppBar(
        automaticallyImplyLeading: false,
        title: const Text('GoRide'),
        centerTitle: false,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.notifications), onPressed: () {}),
        ],
      );
    }

    // Passenger dashboard (Account tab): hamburger + avatar + name + notification.
    final user = Get.find<ApiService>().getUser();
    final name = (user?['name'] ?? 'Guest User').toString();
    final photoUrl =
        ApiService.fileUrl((user?['image'] ?? user?['profile_image']) as String?);

    return AppBar(
      leading: IconButton(
        // Toggle: open the drawer if closed, close it if open (icon flips to X).
        icon: Icon(_isDrawerOpen ? Icons.close : Icons.menu),
        onPressed: () {
          final st = _scaffoldKey.currentState;
          if (st == null) return;
          if (st.isDrawerOpen) {
            st.closeDrawer();
          } else {
            st.openDrawer();
          }
        },
      ),
      titleSpacing: 0,
      elevation: 0,
      // Hide the avatar + name while the drawer is open — it already shows them
      // in its header.
      title: _isDrawerOpen
          ? const SizedBox.shrink()
          : Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.white,
                  backgroundImage:
                      photoUrl != null ? NetworkImage(photoUrl) : null,
                  child: photoUrl == null
                      ? const Icon(Icons.person, color: Color(0xFF10713C), size: 18)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications),
          onPressed: () => Get.to(() => const NotificationsScreen()),
        ),
      ],
    );
  }

  Widget _buildHomeTab(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const OngoingRideBanner(),
            _buildSearchBar(context),
            const SizedBox(height: 20),
            _buildForYouSection(context),
            const SizedBox(height: 20),
            _buildBannerSlider(),
            const SizedBox(height: 24),
            _buildQuickActionsSection(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showLocationPopup(BuildContext context, {String? rideType}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LocationSelectionScreen(
        initialRideType: rideType,
        initialPickupAddress: _currentLocationText,
        initialPickupLat: _currentLat,
        initialPickupLng: _currentLng,
      ),
    );
  }

  void _showRentCarTypeSelection(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
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
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
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
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServicesTab(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Our Services',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1,
              children: services.map((service) {
                return GestureDetector(
                    onTap: () {
                      if (service.title == 'Rent Car') {
                        _showRentCarTypeSelection(context);
                      } else if (service.title == 'Corporate') {
                        _handleCorporateClick(context);
                      } else {
                        _showLocationPopup(context, rideType: service.title);
                      }
                    },                  child: Card(
                    elevation: 4,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF10713C),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            service.imagePath,
                            height: 90,
                            width: 90,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                service.icon,
                                size: 60,
                                color: const Color(0xFF10713C),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          Text(
                            service.title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF10713C),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityTab(BuildContext context) {
    final bool hasActivity = false;

    if (!hasActivity) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.history,
                size: 80,
                color: Colors.grey[300],
              ),
              const SizedBox(height: 16),
              Text(
                "You don't have any recent activity",
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Book your first ride to see it here',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[400],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your Activity',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            _buildActivityItem(
              'Trip to Downtown',
              '15 min ago',
              Icons.directions_car,
            ),
            _buildActivityItem('Bike Rental', '2 hours ago', Icons.two_wheeler),
            _buildActivityItem('Car Rental', '2 days ago', Icons.domain),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityItem(String title, String time, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF10713C).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: const Color(0xFF10713C)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  time,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
        ],
      ),
    );
  }

  /// Loads the passenger's dashboard data (stats + recent trips). Guarded so a
  /// slow/failed call can never leave the dashboard stuck on its spinner.
  Future<void> _loadRiderStats() async {
    final api = Get.find<ApiService>();
    try {
      try {
        final res = await api.getRiderStats();
        if (res.statusCode == 200 && res.data is Map) {
          final data = (res.data['data'] as Map?)?.cast<String, dynamic>();
          if (data != null && mounted) setState(() => _riderStats = data);
        }
      } catch (_) {/* show zeros */}
      try {
        final res = await api.getRideHistory(perPage: 3);
        if (res.statusCode == 200 && res.data is Map) {
          final list = res.data['data'] as List? ?? [];
          final trips =
              list.map((e) => (e as Map).cast<String, dynamic>()).toList();
          if (mounted) setState(() => _recentTrips = trips);
        }
      } catch (_) {/* show empty */}
    } finally {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  Widget _buildAccountTab(BuildContext context) {
    final s = _riderStats;
    // Robust parsing: the API may return numbers as strings ("170.00"), which
    // would crash a raw `as num` cast and blank out the whole tab.
    double num0(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    String money(dynamic v) => '৳${num0(v).toStringAsFixed(0)}';
    String count(dynamic v) => v is num ? '${v.toInt()}' : '${double.tryParse('$v')?.toInt() ?? 0}';

    return RefreshIndicator(
      onRefresh: _loadRiderStats,
      color: const Color(0xFF10713C),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
        children: [
          // ── Balance / trips summary banner ──
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF10713C), Color(0xFF1D9755)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Wallet Balance',
                          style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(
                        _statsLoading ? '…' : money(s?['wallet_balance']),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.account_balance_wallet_rounded,
                      color: Colors.white, size: 30),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Stat mini-cards ──
          Row(
            children: [
              _miniStat('Total Trips', _statsLoading ? '…' : count(s?['total_trips']),
                  Icons.route_rounded, const Color(0xFF10713C)),
              const SizedBox(width: 12),
              _miniStat('Completed', _statsLoading ? '…' : count(s?['completed_trips']),
                  Icons.check_circle_rounded, const Color(0xFF16A34A)),
              const SizedBox(width: 12),
              _miniStat('Spent', _statsLoading ? '…' : money(s?['total_spent']),
                  Icons.payments_rounded, const Color(0xFFED1C24)),
            ],
          ),
          const SizedBox(height: 24),

          // ── Quick actions grid ──
          const Text('Quick Actions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.85,
            children: [
              _quickAction(Icons.receipt_long_rounded, 'My Trips',
                  () => Get.to(() => const RideHistoryScreen())),
              _quickAction(Icons.bookmark_rounded, 'Saved',
                  () => Get.to(() => const SavedAddressesScreen())),
              // Both point at the real Rewards screen (live points + tier +
              // referral), not the old hardcoded Points/Membership mockups.
              _quickAction(Icons.card_giftcard_rounded, 'Rewards',
                  () => Get.to(() => const RewardsScreen())),
              _quickAction(Icons.workspace_premium_rounded, 'Member',
                  () => Get.to(() => const RewardsScreen())),
              _quickAction(Icons.person_rounded, 'Profile', () async {
                await Get.to(() => const EditProfileScreen());
                if (mounted) setState(() {});
              }),
              _quickAction(Icons.lock_rounded, 'Password',
                  () => Get.toNamed('/change-password')),
              _quickAction(Icons.support_agent_rounded, 'Support',
                  () => Get.to(() => const MySupportTicketsScreen())),
              _quickAction(Icons.logout_rounded, 'Logout', () async {
                await Get.find<ApiService>().logout();
                Get.offAll(() => const SplashScreen());
              }),
            ],
          ),
          const SizedBox(height: 24),

          // ── Recent trips ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Recent Trips',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              TextButton(
                onPressed: () => Get.to(() => const RideHistoryScreen()),
                child: const Text('See all',
                    style: TextStyle(color: Color(0xFF10713C))),
              ),
            ],
          ),
          if (_statsLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF10713C))),
            )
          else if (_recentTrips.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.directions_car_outlined,
                        size: 44, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    Text('No trips yet',
                        style: TextStyle(color: Colors.grey[600])),
                  ],
                ),
              ),
            )
          else
            ..._recentTrips.map(_recentTripTile),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 11, color: Colors.grey[700])),
          ],
        ),
      ),
    );
  }

  Widget _quickAction(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFF10713C).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF10713C), size: 24),
          ),
          const SizedBox(height: 6),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _recentTripTile(Map<String, dynamic> trip) {
    final status = (trip['status'] ?? '').toString();
    final dest = (trip['destination_address'] ?? 'Trip').toString();
    final fare = trip['actual_fare'] ?? trip['fare'] ?? 0;
    final isCancelled = status == 'cancelled';

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (isCancelled ? Colors.red : const Color(0xFF10713C))
                  .withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCancelled ? Icons.cancel_rounded : Icons.check_circle_rounded,
              color: isCancelled ? Colors.red : const Color(0xFF10713C),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dest,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                    status.isEmpty
                        ? ''
                        : status[0].toUpperCase() + status.substring(1),
                    style: TextStyle(
                        fontSize: 11,
                        color:
                            isCancelled ? Colors.red : const Color(0xFF16A34A),
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Text('৳${(fare is num ? fare.toDouble() : double.tryParse('$fare') ?? 0).toStringAsFixed(0)}',
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Color(0xFF10713C))),
        ],
      ),
    );
  }

  Future<void> _detectCurrentLocation() async {
    setState(() => _isRefreshingLocation = true);
    final PlacesService placesService = PlacesService();
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() {
          _currentLocationText = 'Location off';
          _isRefreshingLocation = false;
        });
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) setState(() {
          _currentLocationText = 'Location denied';
          _isRefreshingLocation = false;
        });
        return;
      }
      // Phase 1: Get last known position (instant, from device cache)
      // This shows something immediately while GPS warms up
      Position pos;
      try {
        final lastPos = await Geolocator.getLastKnownPosition();
        if (lastPos != null) {
          pos = lastPos;
        } else {
          // No cached position — get a quick network/cell position
          pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.low,
            timeLimit: const Duration(seconds: 3),
          );
        }
      } catch (_) {
        // If all quick methods fail, wait for GPS with no timeout
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
      }
      
      if (!mounted) return;
      _currentLat = pos.latitude;
      _currentLng = pos.longitude;

      // Resolve address from initial position for immediate display
      await _resolveAddress(pos.latitude, pos.longitude, placesService);

      // Phase 2: Asynchronously try to get a more accurate GPS position
      // GPS may need more time for first lock (cold start can take 30-60s)
      _refinePosition(placesService);
    } catch (e) {
      if (mounted) setState(() {
        _currentLocationText = 'My Current Location';
        _isRefreshingLocation = false;
      });
      // Phase 1 failed entirely, but GPS may still get a fix later
      _refinePosition(placesService);
    }
  }

  /// Resolve a human-readable address from coordinates and update the UI.
  Future<void> _resolveAddress(double lat, double lng, PlacesService placesService) async {
    // Try Google Maps reverse geocoding first (more accurate names)
    try {
      final address = await placesService.getAddressFromLatLng(lat, lng);
      if (address != null && mounted) {
        setState(() {
          _currentLocationText = address;
          _isRefreshingLocation = false;
        });
        return;
      }
    } catch (_) {}

    // Fallback to local geocoding package
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final p = placemarks[0];
        String location = '';
        if (p.subLocality != null && p.subLocality!.isNotEmpty) {
          location = p.subLocality!;
        } else if (p.locality != null && p.locality!.isNotEmpty) {
          location = p.locality!;
        }
        if (p.street != null && p.street!.isNotEmpty) {
          location = location.isEmpty ? p.street! : '$location, ${p.street}';
        }
        if (location.isEmpty) location = 'My Current Location';
        if (mounted) setState(() {
          _currentLocationText = location;
          _isRefreshingLocation = false;
        });
        return;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _currentLocationText = 'My Current Location';
        _isRefreshingLocation = false;
      });
    }
  }

  /// Try to refine the position with a more accurate GPS fix.
  /// GPS cold start can take 30-60 seconds, so this runs asynchronously
  /// after showing the initial (possibly less accurate) position.
  Future<void> _refinePosition(PlacesService placesService) async {
    try {
      // Attempt a high-accuracy position without a time limit
      // so GPS has enough time to lock on properly
      final betterPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      if (!mounted) return;

      // Only update if the new position is meaningfully different (>50m)
      final distance = Geolocator.distanceBetween(
        _currentLat ?? 0, _currentLng ?? 0,
        betterPos.latitude, betterPos.longitude,
      );

      if (distance > 50) {
        _currentLat = betterPos.latitude;
        _currentLng = betterPos.longitude;
        await _resolveAddress(betterPos.latitude, betterPos.longitude, placesService);
      }
    } catch (_) {
      // Phase 2 refinement failed — the Phase 1 result is already showing
    }
  }

  Widget _buildSearchBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF10713C), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showLocationPopup(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.my_location, color: Color(0xFF10713C), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'From',
                      style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.w500),
                    ),
                    Text(
                      _currentLocationText,
                      style: const TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Refresh location button (spins while detecting)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _isRefreshingLocation ? null : () {
                    setState(() => _currentLocationText = 'Detecting location...');
                    _detectCurrentLocation();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(6),
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: _isRefreshingLocation ? const Color(0xFF10713C).withValues(alpha: 0.1) : Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _isRefreshingLocation
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: const Color(0xFF10713C).withValues(alpha: 0.7),
                            ),
                          )
                        : const Icon(Icons.refresh, color: Color(0xFF10713C), size: 16),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10713C).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.search, color: Color(0xFF10713C), size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForYouSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'For You',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.82,
          ),
          itemCount: services.length,
          itemBuilder: (context, index) {
            return _buildServiceCard(services[index], context);
          },
        ),
      ],
    );
  }

  Widget _buildServiceCard(ServiceItem service, BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (service.title == 'Rent Car') {
          _showRentCarTypeSelection(context);
        } else if (service.title == 'Corporate') {
          _handleCorporateClick(context);
        } else {
          _showLocationPopup(context, rideType: service.title);
        }
      },      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: const Color(0xFF10713C).withValues(alpha: 0.15), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipOval(
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Image.asset(
                  service.imagePath,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Icon(
                        service.icon,
                        size: 28,
                        color: const Color(0xFF10713C),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            service.title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF10713C),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsSection() {
    final List<Map<String, dynamic>> quickActions = [
      {
        'title': 'Pay Later',
        'subtitle': 'Pay Smarter, Pay Later >',
        'icon': Icons.credit_card,
        'color': Colors.blue,
        'page': const PayLaterScreen(),
      },
      {
        'title': 'Saved Address',
        'subtitle': 'Add Home',
        'icon': Icons.location_on,
        'color': Colors.purple,
        'page': const SavedAddressScreen(),
      },
      {
        'title': 'Bronze User',
        'subtitle': 'Avail Benefits >',
        'icon': Icons.card_membership,
        'color': Colors.orange,
        'page': const MembershipScreen(),
      },
      {
        'title': 'Points',
        'subtitle': 'Redeem Now',
        'icon': Icons.star,
        'color': Colors.amber,
        'page': const PointsScreen(),
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 90,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: quickActions.length,
            padding: const EdgeInsets.only(right: 8),
            itemBuilder: (context, index) {
              final action = quickActions[index];
              return _buildQuickActionCard(
                action['title'] as String,
                action['subtitle'] as String,
                action['icon'] as IconData,
                action['color'] as Color,
                action['page'] as Widget,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionCard(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    Widget screen,
  ) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => screen),
      ),
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!, width: 1),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadBanners() async {
    try {
      final api = Get.find<ApiService>();
      final res = await api.getBanners();
      if (res.statusCode == 200 && res.data['success'] == true) {
        final list = (res.data['banners'] as List)
            .map((b) => Map<String, dynamic>.from(b as Map))
            .toList();
        if (mounted && list.isNotEmpty) setState(() => _apiBanners = list);
      }
    } catch (_) {}
  }

  /// Open a banner's link. Full URLs launch in the browser; a bare path is
  /// ignored gracefully (no crash) so bad admin input never breaks the home.
  Future<void> _openBannerLink(String link) async {
    final uri = Uri.tryParse(link);
    if (uri == null || !(uri.hasScheme && (uri.isScheme('http') || uri.isScheme('https')))) {
      return;
    }
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {/* ignore launch failures */}
  }

  Widget _buildBannerSlider() {
    final int count = _bannerCount;

    return Stack(
      children: [
        SizedBox(
          height: 150,
          child: PageView.builder(
            controller: _bannerPageController,
            onPageChanged: (index) {
              setState(() => _currentBannerPage = index % count);
            },
            itemCount: count,
            pageSnapping: true,
            itemBuilder: (context, index) {
              final isApi = _apiBanners.isNotEmpty;
              // Safe parse — never crash on an unexpected type.
              final banner = isApi ? _apiBanners[index % count] : null;
              final imageUrl = banner?['image_url']?.toString() ?? '';
              final link = banner?['link']?.toString() ?? '';
              final card = Container(
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!, width: 1),
                  color: Colors.grey[100],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: isApi
                      ? Image.network(imageUrl, fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) => Image.asset(
                              _fallbackBanners[index % _fallbackBanners.length], fit: BoxFit.cover))
                      : Image.asset(
                    _fallbackBanners[index % _fallbackBanners.length],
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Icon(Icons.local_offer, size: 50,
                          color: const Color(0xFF10713C).withValues(alpha: 0.5)),
                    ),
                  ),
                ),
              );
              // Only DB banners with a link are tappable.
              if (isApi && link.isNotEmpty) {
                return GestureDetector(
                  onTap: () => _openBannerLink(link),
                  child: card,
                );
              }
              return card;
            },
          ),
        ),
        Positioned(
          bottom: 8,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              count,
              (index) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _currentBannerPage == index
                      ? const Color(0xFF10713C)
                      : Colors.grey[300],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _handleCorporateClick(BuildContext context) {
    final apiService = Get.find<ApiService>();
    if (apiService.isLoggedIn()) {
      final user = apiService.getUser();
      final role = user?['role'] as String?;
      if (role == 'corporate') {
        Get.to(() => UnifiedDashboard(role: 'corporate'));
        return;
      }
    }
    _showCorporateInfoDialog(context);
  }

  void _showCorporateInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.business, color: Color(0xFF10713C)),
            const SizedBox(width: 10),
            const Text('Corporate Services'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'To access our exclusive corporate features, you need to be logged in with a Corporate Account.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            _buildBulletPoint('Manage employee trips & billing'),
            _buildBulletPoint('Priority support & dedicated fleet'),
            _buildBulletPoint('Detailed usage analytics & reports'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Maybe Later', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const RegisterScreen(selectedRole: 'corporate'),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10713C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Login / Register', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF10713C), size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: Colors.black87))),
        ],
      ),
    );
  }
}

class ServiceItem {
  final String title;
  final String imagePath;
  final IconData icon;

  ServiceItem({
    required this.title,
    required this.imagePath,
    required this.icon,
  });
}
