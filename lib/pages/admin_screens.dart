import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/api_service.dart';
import '../utils/num_utils.dart';

const _kBrand = Color(0xFF10713C);

Widget _loading() => const Center(child: CircularProgressIndicator(color: _kBrand));

Widget _errorRetry(String msg, VoidCallback onRetry) => Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.error_outline, size: 56, color: Colors.grey),
        const SizedBox(height: 12),
        Text(msg, style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: onRetry,
          style: ElevatedButton.styleFrom(backgroundColor: _kBrand),
          child: const Text('Retry', style: TextStyle(color: Colors.white)),
        ),
      ]),
    );

Widget _empty(IconData icon, String msg) => Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 56, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text(msg, style: TextStyle(color: Colors.grey[500])),
      ]),
    );

void _toast(String title, String msg, {bool error = false}) => Get.snackbar(
      title, msg,
      backgroundColor: error ? Colors.red : _kBrand,
      colorText: Colors.white,
      duration: const Duration(seconds: 3),
    );

// ═══════════════════════════════════════════════════════════════════
//  DRIVER PAYOUTS — pending dues, one-tap pay to driver wallet
// ═══════════════════════════════════════════════════════════════════

class AdminPayoutsScreen extends StatefulWidget {
  const AdminPayoutsScreen({super.key});
  @override
  State<AdminPayoutsScreen> createState() => _AdminPayoutsScreenState();
}

class _AdminPayoutsScreenState extends State<AdminPayoutsScreen> {
  final _api = Get.find<ApiService>();
  List<Map<String, dynamic>> _payouts = [];
  double _totalPending = 0;
  bool _loadingData = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loadingData = true; _error = null; });
    final res = await _api.getPendingPayouts();
    if (!mounted) return;
    if (res.statusCode == 200 && res.data is Map && res.data['success'] == true) {
      final list = (res.data['payouts'] as List? ?? []);
      setState(() {
        _payouts = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _totalPending = parseApiDouble(res.data['total_pending']);
        _loadingData = false;
      });
    } else {
      setState(() { _error = 'Failed to load payouts'; _loadingData = false; });
    }
  }

  Future<void> _pay(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Process payout?'),
        content: Text(
            'Pay ৳${parseApiDouble(p['net_amount']).toStringAsFixed(0)} to ${(p['driver'] as Map?)?['name'] ?? 'driver'}\'s wallet?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: _kBrand),
              child: const Text('Pay Now', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (ok != true) return;
    final res = await _api.processPayout(p['id'] as int);
    if (res.statusCode == 200 && res.data is Map && res.data['success'] == true) {
      _toast('Paid', 'Payout sent to driver wallet');
      _load();
    } else {
      _toast('Error',
          (res.data is Map ? res.data['message'] : null)?.toString() ?? 'Payout failed',
          error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Driver Payouts')),
      body: _loadingData
          ? _loading()
          : _error != null
              ? _errorRetry(_error!, _load)
              : Column(children: [
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _kBrand.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _kBrand.withValues(alpha: 0.25)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Total pending',
                          style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                      Text('৳${_totalPending.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 26, fontWeight: FontWeight.bold, color: _kBrand)),
                    ]),
                  ),
                  Expanded(
                    child: _payouts.isEmpty
                        ? _empty(Icons.account_balance_wallet, 'No pending payouts')
                        : RefreshIndicator(
                            color: _kBrand,
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              itemCount: _payouts.length,
                              itemBuilder: (context, i) {
                                final p = _payouts[i];
                                final driver = p['driver'] as Map?;
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: ListTile(
                                    title: Text(driver?['name']?.toString() ?? 'Driver',
                                        style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text(
                                        '${p['period_from']} → ${p['period_to']}\nGross ৳${parseApiDouble(p['gross_earnings']).toStringAsFixed(0)} − commission ৳${parseApiDouble(p['commission']).toStringAsFixed(0)}'),
                                    isThreeLine: true,
                                    trailing: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                            '৳${parseApiDouble(p['net_amount']).toStringAsFixed(0)}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold, color: _kBrand)),
                                        TextButton(
                                            onPressed: () => _pay(p),
                                            child: const Text('PAY')),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  ADMIN TICKET DETAIL — thread view + reply + status change
// ═══════════════════════════════════════════════════════════════════

class AdminTicketDetailScreen extends StatefulWidget {
  final int ticketId;
  const AdminTicketDetailScreen({super.key, required this.ticketId});
  @override
  State<AdminTicketDetailScreen> createState() => _AdminTicketDetailScreenState();
}

class _AdminTicketDetailScreenState extends State<AdminTicketDetailScreen> {
  final _api = Get.find<ApiService>();
  final _replyCtrl = TextEditingController();
  Map<String, dynamic>? _ticket;
  bool _loadingData = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await _api.getSupportTicketDetail(widget.ticketId);
    if (!mounted) return;
    setState(() {
      _ticket = (res.statusCode == 200 && res.data is Map && res.data['success'] == true)
          ? Map<String, dynamic>.from(res.data['ticket'])
          : null;
      _loadingData = false;
    });
  }

  Future<void> _reply() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    final res = await _api.replySupportTicket(widget.ticketId, text);
    if (res.statusCode == 200 || res.statusCode == 201) {
      _replyCtrl.clear();
      await _load();
    } else {
      _toast('Error', 'Reply failed', error: true);
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _setStatus(String status) async {
    final res = await _api.updateSupportTicketStatus(widget.ticketId, status: status);
    if (res.statusCode == 200) {
      _toast('Updated', 'Ticket marked ${status.replaceAll('_', ' ')}');
      _load();
    } else {
      _toast('Error', 'Could not update status', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _ticket?['status']?.toString() ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(_ticket?['subject']?.toString() ?? 'Ticket'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.flag),
            onSelected: _setStatus,
            itemBuilder: (_) => ['open', 'in_progress', 'resolved', 'closed']
                .map((s) => PopupMenuItem(
                    value: s,
                    child: Text('Mark ${s.replaceAll('_', ' ')}',
                        style: TextStyle(
                            fontWeight:
                                s == status ? FontWeight.bold : FontWeight.normal))))
                .toList(),
          ),
        ],
      ),
      body: _loadingData
          ? _loading()
          : _ticket == null
              ? _empty(Icons.error_outline, 'Ticket not found')
              : Column(children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _bubble(_ticket!['message']?.toString() ?? '',
                            isAdmin: false,
                            label: '${_ticket!['owner_type']} #${_ticket!['user_id']}'),
                        ...((_ticket!['replies'] as List? ?? []).map((r) {
                          final m = Map<String, dynamic>.from(r as Map);
                          final isAdmin = m['sender_type'] == 'admin';
                          return _bubble(m['message']?.toString() ?? '',
                              isAdmin: isAdmin,
                              label: isAdmin ? 'You (Support)' : 'Customer');
                        })),
                      ],
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                      child: Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _replyCtrl,
                            decoration: InputDecoration(
                              hintText: 'Reply to customer…',
                              border:
                                  OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _sending ? null : _reply,
                          icon: _sending
                              ? const SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.send, color: _kBrand),
                        ),
                      ]),
                    ),
                  ),
                ]),
    );
  }

  Widget _bubble(String text, {required bool isAdmin, required String label}) {
    return Align(
      alignment: isAdmin ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isAdmin ? _kBrand.withValues(alpha: 0.1) : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(text),
        ]),
      ),
    );
  }
}
