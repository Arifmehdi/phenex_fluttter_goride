import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/api_service.dart';
import '../utils/num_utils.dart';

const _kBrand = Color(0xFF10713C);

// ═══════════════════════════ Employees ═══════════════════════════

/// The staff a company books rides for. Saved once, then picked from a list
/// at booking time instead of retyping name + mobile.
class CorporateEmployeesScreen extends StatefulWidget {
  const CorporateEmployeesScreen({super.key});

  @override
  State<CorporateEmployeesScreen> createState() => _CorporateEmployeesScreenState();
}

class _CorporateEmployeesScreenState extends State<CorporateEmployeesScreen> {
  final ApiService _api = Get.find<ApiService>();

  List<Map<String, dynamic>> _employees = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _api.getCorporateEmployees();
      if (res.statusCode == 200 && res.data is Map && res.data['success'] == true) {
        _employees = List<Map<String, dynamic>>.from(
          (res.data['employees'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }
    } catch (_) {/* empty state explains it */}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _delete(Map<String, dynamic> e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove employee?'),
        content: Text('${e['name']} will no longer appear when booking.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final res = await _api.deleteCorporateEmployee(e['id'] as int);
    if (res.statusCode == 200) {
      setState(() => _employees.remove(e));
    } else {
      Get.snackbar('Failed', 'Could not remove employee',
          backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  Future<void> _edit([Map<String, dynamic>? existing]) async {
    final name = TextEditingController(text: existing?['name']?.toString() ?? '');
    final mobile = TextEditingController(text: existing?['mobile']?.toString() ?? '');
    final dept = TextEditingController(text: existing?['department']?.toString() ?? '');
    final code = TextEditingController(text: existing?['employee_code']?.toString() ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(existing == null ? 'Add employee' : 'Edit employee'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 400,
            maxHeight: MediaQuery.of(ctx).size.height * 0.5,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Full name *'),
                  textCapitalization: TextCapitalization.words,
                ),
                TextField(
                  controller: mobile,
                  decoration: const InputDecoration(labelText: 'Mobile *'),
                  keyboardType: TextInputType.phone,
                ),
                TextField(
                  controller: dept,
                  decoration: const InputDecoration(labelText: 'Department'),
                ),
                TextField(
                  controller: code,
                  decoration: const InputDecoration(labelText: 'Employee code'),
                ),
              ],
            ),
          ),
        ),
        actionsOverflowButtonSpacing: 8,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (name.text.trim().isEmpty || mobile.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: _kBrand),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (saved != true) return;

    final res = await _api.saveCorporateEmployee({
      if (existing != null) 'id': existing['id'],
      'name': name.text.trim(),
      'mobile': mobile.text.trim(),
      'department': dept.text.trim(),
      'employee_code': code.text.trim(),
    });

    if (res.statusCode == 200) {
      await _load();
    } else {
      Get.snackbar('Failed', 'Could not save employee',
          backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Employees'),
        backgroundColor: _kBrand,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        backgroundColor: _kBrand,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text('Add', style: TextStyle(color: Colors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kBrand))
          : _employees.isEmpty
              ? _empty()
              : RefreshIndicator(
                  color: _kBrand,
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _employees.length,
                    itemBuilder: (_, i) => _tile(_employees[i]),
                  ),
                ),
    );
  }

  Widget _empty() => ListView(
        children: [
          const SizedBox(height: 120),
          Icon(Icons.groups_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 12),
          const Center(
            child: Text('No employees yet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text('Add your staff to book rides for them faster.',
                style: TextStyle(color: Colors.grey[600])),
          ),
        ],
      );

  Widget _tile(Map<String, dynamic> e) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: _kBrand.withValues(alpha: 0.1),
            child: Text(
              '${e['name']}'.isNotEmpty ? '${e['name']}'[0].toUpperCase() : '?',
              style: const TextStyle(color: _kBrand, fontWeight: FontWeight.bold),
            ),
          ),
          title: Text('${e['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            '${e['mobile']}'
            '${e['department'] != null && '${e['department']}'.isNotEmpty ? ' · ${e['department']}' : ''}',
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (v) => v == 'edit' ? _edit(e) : _delete(e),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Remove')),
            ],
          ),
        ),
      );
}

// ═══════════════════════════ Trip history ═══════════════════════════

/// Every trip the company has booked, newest first.
class CorporateTripsScreen extends StatefulWidget {
  const CorporateTripsScreen({super.key});

  @override
  State<CorporateTripsScreen> createState() => _CorporateTripsScreenState();
}

class _CorporateTripsScreenState extends State<CorporateTripsScreen> {
  final ApiService _api = Get.find<ApiService>();

  static const _filters = ['', 'pending', 'in_progress', 'completed', 'cancelled'];

  List<Map<String, dynamic>> _rides = [];
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
      final res = await _api.getCorporateRides(status: _filter);
      if (res.statusCode == 200 && res.data is Map && res.data['success'] == true) {
        _rides = List<Map<String, dynamic>>.from(
          (res.data['rides'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }
    } catch (_) {/* empty state explains it */}
    if (mounted) setState(() => _loading = false);
  }

  Color _statusColor(String s) => switch (s) {
        'completed' => Colors.green,
        'cancelled' => Colors.red,
        'in_progress' || 'accepted' || 'arriving' => Colors.blue,
        _ => Colors.orange,
      };

  String _label(String s) => s.isEmpty
      ? 'All'
      : s.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Company Trips'),
        backgroundColor: _kBrand,
        foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final f in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_label(f)),
                      selected: _filter == f,
                      selectedColor: _kBrand,
                      labelStyle: TextStyle(
                          color: _filter == f ? Colors.white : Colors.black87),
                      onSelected: (_) {
                        setState(() => _filter = f);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _kBrand))
                : _rides.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 120),
                        Icon(Icons.route_outlined, size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            _filter.isEmpty ? 'No trips booked yet' : 'No ${_label(_filter).toLowerCase()} trips',
                            style: TextStyle(color: Colors.grey[600], fontSize: 16),
                          ),
                        ),
                      ])
                    : RefreshIndicator(
                        color: _kBrand,
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _rides.length,
                          itemBuilder: (_, i) => _card(_rides[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> r) {
    final status = '${r['status'] ?? ''}';
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
                  '${r['booked_for_name'] ?? 'Employee'}',
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
                child: Text(_label(status),
                    style: TextStyle(
                        color: _statusColor(status),
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _row(Icons.trip_origin, '${r['pickup_address'] ?? '—'}'),
          _row(Icons.place, '${r['destination_address'] ?? '—'}'),
          if (r['driver_name'] != null) _row(Icons.person, 'Driver: ${r['driver_name']}'),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${r['created_at'] ?? ''}'.split('.').first,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              Row(
                children: [
                  Text('৳${parseApiDouble(r['fare']).toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: _kBrand, fontSize: 16)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: r['payment_status'] == 'paid'
                          ? Colors.green.withValues(alpha: 0.12)
                          : Colors.grey.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      r['payment_status'] == 'paid' ? 'Paid' : 'Unpaid',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: r['payment_status'] == 'paid'
                            ? Colors.green[700]
                            : Colors.grey[700],
                      ),
                    ),
                  ),
                ],
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
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
}
