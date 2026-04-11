import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class DhakaMapScreen extends StatefulWidget {
  const DhakaMapScreen({super.key});

  @override
  State<DhakaMapScreen> createState() => _DhakaMapScreenState();
}

class _DhakaMapScreenState extends State<DhakaMapScreen> {
  final LatLng _dhakaCenter = LatLng(23.8103, 90.4125);
  late final MapController _mapController;
  final List<String> _locations = ['', '']; // Starts with: pickup, destination
  final int _maxAdditionalStops = 2;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showLocationBottomSheet();
    });
  }

  void _addStop() {
    if (_additionalStopsCount < _maxAdditionalStops) {
      setState(() => _locations.insert(_locations.length - 1, ''));
    }
  }

  void _removeStop(int index) {
    if (index > 0 && index < _locations.length - 1) {
      setState(() => _locations.removeAt(index));
    }
  }

  int get _additionalStopsCount => _locations.length - 2;

  void _showLocationBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.80,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                  const Expanded(
                    child: Text(
                      'Select Location',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        ...List.generate(_locations.length, (index) {
                          final isPickup = index == 0;
                          final isDestination = index == _locations.length - 1;
                          final stopNumber = isPickup ? 1 : isDestination ? _locations.length : index;
                          return AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder: (child, animation) {
                              return SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(1, 0),
                                  end: Offset.zero,
                                ).animate(CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutCubic,
                                )),
                                child: FadeTransition(opacity: animation, child: child),
                              );
                            },
                            child: Column(
                              key: ValueKey(index),
                              children: [
                                Row(
                                  children: [
                                    Column(
                                      children: [
                                        AnimatedContainer(
                                          duration: const Duration(milliseconds: 300),
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            color: isPickup ? const Color(0xFF10713C) : isDestination ? const Color(0xFFED1C24) : Colors.grey,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        if (!isDestination)
                                          AnimatedContainer(
                                            duration: const Duration(milliseconds: 300),
                                            width: 2,
                                            height: 30,
                                            color: Colors.grey[400],
                                          ),
                                      ],
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextField(
                                        decoration: InputDecoration(
                                          hintText: isPickup ? 'Pickup location' : isDestination ? 'Final destination' : 'Stop $stopNumber',
                                          hintStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
                                          border: InputBorder.none,
                                        ),
                                      ),
                                    ),
                                    if (!isPickup && !isDestination)
                                      IconButton(
                                        icon: Icon(Icons.close, size: 18, color: Colors.grey[600]),
                                        onPressed: () => _removeStop(index),
                                      ),
                                  ],
                                ),
                                if (!isDestination) Divider(color: Colors.grey[300]),
                              ],
                            ),
                          );
                        }),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (child, animation) {
                            return FadeTransition(opacity: animation, child: child);
                          },
                          child: _additionalStopsCount < _maxAdditionalStops
                            ? Padding(
                                key: const ValueKey('addStopBtn'),
                                padding: const EdgeInsets.only(top: 8),
                                child: TextButton.icon(
                                  onPressed: _addStop,
                                  icon: const Icon(Icons.add_circle, size: 18),
                                  label: const Text('Add Stop'),
                                ),
                              )
                            : const SizedBox.shrink(key: ValueKey('noAddBtn')),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10713C),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Find Rides',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Popular Places',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildPopularPlace(Icons.home, 'Home', 'Gulshan 2, Dhaka'),
                  _buildPopularPlace(Icons.work, 'Office', 'Banani, Dhaka'),
                  _buildPopularPlace(Icons.flight, 'Airport', 'Hazrat Shahjalal International'),
                  _buildPopularPlace(Icons.store, 'Shopping', 'Jamuna Future Park'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPopularPlace(IconData icon, String title, String address) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF10713C).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: const Color(0xFF10713C), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text(address, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Location'),
        backgroundColor: const Color(0xFF10713C),
        foregroundColor: Colors.white,
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _dhakaCenter,
          initialZoom: 13,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.goride.app',
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: _dhakaCenter,
                width: 40,
                height: 40,
                child: const Icon(Icons.location_on, color: Color(0xFF10713C), size: 40),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
