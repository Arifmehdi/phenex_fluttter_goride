import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_service.dart';
import '../utils/num_utils.dart';

class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({super.key});

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  final ApiService _apiService = Get.find<ApiService>();
  List<dynamic> _rides = [];
  bool _isLoading = true;
  String? _error;
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
      final ampm = date.hour >= 12 ? 'PM' : 'AM';
      final min = date.minute.toString().padLeft(2, '0');
      return date.day.toString() + ' ' + months[date.month - 1] + ' ' + date.year.toString() + ', ' + hour.toString() + ':' + min + ' ' + ampm;
    } catch (_) {
      return dateStr ?? '';
    }
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await _apiService.getRideHistory(
        status: _statusFilter == 'all' ? null : _statusFilter,
      );
      if (response.statusCode == 200 && response.data['success'] == true) {
        setState(() { _rides = response.data['data'] ?? []; _isLoading = false; });
      } else {
        setState(() { _error = 'Failed to load ride history'; _isLoading = false; });
      }
    } catch (e) {
      setState(() { _error = 'Connection error'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride History'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() => _statusFilter = value);
              _loadHistory();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('All Rides')),
              const PopupMenuItem(value: 'completed', child: Text('Completed')),
              const PopupMenuItem(value: 'cancelled', child: Text('Cancelled')),
              const PopupMenuItem(value: 'accepted', child: Text('Active')),
            ],
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.error_outline, size: 64, color: Colors.grey),
        const SizedBox(height: 16),
        Text(_error!, style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: _loadHistory, child: const Text('Retry')),
      ]));
    }
    if (_rides.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.history, size: 64, color: Colors.grey),
        const SizedBox(height: 16),
        const Text('No ride history found', style: TextStyle(fontSize: 18, color: Colors.grey)),
        const SizedBox(height: 8),
        const Text('Your completed rides will appear here', style: TextStyle(color: Colors.grey)),
      ]));
    }
    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _rides.length,
        itemBuilder: (context, index) => _buildRideCard(_rides[index]),
      ),
    );
  }

  Widget _buildRideCard(dynamic ride) {
    final status = ride['status'] ?? '';
    final isCompleted = status == 'completed';
    final isCancelled = status == 'cancelled';
    Color statusColor;
    IconData statusIcon;
    if (isCompleted) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else if (isCancelled) {
      statusColor = Colors.red;
      statusIcon = Icons.cancel;
    } else {
      statusColor = Colors.orange;
      statusIcon = Icons.access_time;
    }
    final formattedDate = _formatDate(ride['created_at']);
    final driver = ride['driver'];
    final driverName = driver != null ? (driver['name'] ?? 'N/A') : 'N/A';
    final fare = parseApiDouble(ride['fare']);
    final actualFare = ride['actual_fare'];
    final displayFare = actualFare != null ? parseApiDouble(actualFare) : fare;
    final pickup = ride['pickup_address'] ?? '';
    final destination = ride['destination_address'] ?? '';
    final cancelledBy = ride['cancelled_by'];
    final cancelReason = ride['cancellation_reason'];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showRideDetail(ride),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(statusIcon, color: statusColor, size: 20),
              const SizedBox(width: 8),
              Text(status.toUpperCase(), style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 13)),
              const Spacer(),
              Text('\u09F3' + displayFare.toStringAsFixed(0), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.circle, size: 10, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(child: Text(pickup.isNotEmpty ? pickup : 'Pickup location', style: const TextStyle(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            const Padding(padding: EdgeInsets.only(left: 4), child: Text('|', style: TextStyle(color: Colors.grey, fontSize: 10))),
            Row(children: [
              const Icon(Icons.location_on, size: 12, color: Colors.red),
              const SizedBox(width: 8),
              Expanded(child: Text(destination.isNotEmpty ? destination : 'Destination', style: const TextStyle(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            const Divider(height: 16),
            Row(children: [
              const Icon(Icons.person, size: 16, color: Colors.grey),
              const SizedBox(width: 4),
              Text('Driver: ' + driverName, style: const TextStyle(color: Colors.grey, fontSize: 13)),
              const Spacer(),
              if (formattedDate.isNotEmpty) Text(formattedDate, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
            if (isCancelled && cancelledBy != null)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text('Cancelled by: ' + cancelledBy + (cancelReason != null ? ' - ' + cancelReason : ''), style: const TextStyle(color: Colors.red, fontSize: 12, fontStyle: FontStyle.italic))),
          ]),
        ),
      ),
    );
  }

  void _showRideDetail(dynamic ride) {
    final isCompleted = (ride['status'] ?? '') == 'completed';
    Get.bottomSheet(
      SafeArea(
        child: Container(
          // Cap the height and keep the action buttons pinned so the Close
          // button is always visible/reachable on every screen size.
          constraints: BoxConstraints(maxHeight: Get.height * 0.85),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(height: 16),
              const Text('Ride Details',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              // Details scroll if they're long \u2014 never pushes the buttons off.
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _detailRow('Status', ride['status'] ?? ''),
                      _detailRow('Pickup', ride['pickup_address'] ?? ''),
                      _detailRow('Destination', ride['destination_address'] ?? ''),
                      _detailRow('Fare', '\u09F3' + parseApiDouble(ride['actual_fare'] ?? ride['fare']).toStringAsFixed(0)),
                      _detailRow('Payment', ride['payment_status'] ?? 'N/A'),
                      if (ride['distance_km'] != null) _detailRow('Distance', ride['distance_km'].toString() + ' km'),
                      if (ride['duration_minutes'] != null) _detailRow('Duration', ride['duration_minutes'].toString() + ' min'),
                      if (ride['cancelled_by'] != null) _detailRow('Cancelled by', ride['cancelled_by']),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (isCompleted && ride['id'] != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _downloadReceipt(ride['id']),
                    icon: const Icon(Icons.receipt_long, size: 18),
                    label: const Text('Download Receipt (PDF)'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF10713C),
                      side: const BorderSide(color: Color(0xFF10713C)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Get.back(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }

  Future<void> _downloadReceipt(dynamic rideIdRaw) async {
    final rideId = rideIdRaw is num ? rideIdRaw.toInt() : int.tryParse('$rideIdRaw');
    if (rideId == null) return;

    Get.snackbar('Receipt', 'Preparing your receipt…',
        duration: const Duration(seconds: 1));
    final bytes = await _apiService.downloadReceiptBytes(rideId);
    if (bytes == null) {
      Get.snackbar('Receipt', 'Could not generate the receipt. Please try again.',
          backgroundColor: Colors.red, colorText: Colors.white);
      return;
    }
    try {
      final path = '${Directory.systemTemp.path}/goride_receipt_$rideId.pdf';
      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([XFile(path)], subject: 'GoRide Receipt #$rideId');
    } catch (e) {
      Get.snackbar('Receipt', 'Could not open the receipt.',
          backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 100, child: Text(label, style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w500))),
        Expanded(child: Text(value)),
      ]),
    );
  }
}
