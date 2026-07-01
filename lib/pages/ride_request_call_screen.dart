import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:get/get.dart';
import '../services/ride_service.dart';
import '../services/firebase_service.dart';
import '../services/api_service.dart';
import 'live_tracking_screen.dart';

/// Full-screen incoming call screen for ride requests.
/// Behaves like an incoming phone call with ring/vibration, Accept/Decline buttons,
/// and auto-dismiss after 10 seconds.
class RideRequestCallScreen extends StatefulWidget {
  final String requestId;
  final String riderName;
  final String pickupAddress;
  final String destinationAddress;
  final String rideType;
  final double fare;
  final double pickupLat;
  final double pickupLng;
  final double destLat;
  final double destLng;
  final String? tripId;
  final String? riderPhone;
  final String? riderRating;
  final int? mysqlRideId;

  const RideRequestCallScreen({
    super.key,
    required this.requestId,
    required this.riderName,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.rideType,
    required this.fare,
    required this.pickupLat,
    required this.pickupLng,
    required this.destLat,
    required this.destLng,
    this.tripId,
    this.riderPhone,
    this.riderRating,
    this.mysqlRideId,
  });

  @override
  State<RideRequestCallScreen> createState() => _RideRequestCallScreenState();
}

class _RideRequestCallScreenState extends State<RideRequestCallScreen>
    with TickerProviderStateMixin {
  final RideService _rideService = Get.find<RideService>();
  final AudioPlayer _audioPlayer = AudioPlayer();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnim;
  Timer? _autoDismissTimer;
  int _secondsRemaining = 10;
  StreamSubscription? _docSub;
  bool _closing = false;

  @override
  void initState() {
    super.initState();

    // Watch the ride request doc — if ANOTHER driver takes it (or it's
    // cancelled), dismiss this call instantly (real-time "ride taken").
    _listenForRideTaken();

    // Keep screen on and in full-screen immersive mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    // Pulse animation for the ring effect
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutSine),
    );

    // Slide animation for the bottom panel
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    _slideController.forward();

    // Start the 10-second auto-dismiss countdown
    _startAutoDismissTimer();

    // Play looping ringtone
    _playRingtone();

    // Vibrate to alert the driver
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 500), () {
      HapticFeedback.heavyImpact();
    });
    Future.delayed(const Duration(milliseconds: 1000), () {
      HapticFeedback.heavyImpact();
    });
  }

  void _startAutoDismissTimer() {
    _autoDismissTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _secondsRemaining = 10 - timer.tick;
      });
      if (timer.tick >= 10) {
        timer.cancel();
        _dismissCall();
      }
    });
  }

  Future<void> _acceptRide() async {
    _autoDismissTimer?.cancel();
    // Mark as closing so the "ride taken" listener doesn't fire for our own accept.
    _closing = true;
    _docSub?.cancel();
    await _stopRingtone();

    // Re-read the Firestore document to get the latest mysqlRideId.
    // The rider's app writes this ~1 second after the document is created
    // (race condition), so the widget may have received a null value initially.
    int? freshMysqlRideId = widget.mysqlRideId;
    try {
      final firebaseService = Get.find<FirebaseService>();
      final doc = await firebaseService.rideRequests?.doc(widget.requestId).get();
      if (doc != null && doc.exists) {
        final fresh = (doc.data() as Map<String, dynamic>?)?['mysqlRideId'];
        if (fresh != null) {
          freshMysqlRideId = (fresh as num).toInt();
          debugPrint('Fetched fresh mysqlRideId: $freshMysqlRideId');
        }
      }
    } catch (e) {
      debugPrint('Could not re-fetch mysqlRideId: $e');
    }

    final success = await _rideService.acceptRideRequest(
      widget.requestId,
      tripId: widget.tripId,
      riderName: widget.riderName,
      riderPhone: widget.riderPhone,
      laravelRideId: freshMysqlRideId,
    );

    if (mounted) {
      // Restore system UI
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

      if (success) {
        // Pop the call screen back to the dashboard, then open tracking on top
        // so "minimize" returns to the dashboard (ongoing-ride bar shows there).
        Get.until((route) => route.isFirst);
        Get.to(() => LiveTrackingScreen(
              role: 'driver',
              rideType: widget.rideType,
              pickupAddress: widget.pickupAddress,
              destinationAddress: widget.destinationAddress,
              price: widget.fare,
              pickupLat: widget.pickupLat,
              pickupLng: widget.pickupLng,
              destLat: widget.destLat,
              destLng: widget.destLng,
              tripId: widget.tripId ?? widget.requestId,
            ));
      } else {
        // Another driver claimed it first (atomic claim lost).
        Get.back();
        Get.snackbar(
          'Ride Taken',
          'Another rider accepted this trip first.',
          backgroundColor: Colors.black87,
          colorText: Colors.white,
          duration: const Duration(seconds: 2),
        );
      }
    }
  }

  /// Play the ringtone sound in a continuous loop
  Future<void> _playRingtone() async {
    try {
      await _audioPlayer.setSource(AssetSource('audio/ringtone.wav'));
      _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.resume();
      debugPrint('Ringtone playing...');
    } catch (e) {
      debugPrint('Could not play ringtone: $e');
    }
  }

  /// Stop the playing ringtone (release the source, don't dispose — that happens in dispose())
  Future<void> _stopRingtone() async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.release();
    } catch (e) {
      debugPrint('Error stopping ringtone: $e');
    }
  }

  /// Auto-dismiss the moment the ride is no longer pending
  /// (another driver accepted it, or the rider cancelled).
  void _listenForRideTaken() {
    final stream = Get.find<FirebaseService>().streamRideRequestDoc(widget.requestId);
    if (stream == null) return;
    _docSub = stream.listen((doc) {
      if (!doc.exists) return;
      final data = doc.data() as Map<String, dynamic>?;
      final status = data?['status'] as String?;
      if (status != null && status != 'pending' && !_closing) {
        // Someone else took it / cancelled — close this call now.
        _autoDismissTimer?.cancel();
        _dismissCall(takenByOther: true);
      }
    });
  }

  void _declineRide() {
    _autoDismissTimer?.cancel();
    // Tell the backend to transfer this call to the next nearest driver.
    final rideId = widget.mysqlRideId ?? 0;
    if (rideId > 0) {
      Get.find<ApiService>().declineRide(rideId);
    }
    _dismissCall();
  }

  void _dismissCall({bool takenByOther = false}) {
    if (_closing) return;
    _closing = true;
    _stopRingtone();
    if (mounted) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      Get.back(result: false);
      if (takenByOther) {
        Get.snackbar(
          'Ride Taken',
          'This ride was accepted by another rider.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.black87,
          colorText: Colors.white,
          duration: const Duration(seconds: 2),
        );
      }
    }
  }

  @override
  void dispose() {
    _docSub?.cancel();
    _autoDismissTimer?.cancel();
    _audioPlayer.dispose();
    _pulseController.dispose();
    _slideController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),

            // === Top: "Incoming Ride" badge ===
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) => Transform.scale(
                scale: _pulseAnim.value,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10713C).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF10713C).withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.ring_volume, color: Color(0xFF10713C), size: 20),
                      SizedBox(width: 8),
                      Text(
                        'INCOMING RIDE',
                        style: TextStyle(
                          color: Color(0xFF10713C),
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const Spacer(),

            // === Avatar with ring animation ===
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF10713C).withOpacity(0.3 + 0.3 * _pulseAnim.value),
                      width: 3 * _pulseAnim.value,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10713C).withOpacity(0.15 * _pulseAnim.value),
                        blurRadius: 30 * _pulseAnim.value,
                        spreadRadius: 5 * _pulseAnim.value,
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 55,
                    backgroundColor: const Color(0xFF10713C).withOpacity(0.9),
                    child: Icon(
                      Icons.person,
                      size: 50,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // === Rider Name ===
            Text(
              widget.riderName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            // === Ride Info ===
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text(
                    '${widget.rideType.toUpperCase()} • ৳${widget.fare.round()}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.pickupAddress} → ${widget.destinationAddress}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            const Spacer(),

            // === Bottom Actions (slide in) ===
            SlideTransition(
              position: _slideAnim,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Row(
                  children: [
                    // Decline button
                    Expanded(
                      child: _buildActionButton(
                        icon: Icons.call_end,
                        label: 'Decline',
                        color: const Color(0xFFED1C24),
                        onTap: _declineRide,
                      ),
                    ),
                    const SizedBox(width: 32),
                    // Accept button
                    Expanded(
                      child: _buildActionButton(
                        icon: Icons.call,
                        label: 'Accept',
                        color: const Color(0xFF10713C),
                        onTap: _acceptRide,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // === Countdown timer ===
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(
                            value: _secondsRemaining / 10,
                            strokeWidth: 3,
                            backgroundColor: Colors.white.withOpacity(0.1),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF10713C),
                            ),
                          ),
                        ),
                        Text(
                          '$_secondsRemaining',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Auto-declining in $_secondsRemaining seconds',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.35),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
