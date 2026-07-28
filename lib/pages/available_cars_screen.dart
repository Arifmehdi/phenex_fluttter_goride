import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/api_service.dart';
import '../utils/num_utils.dart';
import 'car_details_screen.dart';

class AvailableCarsScreen extends StatefulWidget {
  final Map<String, dynamic> bookingData;

  const AvailableCarsScreen({super.key, required this.bookingData});

  @override
  State<AvailableCarsScreen> createState() => _AvailableCarsScreenState();
}

class _AvailableCarsScreenState extends State<AvailableCarsScreen> {
  final ApiService _api = Get.find<ApiService>();

  List<Map<String, dynamic>> _cars = [];
  bool _loading = true;
  String? _error;

  Map<String, dynamic> get bookingData => widget.bookingData;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Real fleet from the server — already filtered to cars that are free for
  /// these dates, priced for the one-way / with-return choice.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.getRentalCars(
        withReturn: bookingData['isWithReturn'] == true,
        pickupDate: bookingData['pickupDateIso']?.toString(),
        returnDate: bookingData['returnDateIso']?.toString(),
      );
      if (res.statusCode == 200 && res.data is Map && res.data['success'] == true) {
        _cars = List<Map<String, dynamic>>.from(
          (res.data['cars'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
      } else {
        _error = 'Could not load cars. Please try again.';
      }
    } catch (_) {
      _error = 'No connection. Check your internet and retry.';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Available Cars'),
        backgroundColor: const Color(0xFF10713C),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildSummaryHeader(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF10713C)));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off, size: 56, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10713C)),
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }
    if (_cars.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.no_transfer, size: 56, color: Colors.grey[300]),
              const SizedBox(height: 12),
              const Text('No cars free for these dates',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Try different dates, or check back later.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600])),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: const Color(0xFF10713C),
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _cars.length,
        itemBuilder: (context, index) => _buildCarCard(context, _cars[index]),
      ),
    );
  }

  Widget _buildSummaryHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10713C).withOpacity(0.05),
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on, size: 16, color: Color(0xFF10713C)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${bookingData['pickupThana']}, ${bookingData['pickupDistrict']} → ${bookingData['destThana']}, ${bookingData['destDistrict']}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                '${bookingData['pickupDate']} at ${bookingData['pickupTime']}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              if (bookingData['isWithReturn']) ...[
                const SizedBox(width: 8),
                const Icon(Icons.compare_arrows, size: 14, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  'Return: ${bookingData['returnDate']}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCarCard(BuildContext context, Map<String, dynamic> car) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CarDetailsScreen(car: car, bookingData: bookingData),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 100,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Hero(
                      tag: 'car_${car['id'] ?? car['name']}',
                      // The admin may not have set an image — fall back to an
                      // icon rather than crashing on a null asset path.
                      child: (car['image'] == null || '${car['image']}'.isEmpty)
                          ? const Icon(Icons.directions_car, size: 40, color: Colors.grey)
                          : Image.asset(
                              '${car['image']}',
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(Icons.directions_car, size: 40, color: Colors.grey),
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${car['name']}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _titleCase('${car['type'] ?? ''}'),
                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            _buildSpecItem(Icons.person, '${car['seats'] ?? '-'} Seats'),
                            if (car['transmission'] != null)
                              _buildSpecItem(Icons.settings, '${car['transmission']}'),
                            if (car['fuel'] != null)
                              _buildSpecItem(Icons.local_gas_station, '${car['fuel']}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total Price',
                        style: TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                      Text(
                        '৳ ${parseApiDouble(car['price']).toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF10713C),
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CarDetailsScreen(car: car, bookingData: bookingData),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10713C),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                    ),
                    child: const Text(
                      'Book Now',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
      ],
    );
  }

  /// The API stores types lowercase ('suv'), the UI shows them capitalised.
  String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
