import 'package:flutter/material.dart';
import 'car_details_screen.dart';

class AvailableCarsScreen extends StatelessWidget {
  final Map<String, dynamic> bookingData;

  const AvailableCarsScreen({super.key, required this.bookingData});

  @override
  Widget build(BuildContext context) {
    // Mock car data
    final List<Map<String, dynamic>> cars = [
      {
        'name': 'Toyota Corolla',
        'type': 'Sedan',
        'price': bookingData['isWithReturn'] ? 5500 : 3500,
        'image': 'assets/car.png',
        'rating': 4.8,
        'seats': 4,
        'bags': 2,
      },
      {
        'name': 'Mitsubishi Pajero',
        'type': 'SUV',
        'price': bookingData['isWithReturn'] ? 8500 : 5500,
        'image': 'assets/car.png',
        'rating': 4.9,
        'seats': 7,
        'bags': 4,
      },
      {
        'name': 'Toyota Hiace',
        'type': 'Microbus',
        'price': bookingData['isWithReturn'] ? 12000 : 8000,
        'image': 'assets/car.png',
        'rating': 4.7,
        'seats': 12,
        'bags': 6,
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Available Cars'),
        backgroundColor: const Color(0xFF10713C),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildSummaryHeader(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: cars.length,
              itemBuilder: (context, index) {
                return _buildCarCard(context, cars[index]);
              },
            ),
          ),
        ],
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
                      tag: car['name'],
                      child: Image.asset(
                        car['image'],
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              car['name'],
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Row(
                              children: [
                                const Icon(Icons.star, color: Colors.amber, size: 16),
                                Text(
                                  ' ${car['rating']}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          car['type'],
                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _buildSpecItem(Icons.person, '${car['seats']} Seats'),
                            const SizedBox(width: 12),
                            _buildSpecItem(Icons.work, '${car['bags']} Bags'),
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
                        '৳ ${car['price']}',
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
}
