import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart' as latlong;

class TripDetailsPage extends StatelessWidget {
  final String rideType;
  final String pickup;
  final String destination;
  final double price;

  const TripDetailsPage({
    super.key,
    required this.rideType,
    required this.pickup,
    required this.destination,
    required this.price,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Map
          _buildMap(),

          // Back Button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: CircleAvatar(
                backgroundColor: Colors.white,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),

          // Draggable Bottom Sheet for details
          DraggableScrollableSheet(
            initialChildSize: 0.4,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
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
                    
                    // Status Badge
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10713C).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.access_time, color: Color(0xFF10713C), size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Driver is arriving in 3 mins',
                              style: TextStyle(color: Color(0xFF10713C), fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Route Info
                    _buildRouteInfo(),
                    
                    const Divider(height: 48),
                    
                    // Fare Details
                    const Text(
                      'Fare Details',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    _buildFareRow('Base Fare', '৳50.00'),
                    _buildFareRow('Distance Fare', '৳${(price - 50 - 10).toStringAsFixed(2)}'),
                    _buildFareRow('Service Fee', '৳10.00'),
                    const Divider(height: 24),
                    _buildFareRow('Total (Incl. Tax)', '৳${price.toStringAsFixed(2)}', isTotal: true),
                    
                    const SizedBox(height: 32),
                    
                    // Safety & Support
                    const Text(
                      'Safety & Support',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _buildSafetyOption(Icons.share, 'Share Trip', Colors.blue),
                        const SizedBox(width: 12),
                        _buildSafetyOption(Icons.emergency, 'Emergency', Colors.red),
                        const SizedBox(width: 12),
                        _buildSafetyOption(Icons.support_agent, 'Support', Colors.orange),
                      ],
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Driver Summary (Mini)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            radius: 20,
                            backgroundImage: AssetImage('assets/user-avatar.png'),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Md. Abdur Rahman', style: TextStyle(fontWeight: FontWeight.bold)),
                                Text('Toyota Corolla • DHK-1234', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              const Icon(Icons.star, color: Colors.amber, size: 16),
                              const Text(' 4.9', style: TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return fmap.FlutterMap(
      options: const fmap.MapOptions(
        initialCenter: latlong.LatLng(23.8103, 90.4125),
        initialZoom: 15,
      ),
      children: [
        fmap.TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.goride.app',
        ),
        fmap.MarkerLayer(
          markers: [
            fmap.Marker(
              point: const latlong.LatLng(23.8103, 90.4125),
              width: 40,
              height: 40,
              child: const Icon(Icons.my_location, color: Colors.blue, size: 30),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRouteInfo() {
    return Column(
      children: [
        Row(
          children: [
            const Icon(Icons.my_location, color: Color(0xFF10713C), size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Pickup', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Text(pickup, style: const TextStyle(fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(left: 9),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(height: 24, child: VerticalDivider(width: 1, thickness: 1)),
          ),
        ),
        Row(
          children: [
            const Icon(Icons.location_on, color: Colors.red, size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Destination', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Text(destination, style: const TextStyle(fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFareRow(String label, String amount, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? Colors.black : Colors.grey[600],
            ),
          ),
          Text(
            amount,
            style: TextStyle(
              fontSize: isTotal ? 20 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              color: isTotal ? const Color(0xFF10713C) : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyOption(IconData icon, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.1)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}
