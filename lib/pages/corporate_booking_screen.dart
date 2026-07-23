import 'dart:math';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/api_service.dart';
import '../utils/num_utils.dart';
import 'map_picker_screen.dart';

const _kBrand = Color(0xFF10713C);

/// Corporate "book a ride for an employee" — a company admin enters the
/// employee's name/phone and the trip, and the ride is billed to the
/// corporate account. Same pattern as Uber for Business / Pathao Corporate.
class CorporateBookingScreen extends StatefulWidget {
  const CorporateBookingScreen({super.key});

  @override
  State<CorporateBookingScreen> createState() => _CorporateBookingScreenState();
}

class _CorporateBookingScreenState extends State<CorporateBookingScreen> {
  final _api = Get.find<ApiService>();
  final _empName = TextEditingController();
  final _empMobile = TextEditingController();

  String _rideType = 'car';
  Map<String, dynamic>? _pickup;
  Map<String, dynamic>? _dest;
  double _perKmRate = 20;
  double _baseFare = 50;
  bool _booking = false;

  static const List<String> _rideTypes = ['car', 'bike', 'cng', 'ambulance'];

  @override
  void initState() {
    super.initState();
    _loadRate();
  }

  @override
  void dispose() {
    _empName.dispose();
    _empMobile.dispose();
    super.dispose();
  }

  Future<void> _loadRate() async {
    try {
      final res = await _api.getWebsiteParameters();
      if (res.statusCode == 200 && res.data is Map) {
        final d = res.data['data'] as Map?;
        if (d != null) {
          setState(() {
            _perKmRate = parseApiDouble(d['per_km_rate'], fallback: 20);
            _baseFare = parseApiDouble(d['base_fare'], fallback: 50);
          });
        }
      }
    } catch (_) {}
  }

  double get _distanceKm {
    if (_pickup == null || _dest == null) return 0;
    const earth = 6371.0;
    final dLat = (_dest!['lat'] - _pickup!['lat']) * pi / 180;
    final dLng = (_dest!['lng'] - _pickup!['lng']) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_pickup!['lat'] * pi / 180) *
            cos(_dest!['lat'] * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return earth * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double get _fare =>
      _pickup == null || _dest == null ? 0 : _baseFare + _distanceKm * _perKmRate;

  Future<void> _pick(bool isPickup) async {
    final result = await Get.to<Map<String, dynamic>>(() => MapPickerScreen(
          title: isPickup ? 'Set Pickup' : 'Set Destination',
          initialLocation: _pickup != null
              ? LatLng(_pickup!['lat'], _pickup!['lng'])
              : null,
        ));
    if (result != null) {
      setState(() {
        if (isPickup) {
          _pickup = result;
        } else {
          _dest = result;
        }
      });
    }
  }

  Future<void> _book() async {
    if (_empName.text.trim().isEmpty || _empMobile.text.trim().isEmpty) {
      Get.snackbar('Missing info', 'Enter the employee name and phone',
          backgroundColor: Colors.red, colorText: Colors.white);
      return;
    }
    if (_pickup == null || _dest == null) {
      Get.snackbar('Missing info', 'Set both pickup and destination',
          backgroundColor: Colors.red, colorText: Colors.white);
      return;
    }
    setState(() => _booking = true);
    final res = await _api.createCorporateRideRequest({
      'employee_name': _empName.text.trim(),
      'employee_mobile': _empMobile.text.trim(),
      'ride_type': _rideType,
      'pickup_latitude': _pickup!['lat'],
      'pickup_longitude': _pickup!['lng'],
      'pickup_address': _pickup!['address'],
      'destination_latitude': _dest!['lat'],
      'destination_longitude': _dest!['lng'],
      'destination_address': _dest!['address'],
      'fare': double.parse(_fare.toStringAsFixed(0)),
    });
    if (mounted) setState(() => _booking = false);
    if (res.statusCode == 200 || res.statusCode == 201) {
      Get.back(result: true);
      Get.snackbar('Booked', 'Ride booked for ${_empName.text.trim()} — billed to your company.',
          backgroundColor: _kBrand, colorText: Colors.white);
    } else {
      Get.snackbar('Error',
          (res.data is Map ? res.data['message'] : null)?.toString() ?? 'Booking failed',
          backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Book for Employee'),
        backgroundColor: _kBrand,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _label('Employee details'),
          TextField(
            controller: _empName,
            decoration: _dec('Employee name', Icons.person_outline),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _empMobile,
            keyboardType: TextInputType.phone,
            decoration: _dec('Employee phone', Icons.phone_outlined),
          ),
          const SizedBox(height: 20),
          _label('Ride type'),
          Wrap(
            spacing: 8,
            children: _rideTypes.map((t) {
              final sel = _rideType == t;
              return ChoiceChip(
                label: Text(t.toUpperCase()),
                selected: sel,
                selectedColor: _kBrand.withValues(alpha: 0.15),
                onSelected: (_) => setState(() => _rideType = t),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          _label('Trip'),
          _locTile('Pickup', _pickup, const Color(0xFF10713C), () => _pick(true)),
          const SizedBox(height: 10),
          _locTile('Destination', _dest, Colors.red, () => _pick(false)),
          const SizedBox(height: 20),
          if (_pickup != null && _dest != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kBrand.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kBrand.withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Estimated fare',
                          style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                      Text('${_distanceKm.toStringAsFixed(1)} km × ৳${_perKmRate.toStringAsFixed(0)}/km + ৳${_baseFare.toStringAsFixed(0)} base',
                          style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                    ],
                  ),
                  Text('৳${_fare.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold, color: _kBrand)),
                ],
              ),
            ),
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _booking ? null : _book,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kBrand,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _booking
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Book Ride',
                      style: TextStyle(
                          color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black54)),
      );

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: _kBrand, size: 20),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  Widget _locTile(String label, Map<String, dynamic>? loc, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(children: [
          Icon(Icons.location_on, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                Text(
                  loc?['address']?.toString() ?? 'Tap to set on map',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: loc == null ? Colors.grey : Colors.black87),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ]),
      ),
    );
  }
}
