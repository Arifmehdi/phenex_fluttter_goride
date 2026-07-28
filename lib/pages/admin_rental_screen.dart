import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/api_service.dart';
import '../utils/num_utils.dart';

const _kBrand = Color(0xFF10713C);

/// Admin: every Rent-a-Car booking, with the status controls the web panel
/// has. Mirrors /admin/rental/bookings on the browser side.
class AdminRentalScreen extends StatefulWidget {
  const AdminRentalScreen({super.key});

  @override
  State<AdminRentalScreen> createState() => _AdminRentalScreenState();
}

class _AdminRentalScreenState extends State<AdminRentalScreen> {
  final ApiService _api = Get.find<ApiService>();

  static const _statuses = ['pending', 'confirmed', 'ongoing', 'completed', 'cancelled'];

  List<Map<String, dynamic>> _bookings = [];
  bool _loading = true;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _api.getAdminRentalBookings(status: _filter);
      if (res.statusCode == 200 && res.data is Map && res.data['success'] == true) {
        _bookings = List<Map<String, dynamic>>.from(
          (res.data['bookings'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }
    } catch (_) {
      // keep whatever we had; the empty state explains it
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setStatus(Map<String, dynamic> b, String status) async {
    final res = await _api.updateRentalBookingStatus(b['id'] as int, status);
    final ok = res.statusCode == 200 && res.data is Map && res.data['success'] == true;
    if (ok) {
      setState(() => b['status'] = status);
    }
    Get.snackbar(
      ok ? 'Updated' : 'Failed',
      ok
          ? 'Booking #${b['id']} is now $status'
          : ((res.data is Map ? res.data['message'] : null)?.toString() ?? 'Could not update'),
      backgroundColor: ok ? _kBrand : Colors.red,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  Color _statusColor(String s) => switch (s) {
        'confirmed' => Colors.blue,
        'ongoing' => Colors.teal,
        'completed' => Colors.green,
        'cancelled' => Colors.red,
        _ => Colors.orange, // pending
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Rental Bookings'),
        backgroundColor: _kBrand,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          _filterBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _kBrand))
                : _bookings.isEmpty
                    ? _emptyState()
                    : RefreshIndicator(
                        color: _kBrand,
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _bookings.length,
                          itemBuilder: (_, i) => _card(_bookings[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _filterBar() {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _chip('All', ''),
          for (final s in _statuses) _chip(_titleCase(s), s),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        selectedColor: _kBrand,
        labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87),
        onSelected: (_) {
          setState(() => _filter = value);
          _load();
        },
      ),
    );
  }

  Widget _emptyState() => ListView(
        children: [
          const SizedBox(height: 120),
          Icon(Icons.event_busy, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Center(
            child: Text(
              _filter.isEmpty ? 'No rental bookings yet' : 'No $_filter bookings',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ),
        ],
      );

  Widget _card(Map<String, dynamic> b) {
    final status = (b['status'] ?? 'pending').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '#${b['id']}  ${b['car_name'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor(status).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _titleCase(status),
                  style: TextStyle(
                    color: _statusColor(status),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _row(Icons.person, '${b['customer'] ?? 'Unknown'}'
              '${b['customer_phone'] != null ? ' · ${b['customer_phone']}' : ''}'),
          _row(
            Icons.route,
            '${b['pickup_district'] ?? '—'} → ${b['dest_district'] ?? '—'}'
            '  (${b['with_return'] == true ? 'with return' : 'one way'})',
          ),
          _row(
            Icons.calendar_today,
            '${b['pickup_date'] ?? '—'}'
            '${b['pickup_time'] != null ? ' · ${b['pickup_time']}' : ''}'
            '${b['return_date'] != null ? '  →  ${b['return_date']}' : ''}',
          ),
          _row(Icons.payments,
              '৳${parseApiDouble(b['total_price']).toStringAsFixed(0)}'),
          const Divider(height: 20),
          Row(
            children: [
              const Text('Set status:', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<String>(
                  value: _statuses.contains(status) ? status : 'pending',
                  isExpanded: true,
                  underline: const SizedBox(),
                  items: [
                    for (final s in _statuses)
                      DropdownMenuItem(value: s, child: Text(_titleCase(s))),
                  ],
                  onChanged: (v) {
                    if (v != null && v != status) _setStatus(b, v);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: Colors.grey[500]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
      );

  String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
