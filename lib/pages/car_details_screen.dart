import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/api_service.dart';
import '../utils/num_utils.dart';

class CarDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> car;
  final Map<String, dynamic> bookingData;

  const CarDetailsScreen({super.key, required this.car, required this.bookingData});

  @override
  State<CarDetailsScreen> createState() => _CarDetailsScreenState();
}

class _CarDetailsScreenState extends State<CarDetailsScreen> {
  final ApiService _api = Get.find<ApiService>();
  bool _submitting = false;

  Map<String, dynamic> get car => widget.car;
  Map<String, dynamic> get bookingData => widget.bookingData;

  /// Sends the booking to the server. The price is NOT sent — the API prices
  /// it from the car record, so the total can't be tampered with.
  Future<void> _confirmBooking() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    try {
      final res = await _api.createRentalBooking({
        'rental_car_id': car['id'],
        'with_return': bookingData['isWithReturn'] == true,
        'pickup_date': bookingData['pickupDateIso'],
        'pickup_time': bookingData['pickupTime'],
        'return_date': bookingData['returnDateIso'],
        'pickup_district': bookingData['pickupDistrict'],
        'pickup_thana': bookingData['pickupThana'],
        'dest_district': bookingData['destDistrict'],
        'dest_thana': bookingData['destThana'],
      });

      if (!mounted) return;

      if ((res.statusCode == 200 || res.statusCode == 201) &&
          res.data is Map && res.data['success'] == true) {
        _showBookingSuccess(context);
      } else {
        final msg = (res.data is Map ? res.data['message'] : null)?.toString() ??
            'Could not place the booking. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No connection. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${car['name']}'),
        backgroundColor: const Color(0xFF10713C),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              height: 250,
              color: Colors.grey[100],
              child: Hero(
                tag: 'car_${car['id'] ?? car['name']}',
                child: (car['image'] == null || '${car['image']}'.isEmpty)
                    ? const Icon(Icons.directions_car, size: 100, color: Colors.grey)
                    : Image.asset(
                        '${car['image']}',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.directions_car, size: 100, color: Colors.grey),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
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
                            '${car['name']}',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _titleCase('${car['type'] ?? ''}'),
                            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Car Specifications',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSpecCard(Icons.person_outline, 'Capacity', '${car['seats'] ?? '-'} Seats'),
                      _buildSpecCard(Icons.settings_outlined, 'Transmission',
                          '${car['transmission'] ?? '-'}'),
                      _buildSpecCard(Icons.local_gas_station, 'Fuel', '${car['fuel'] ?? '-'}'),
                    ],
                  ),
                  if (car['features'] is List && (car['features'] as List).isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text('Features',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final f in (car['features'] as List))
                          Chip(
                            label: Text('$f', style: const TextStyle(fontSize: 12)),
                            backgroundColor: const Color(0xFF10713C).withValues(alpha: 0.08),
                            side: BorderSide.none,
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 32),
                  const Text(
                    'Rental Summary',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildSummaryRow('Pickup', '${bookingData['pickupThana']}, ${bookingData['pickupDistrict']}'),
                  _buildSummaryRow('Destination', '${bookingData['destThana']}, ${bookingData['destDistrict']}'),
                  _buildSummaryRow('Date', bookingData['pickupDate']),
                  _buildSummaryRow('Time', bookingData['pickupTime']),
                  if (bookingData['isWithReturn'])
                    _buildSummaryRow('Return Date', bookingData['returnDate']),
                  const Divider(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Fare',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        '৳ ${parseApiDouble(car['price']).toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF10713C),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _confirmBooking,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10713C),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              height: 22, width: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text(
                              'Confirm Booking',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecCard(IconData icon, String label, String value) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF10713C)),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _showBookingSuccess(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF10713C), size: 80),
            const SizedBox(height: 24),
            const Text(
              'Booking Successful!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Your car rental request has been placed. A driver will contact you soon.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10713C),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Go to Home', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The API stores types lowercase ('suv'), the UI shows them capitalised.
  String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
