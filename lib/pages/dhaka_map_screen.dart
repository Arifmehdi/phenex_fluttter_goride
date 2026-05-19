import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'ride_status_page.dart';

class DhakaMapScreen extends StatefulWidget {
  final String? initialRideType;
  final String? pickupAddress;
  final String? destinationAddress;
  
  const DhakaMapScreen({
    super.key, 
    this.initialRideType,
    this.pickupAddress,
    this.destinationAddress,
  });

  @override
  State<DhakaMapScreen> createState() => _DhakaMapScreenState();
}

class _DhakaMapScreenState extends State<DhakaMapScreen> {
  static const LatLng _dhakaCenterFallback = LatLng(23.8103, 90.4125);
  late final MapController _mapController;

  LatLng? _pickupLocation;
  LatLng? _destinationLocation;
  String _pickupAddress = 'Select Pickup Location';
  String _destinationAddress = 'Select Destination';
  double _distance = 0.0;
  double _price = 0.0;
  bool _selectingPickup = true;
  bool _isRideFound = false;
  String? _selectedRide;
  String _selectedPayment = 'Cash';

  Position? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _selectedRide = widget.initialRideType?.toLowerCase();
    
    if (widget.pickupAddress != null && widget.destinationAddress != null) {
      _pickupAddress = widget.pickupAddress!;
      _destinationAddress = widget.destinationAddress!;
      _pickupLocation = const LatLng(23.8103, 90.4125);
      _destinationLocation = const LatLng(23.7925, 90.4078);
      _isRideFound = true;
      _calculateRideDetails();
    }
    
    _checkPermission();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _onMapTap(LatLng point) {
    setState(() {
      if (_selectingPickup) {
        _pickupLocation = point;
        _pickupAddress = "Custom Pickup Location"; 
        _selectingPickup = false;
      } else {
        _destinationLocation = point;
        _destinationAddress = "Custom Destination";
      }
      _calculateRideDetails();
    });
  }

  void _calculateRideDetails() {
    if (_pickupLocation != null && _destinationLocation != null) {
      final double distanceInMeters = Geolocator.distanceBetween(
        _pickupLocation!.latitude,
        _pickupLocation!.longitude,
        _destinationLocation!.latitude,
        _destinationLocation!.longitude,
      );
      _distance = distanceInMeters / 1000;
      _price = 50 + (_distance * 20);
    }
  }

  Future<void> _checkPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    _startLiveTracking();
  }

  void _startLiveTracking() {
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position position) {
        if (mounted) {
          setState(() {
            _currentPosition = position;
          });

          // Update pickup address with live location text if we are still selecting pickup
          if (!_isRideFound && _pickupLocation == null) {
             _mapController.move(
              LatLng(position.latitude, position.longitude),
              15.0,
            );
            _getAddressFromLatLng(position);
          }
        }
      },
    );
  }

  Future<void> _getAddressFromLatLng(Position position) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        setState(() {
          // You can customize how much detail you want to show
          _pickupAddress = "${place.name}, ${place.subLocality}, ${place.locality}";
          // Remove any trailing commas or empty spaces
          _pickupAddress = _pickupAddress.replaceAll(RegExp(r', ,'), ',').trim();
        });
      }
    } catch (e) {
      debugPrint("Geocoding error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          _buildMap(),
          if (_isRideFound) _buildRouteSummaryHeader(),
          _buildControlPanel(),
          _buildInstructionOverlay(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: CircleAvatar(
          backgroundColor: Colors.white,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      title: Text(
        _isRideFound ? 'Your Route' : 'Select Location',
        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      actions: [
        if (_pickupLocation != null || _destinationLocation != null)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.refresh, color: Colors.black, size: 20),
                onPressed: _resetSelection,
              ),
            ),
          ),
      ],
    );
  }

  void _resetSelection() {
    setState(() {
      _pickupLocation = null;
      _destinationLocation = null;
      _pickupAddress = 'Select Pickup Location';
      _destinationAddress = 'Select Destination';
      _distance = 0.0;
      _price = 0.0;
      _selectingPickup = true;
      _isRideFound = false;
    });
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentPosition != null
            ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
            : _dhakaCenterFallback,
        initialZoom: 15,
        onTap: (tapPosition, point) => _onMapTap(point),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.goride.app',
        ),
        MarkerLayer(
          markers: [
            if (_currentPosition != null)
              Marker(
                point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                width: 40,
                height: 40,
                child: const Icon(Icons.my_location, color: Colors.blue, size: 30),
              ),
            if (_pickupLocation != null)
              Marker(
                point: _pickupLocation!,
                width: 40,
                height: 40,
                child: const Icon(Icons.location_on, color: Color(0xFF10713C), size: 40),
              ),
            if (_destinationLocation != null)
              Marker(
                point: _destinationLocation!,
                width: 40,
                height: 40,
                child: const Icon(Icons.location_on, color: Color(0xFFED1C24), size: 40),
              ),
          ],
        ),
        if (_pickupLocation != null && _destinationLocation != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [_pickupLocation!, _destinationLocation!],
                color: const Color(0xFF10713C),
                strokeWidth: 4.0,
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildRouteSummaryHeader() {
    return Positioned(
      top: 100,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
        ),
        child: Column(
          children: [
            _buildLocationSummaryRow(Icons.my_location, _pickupAddress, const Color(0xFF10713C)),
            const Padding(
              padding: EdgeInsets.only(left: 8, top: 4, bottom: 4),
              child: Align(alignment: Alignment.centerLeft, child: SizedBox(height: 10, child: VerticalDivider(width: 1))),
            ),
            _buildLocationSummaryRow(Icons.location_on, _destinationAddress, Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationSummaryRow(IconData icon, String address, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 12),
        Expanded(child: Text(address, style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _buildControlPanel() {
    return Positioned(
      bottom: 30,
      left: 16,
      right: 16,
      child: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 5))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: _isRideFound ? _buildRideOptions() : _buildLocationSelectionPanel(),
          ),
        ),
      ),
    );
  }

  Widget _buildLocationSelectionPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[200]!)),
            child: Column(
              children: [
                _buildLocationInput(icon: Icons.my_location, address: _pickupAddress, color: const Color(0xFF10713C), isSelected: _selectingPickup, onTap: () => setState(() => _selectingPickup = true)),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Divider(height: 1, color: Colors.grey[200])),
                _buildLocationInput(icon: Icons.location_on, address: _destinationAddress, color: const Color(0xFFED1C24), isSelected: !_selectingPickup, onTap: () => setState(() => _selectingPickup = false)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('Popular Places', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _buildPopularPlacesList(),
          const SizedBox(height: 20),
          _buildActionSection(),
        ],
      ),
    );
  }

  Widget _buildPopularPlacesList() {
    return SizedBox(
      height: 90,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildCompactPlace('Home', 'Gulshan 2', const LatLng(23.7925, 90.4078), Icons.home),
          _buildCompactPlace('Office', 'Banani', const LatLng(23.7937, 90.4066), Icons.work),
          _buildCompactPlace('Airport', 'Uttara', const LatLng(23.8433, 90.3978), Icons.flight),
          _buildCompactPlace('Shopping', 'JFP', const LatLng(23.8135, 90.4242), Icons.store),
        ],
      ),
    );
  }

  Widget _buildCompactPlace(String title, String area, LatLng coords, IconData icon) {
    return GestureDetector(
      onTap: () {
        setState(() {
          if (_selectingPickup) {
            _pickupLocation = coords;
            _pickupAddress = "$title ($area)";
            _selectingPickup = false;
          } else {
            _destinationLocation = coords;
            _destinationAddress = "$title ($area)";
          }
          _calculateRideDetails();
          _mapController.move(coords, 15);
        });
      },
      child: Container(
        width: 100,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[200]!)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFF10713C), size: 24),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), maxLines: 1),
            Text(area, style: TextStyle(color: Colors.grey[500], fontSize: 10), maxLines: 1),
          ],
        ),
      ),
    );
  }

  Widget _buildActionSection() {
    if (_pickupLocation != null && _destinationLocation != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Distance: ${_distance.toStringAsFixed(2)} km', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            Text('৳${_price.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: Color(0xFF10713C))),
          ]),
          ElevatedButton(
            onPressed: () => setState(() => _isRideFound = true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10713C), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            child: const Text('Find Rides', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      );
    }
    return SizedBox(
      width: double.infinity, 
      child: OutlinedButton.icon(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tap on the map to select a location.')));
        }, 
        icon: const Icon(Icons.search), 
        label: const Text('Search for more locations'), 
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF10713C), 
          side: const BorderSide(color: Color(0xFF10713C)), 
          padding: const EdgeInsets.symmetric(vertical: 14), 
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
        )
      )
    );
  }

  Widget _buildLocationInput({required IconData icon, required String address, required Color color, required bool isSelected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 18)),
            const SizedBox(width: 12),
            Expanded(child: Text(address, style: TextStyle(color: isSelected ? Colors.black87 : Colors.grey[500], fontSize: 14, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }

  Widget _buildRideOptions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
          _buildRideItem('Car', '4 seats • 5 min away', _price, 'assets/car.png', _selectedRide == 'car', () => setState(() => _selectedRide = 'car')),
          _buildRideItem('Bike', '1 seat • 2 min away', _price * 0.6, 'assets/motor.png', _selectedRide == 'bike', () => setState(() => _selectedRide = 'bike')),
          const Divider(height: 32),
          _buildPaymentAndPromo(),
          const SizedBox(height: 16),
          _buildConfirmButton(),
        ],
      ),
    );
  }

  Widget _buildPaymentAndPromo() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => setState(() => _selectedPayment = _selectedPayment == 'Cash' ? 'Card' : 'Cash'),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)), child: Row(children: [Icon(_selectedPayment == 'Cash' ? Icons.money : Icons.credit_card, size: 20, color: const Color(0xFF10713C)), const SizedBox(width: 8), Text(_selectedPayment, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), const Icon(Icons.keyboard_arrow_down, size: 16)])),
        ),
        const Spacer(),
        TextButton.icon(onPressed: () {}, icon: const Icon(Icons.local_offer_outlined, size: 18, color: Color(0xFF10713C)), label: const Text('Promo', style: TextStyle(color: Color(0xFF10713C), fontWeight: FontWeight.bold))),
      ],
    );
  }

  Widget _buildConfirmButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _selectedRide == null ? null : () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => RideStatusScreen(rideType: _selectedRide!, pickup: _pickupAddress, destination: _destinationAddress, price: _selectedRide == 'car' ? _price : _price * 0.6)));
        },
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10713C), disabledBackgroundColor: Colors.grey[300], padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
        child: Text('Confirm ${_selectedRide?.toUpperCase() ?? 'RIDE'}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }

  Widget _buildRideItem(String name, String detail, double price, String imagePath, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: isSelected ? const Color(0xFF10713C).withOpacity(0.05) : Colors.white, border: Border.all(color: isSelected ? const Color(0xFF10713C) : Colors.grey[200]!, width: isSelected ? 2 : 1), borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)), child: Image.asset(imagePath, height: 40, width: 40, errorBuilder: (c, e, s) => const Icon(Icons.directions_car, size: 30))),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isSelected ? const Color(0xFF10713C) : Colors.black87)), Text(detail, style: TextStyle(color: Colors.grey[600], fontSize: 13))])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('৳${price.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), if (isSelected) const Icon(Icons.check_circle, color: Color(0xFF10713C), size: 20)]),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionOverlay() {
    if (_isRideFound || (_pickupLocation != null && _destinationLocation != null)) return const SizedBox.shrink();
    return Positioned(
      top: 100,
      left: 16,
      right: 16,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)]),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_selectingPickup ? Icons.my_location : Icons.location_on, color: _selectingPickup ? const Color(0xFF10713C) : const Color(0xFFED1C24), size: 20),
              const SizedBox(width: 10),
              Text(_selectingPickup ? 'Set Pickup on Map' : 'Set Destination on Map', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}
