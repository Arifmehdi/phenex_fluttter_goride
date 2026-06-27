import '../main.dart';
import 'home_page.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import '../locale_controller.dart';
import '../registration_screens.dart' show OwnerProfileScreen;
import 'dashboard_details_pages.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../widgets/sidebar_menu.dart';
import 'ride_request_call_screen.dart';
import 'profile_completion_screen.dart';
import 'ride_history_screen.dart';

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../services/firebase_service.dart';
import '../services/ride_service.dart';
import 'live_tracking_screen.dart';
import 'notifications_screen.dart';

class UnifiedDashboard extends StatefulWidget {
  final String role; // 'driver', 'owner', 'corporate', 'admin'
  const UnifiedDashboard({super.key, required this.role});

  @override
  State<UnifiedDashboard> createState() => _UnifiedDashboardState();
}

class _UnifiedDashboardState extends State<UnifiedDashboard> {
  final LocaleController localeController = Get.find<LocaleController>();
  final LocationService _locationService = Get.find<LocationService>();
  final ApiService _apiService = Get.find<ApiService>();
  final FirebaseService _firebaseService = Get.find<FirebaseService>();
  final RideService _rideService = Get.find<RideService>();
  final NotificationService _notificationService = NotificationService();
  
  bool _isOnline = true;
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Profile completion tracking
  int _profileCompletionPercent = 0;
  bool _isProfileLoading = true;

  // Nearby ride request tracking
  static const double _nearbyRadiusKm = 5.0; // 5km radius
  StreamSubscription<QuerySnapshot>? _requestSubscription;
  final Set<String> _pendingRequestIds = {};
  final Set<String> _declinedRequestIds = {}; // Track declined requests locally

  @override
  // Driver live stats
  Map<String, dynamic> _driverStats = {};

  void initState() {
    super.initState();
    if (widget.role == 'driver' && !_locationService.isTracking.value) {
      _toggleOnlineStatus(true);
    }
    if (widget.role == 'driver') {
      _setupRideRequestListener();
      _loadDriverStats();
    }
    if (widget.role != 'admin') {
      _loadProfileCompletion();
    }
  }

  Future<void> _loadDriverStats() async {
    try {
      final res = await _apiService.getDriverStats();
      if (res.statusCode == 200 && res.data['success'] == true) {
        if (mounted) setState(() => _driverStats = Map<String, dynamic>.from(res.data['stats'] ?? {}));
      }
    } catch (_) {}
  }

  Future<void> _loadProfileCompletion() async {
    try {
      final response = await _apiService.getProfileCompletion();
      if (response.statusCode == 200 && response.data['success'] == true) {
        final pct = response.data['profile_completion']['percentage'] ?? 0;
        if (mounted) {
          setState(() {
            _profileCompletionPercent = pct;
            _isProfileLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isProfileLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isProfileLoading = false);
    }
  }

  @override
  void dispose() {
    _requestSubscription?.cancel();
    super.dispose();
  }

  /// Set up a listener for new ride requests to trigger notifications
  void _setupRideRequestListener() {
    _requestSubscription = _firebaseService.streamPendingRequests().listen(
      (snapshot) {
        for (final change in snapshot.docChanges) {
          final requestId = change.doc.id;
          final data = change.doc.data() as Map<String, dynamic>?;
          if (data == null) continue;

          switch (change.type) {
            case DocumentChangeType.added:
              _pendingRequestIds.add(requestId);
              if (_isOnline && mounted) {
                _notifyNewRideRequest(requestId, data);
              }
              break;
            case DocumentChangeType.removed:
              _pendingRequestIds.remove(requestId);
              _notificationService.dismissRequest(requestId);
              break;
            case DocumentChangeType.modified:
              final status = data['status'] as String?;
              if (status != 'pending') {
                _pendingRequestIds.remove(requestId);
                _notificationService.dismissRequest(requestId);
              }
              break;
          }
        }
      },
      onError: (error) {
        // This fires when Firestore rules block access or network fails.
        // Most common cause: Firebase Auth not initialized (anonymous sign-in needed).
        debugPrint('❌ Ride request stream error: $error');
      },
    );
  }

  /// Show notification and full-screen call UI for a new ride request (only if nearby)
  void _notifyNewRideRequest(String requestId, Map<String, dynamic> data) {
    final pickupLat = (data['pickupLatitude'] as num?)?.toDouble();
    final pickupLng = (data['pickupLongitude'] as num?)?.toDouble();
    
    // Check if driver already declined this request
    if (_declinedRequestIds.contains(requestId)) {
      debugPrint('Request $requestId was previously declined by this driver. Skipping.');
      return;
    }

    // Check proximity first
    if (pickupLat != null && pickupLng != null) {
      final distance = _getDistanceFromDriver(pickupLat, pickupLng);
      if (distance != null && distance > _nearbyRadiusKm) {
        debugPrint('Request $requestId is $distance km away — outside $_nearbyRadiusKm km radius. Skipping notification.');
        return; // Too far, don't notify
      }
    }

    // Show system notification (for background alerts)
    _notificationService.showRideRequestNotification(
      requestId: requestId,
      riderName: data['riderName'] as String? ?? 'Passenger',
      pickupAddress: data['pickupAddress'] as String? ?? 'Unknown',
      destinationAddress: data['destAddress'] as String? ?? 'Unknown',
      fare: '৳ ${(data['fare'] as num?)?.round() ?? '0'}',
    );

    // Show full-screen incoming call UI
    _showIncomingCallScreen(requestId, data);
  }

  /// Navigate to the full-screen incoming call UI
  void _showIncomingCallScreen(String requestId, Map<String, dynamic> data) {
    final riderName = data['riderName'] as String? ?? 'Passenger';
    final pickupAddress = data['pickupAddress'] as String? ?? 'Unknown';
    final destAddress = data['destAddress'] as String? ?? 'Unknown';
    final rideType = data['rideType'] as String? ?? 'car';
    final fare = (data['fare'] as num?)?.toDouble() ?? 0.0;
    final pickupLat = (data['pickupLatitude'] as num?)?.toDouble() ?? 0.0;
    final pickupLng = (data['pickupLongitude'] as num?)?.toDouble() ?? 0.0;
    final destLat = (data['destLatitude'] as num?)?.toDouble() ?? 0.0;
    final destLng = (data['destLongitude'] as num?)?.toDouble() ?? 0.0;
    final tripId = data['tripId'] as String?;
    final riderPhone = data['riderPhone'] as String?;
    final mysqlRideId = (data['mysqlRideId'] as num?)?.toInt();

    // Show the full-screen call. When it returns via Get.back(result: false),
    // it means the driver declined or timed out — hide this request.
    if (mounted && Get.isDialogOpen != true) {
      Get.to<bool>(
        () => RideRequestCallScreen(
          requestId: requestId,
          riderName: riderName,
          pickupAddress: pickupAddress,
          destinationAddress: destAddress,
          rideType: rideType,
          fare: fare,
          pickupLat: pickupLat,
          pickupLng: pickupLng,
          destLat: destLat,
          destLng: destLng,
          tripId: tripId,
          riderPhone: riderPhone,
          mysqlRideId: mysqlRideId,
        ),
        fullscreenDialog: true,
        transition: Transition.fadeIn,
        duration: const Duration(milliseconds: 300),
      )?.then((wasAccepted) {
        // If the call screen was dismissed without accepting (result == false or null),
        // mark this request as declined so it won't bother this driver again.
        // When the driver accepts, Get.offAll() replaces the entire stack and
        // this widget gets disposed → mounted becomes false → skip the add.
        if (!mounted) return;
        if (wasAccepted != true) {
          setState(() {
            _declinedRequestIds.add(requestId);
          });
          debugPrint('Driver declined/timeout for request $requestId. Hiding from dashboard.');
        }
      });
    }
  }

  /// Calculate distance from driver's current location to a point (in km)
  double? _getDistanceFromDriver(double lat, double lng) {
    final driverPos = _locationService.currentPosition.value;
    if (driverPos == null) return null;
    return Geolocator.distanceBetween(
      driverPos.latitude, driverPos.longitude,
      lat, lng,
    ) / 1000; // Convert meters to km
  }

  /// Check if a ride request is nearby the driver
  bool _isRideNearby(Map<String, dynamic> data) {
    final pickupLat = (data['pickupLatitude'] as num?)?.toDouble();
    final pickupLng = (data['pickupLongitude'] as num?)?.toDouble();
    if (pickupLat == null || pickupLng == null) return true; // Show if no coordinates
    
    final distance = _getDistanceFromDriver(pickupLat, pickupLng);
    if (distance == null) return true; // Show if we can't determine distance
    return distance <= _nearbyRadiusKm;
  }

  Future<void> _toggleOnlineStatus(bool online) async {
    final user = _apiService.getUser();
    final String? driverId = user?['id']?.toString();
    
    if (driverId == null) {
      Get.snackbar('Error', 'User ID not found. Please re-login.');
      return;
    }

    setState(() => _isOnline = online);

    final vehicleType = user?['vehicle_type']?.toString().toLowerCase();

    // Synchronize online status to Laravel MySQL database
    try {
      await _apiService.toggleDriverOnline(online);
      debugPrint('Synchronized online status to Laravel API: $online');
    } catch (e) {
      debugPrint('Error syncing online status to Laravel API: $e');
    }

    if (!online) {
      // Clear all request tracking when going offline
      _pendingRequestIds.clear();
      _declinedRequestIds.clear();
      _notificationService.cancelAll();
    }

    if (online) {
      // Start tracking and sync to Firestore
      await _locationService.startTracking(
        syncToFirestore: true,
        driverId: driverId,
        vehicleType: vehicleType,
        isOnline: true,
      );
      Get.snackbar('Online', 'You are now online and can receive ride requests.');
    } else {
      // Stop tracking
      await _locationService.stopTracking();
      Get.snackbar('Offline', 'You are now offline.');
    }
  }

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
            _buildSecondaryTab(), // 'Bids' for Rider, 'Fleet' for Owner/Corporate/Admin
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
      title = localeController.get('Rider Dashboard', 'রাইডার ড্যাশবোর্ড');
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
                onChanged: (v) => _toggleOnlineStatus(v),
                activeColor: Colors.white,
                activeTrackColor: Colors.lightGreenAccent,
              ),
            ],
          ),
        IconButton(
          icon: const Icon(Icons.notifications_none),
          onPressed: () => Get.to(() => const NotificationsScreen()),
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
          if (widget.role == 'driver') _buildActiveTripSection(),
          if (widget.role == 'driver') const SizedBox(height: 24),
          if (widget.role == 'driver') _buildPendingBidsSection(),
          if (widget.role == 'owner') _buildCarStatusSection(),
          if (widget.role == 'corporate') _buildCorporateAlerts(),
          if (widget.role == 'admin') _buildAdminManagementSection(),
        ],
      ),
    );
  }

  Widget _buildActiveTripSection() {
    return Obx(() {
      final status = _rideService.tripStatus.value;
      if (status == 'idle' || status == 'completed' || status == 'cancelled') {
        return const SizedBox.shrink();
      }

      String statusDisplay = 'Active Trip';
      IconData statusIcon = Icons.local_taxi;
      if (status == 'accepted') { statusDisplay = 'Accepted • Heading to Pickup'; statusIcon = Icons.directions_run; }
      else if (status == 'arriving') { statusDisplay = 'Arrived at Pickup Spot'; statusIcon = Icons.pin_drop; }
      else if (status == 'in_progress') { statusDisplay = 'In Progress • Driving'; statusIcon = Icons.navigation; }

      return Card(
        elevation: 2,
        color: const Color(0xFF10713C).withOpacity(0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF10713C), width: 1.5),
        ),
        child: InkWell(
          onTap: () {
            Get.to(() => LiveTrackingScreen(
              role: 'driver',
              rideType: _rideService.currentRideType.value,
              pickupAddress: _rideService.currentPickupAddress.value,
              destinationAddress: _rideService.currentDestAddress.value,
              price: _rideService.currentFare.value,
              pickupLat: _rideService.currentPickupLat.value,
              pickupLng: _rideService.currentPickupLng.value,
              destLat: _rideService.currentDestLat.value,
              destLng: _rideService.currentDestLng.value,
              tripId: _rideService.currentTripId.value,
            ));
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(statusIcon, color: const Color(0xFF10713C)),
                    const SizedBox(width: 8),
                    Text(
                      statusDisplay,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10713C),
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      'Resume Live Map',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF10713C),
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'You have an ongoing trip in progress. Tap here to reopen the tracking screen and continue navigation.',
                  style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildWelcomeHeader() {
    final user = _apiService.getUser();
    String name = user?['name'] ?? (widget.role == 'corporate' ? 'TechCorp Ltd.' : 'Guest User');
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
    final pct = _profileCompletionPercent;
    final progressValue = pct / 100.0;
    final isComplete = pct >= 100;
    final color = pct >= 70 ? const Color(0xFF16A34A) : (pct >= 40 ? const Color(0xFFF59E0B) : const Color(0xFFED1C24));

    return GestureDetector(
      onTap: () => _navigateToProfileCompletion(),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF10713C).withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      isComplete ? Icons.check_circle : Icons.person_outline,
                      size: 18,
                      color: color,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      localeController.get('Profile Completion', 'প্রোফাইল সম্পন্ন'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      _isProfileLoading ? '...' : '$pct%',
                      style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_ios, size: 12, color: color),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: _isProfileLoading ? 0 : progressValue,
                minHeight: 8,
                backgroundColor: Colors.white,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isComplete
                      ? localeController.get('Profile complete! Pending approval', 'প্রোফাইল সম্পন্ন! অনুমোদন অপেক্ষায়')
                      : localeController.get('Complete profile to get approved', 'অনুমোদনের জন্য প্রোফাইল সম্পন্ন করুন'),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                if (!isComplete)
                  Text(
                    localeController.get('Complete Now', 'এখন সম্পন্ন করুন'),
                    style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToProfileCompletion() {
    Get.to(() => ProfileCompletionScreen(role: widget.role));
  }

  Widget _buildStatsGrid() {
    List<Map<String, dynamic>> stats = [];
    if (widget.role == 'driver') {
      final earn = (_driverStats['today_earnings'] as num? ?? 0).toDouble();
      final earnStr = earn >= 1000 ? '৳${(earn / 1000).toStringAsFixed(1)}k' : '৳${earn.toStringAsFixed(0)}';
      stats = [
        {
          'label': localeController.get('Today Trips', 'আজকের ট্রিপ'),
          'value': '${_driverStats['today_trips'] ?? '—'}',
          'icon': Icons.directions_car,
          'color': Colors.blue,
        },
        {
          'label': localeController.get('Rating', 'রেটিং'),
          'value': '${_driverStats['avg_rating'] ?? '—'}',
          'icon': Icons.star,
          'color': Colors.orange,
        },
        {
          'label': localeController.get('Today Earn', 'আজকের আয়'),
          'value': _driverStats.isEmpty ? '—' : earnStr,
          'icon': Icons.payments,
          'color': Colors.green,
        },
        {
          'label': localeController.get('Accept %', 'গ্রহণ হার'),
          'value': '${_driverStats['acceptance_rate'] ?? '—'}%',
          'icon': Icons.percent,
          'color': Colors.teal,
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
          'label': localeController.get('Riders', 'রাইডার'),
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
          'label': localeController.get('Active Riders', 'সক্রিয় রাইডার'),
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
        StreamBuilder<QuerySnapshot>(
          stream: _firebaseService.streamPendingRequests(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: Padding(
                padding: EdgeInsets.all(20.0),
                child: CircularProgressIndicator(),
              ));
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.request_page_outlined, size: 48, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text(
                        localeController.get('No requests available', 'কোন অনুরোধ নেই'),
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
              );
            }

            // Filter by nearby proximity and declined requests
            final nearbyDocs = snapshot.data!.docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return _isRideNearby(data) && !_declinedRequestIds.contains(doc.id);
            }).toList();

            if (nearbyDocs.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.near_me_disabled_outlined, size: 40, color: Colors.grey[300]),
                      const SizedBox(height: 8),
                      Text(
                        localeController.get('No nearby requests', 'কাছের কোন অনুরোধ নেই'),
                        style: TextStyle(color: Colors.grey[400], fontSize: 13),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Column(
              children: nearbyDocs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final String pickup = data['pickupAddress'] ?? 'Unknown';
                final String destination = data['destAddress'] ?? 'Unknown';
                final String riderName = data['riderName'] ?? 'Passenger';
                
                return _buildRequestCard(
                  '$pickup to $destination',
                  riderName,
                  '৳ ${(data['fare'] as num?)?.round() ?? '0'}',
                  doc.id,
                  data,
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildRequestCard(String route, String riderName, String fare, String requestId, Map<String, dynamic> data) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          route, 
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text('$riderName • $fare', style: TextStyle(color: Colors.grey[600])),
        ),
        trailing: ElevatedButton(
          onPressed: () => _acceptRide(requestId, data),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10713C),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            minimumSize: const Size(80, 36),
          ),
          child: Text(
            localeController.get('Accept', 'গ্রহণ'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  void _acceptRide(String requestId, Map<String, dynamic> data) async {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(localeController.get('Accept Ride?', 'রাইড গ্রহণ করবেন?')),
        content: Text(localeController.get('Are you sure you want to accept this ride?', 'আপনি কি নিশ্চিত যে আপনি এই রাইডটি গ্রহণ করতে চান?')),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text(localeController.get('Cancel', 'বাতিল'), style: const TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Get.back();
              // Dismiss notification
              _notificationService.dismissRequest(requestId);
              _pendingRequestIds.remove(requestId);
              
              final String? tripId = data['tripId'];
              final success = await _rideService.acceptRideRequest(
                requestId, 
                tripId: tripId,
                riderName: data['riderName'] as String?,
                riderPhone: data['riderPhone'] as String?,
              );
              if (success) {
                Get.to(() => LiveTrackingScreen(
                  role: 'driver',
                  rideType: data['rideType'] ?? 'car',
                  pickupAddress: data['pickupAddress'] ?? 'Pickup',
                  destinationAddress: data['destAddress'] ?? 'Destination',
                  price: (data['fare'] as num?)?.toDouble() ?? 0.0,
                  pickupLat: (data['pickupLatitude'] as num?)?.toDouble() ?? 0.0,
                  pickupLng: (data['pickupLongitude'] as num?)?.toDouble() ?? 0.0,
                  destLat: (data['destLatitude'] as num?)?.toDouble() ?? 0.0,
                  destLng: (data['destLongitude'] as num?)?.toDouble() ?? 0.0,
                  tripId: tripId ?? requestId,
                ));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10713C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(localeController.get('Accept', 'গ্রহণ'), style: const TextStyle(color: Colors.white)),
          ),
        ],
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
          'Manage riders, owners & corporates',
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
          Icons.history_toggle_off,
          localeController.get('Ride History', 'Trip History'),
          onTap: () => Get.to(() => const RideHistoryScreen()),
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
