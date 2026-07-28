import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/api_service.dart';
import '../services/saved_addresses_service.dart';
import '../utils/num_utils.dart';
import 'saved_addresses_screen.dart';

class PayLaterScreen extends StatefulWidget {
  const PayLaterScreen({super.key});

  @override
  State<PayLaterScreen> createState() => _PayLaterScreenState();
}

class _PayLaterScreenState extends State<PayLaterScreen> {
  final ApiService _api = Get.find<ApiService>();

  bool _loading = true;
  double _limit = 0; // admin-set PayLater ceiling (0 = feature off)
  double _due = 0; // outstanding amount owed (negative wallet balance)
  double _balance = 0; // current wallet balance
  List<Map<String, dynamic>> _transactions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final bal = await _api.getWalletBalance();
      if (bal.statusCode == 200 && bal.data is Map) {
        _limit = parseApiDouble(bal.data['pay_later_limit']);
        _due = parseApiDouble(bal.data['due']);
        _balance = parseApiDouble(bal.data['balance']);
      }
      final tx = await _api.getWalletTransactions();
      if (tx.statusCode == 200 && tx.data is Map) {
        // transactions is a paginator: { transactions: { data: [...] } }
        final raw = tx.data['transactions'];
        final list = (raw is Map ? raw['data'] : raw);
        if (list is List) {
          _transactions = list
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList();
        }
      }
    } catch (_) {
      // leave defaults; the UI shows an empty/disabled state
    }
    if (mounted) setState(() => _loading = false);
  }

  double get _available => (_limit - _due).clamp(0, _limit);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pay Later'),
        backgroundColor: const Color(0xFF10713C),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _limit <= 0 ? _disabledView() : _activeView(),
            ),
    );
  }

  // Shown when the admin has not enabled PayLater (limit = 0).
  Widget _disabledView() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 60),
        Icon(Icons.schedule, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 16),
        const Text("Pay Later isn't available yet",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          "Your account doesn't have a Pay Later limit right now. "
          'Ride and pay by wallet, bKash/Nagad or cash in the meantime.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _activeView() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF10713C), Color(0xFF0A5E30)]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text('Available Credit', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 8),
                Text('৳${_available.toStringAsFixed(0)}',
                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Limit: ৳${_limit.toStringAsFixed(0)}  •  Wallet: ৳${_balance.toStringAsFixed(0)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          if (_due > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.red[700]),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('You owe ৳${_due.toStringAsFixed(0)}. Top up your wallet to clear it.',
                        style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Text('Recent Transactions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (_transactions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No transactions yet', style: TextStyle(color: Colors.grey[500]))),
            )
          else
            ..._transactions.map(_buildTransactionTile),
          const SizedBox(height: 24),
          if (_due > 0)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _settleDue,
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10713C),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text('Pay Now (৳${_due.toStringAsFixed(0)})',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }

  // Clears the outstanding PayLater due by topping the wallet up by that amount.
  Future<void> _settleDue() async {
    final amount = _due;
    if (amount <= 0) return;
    try {
      final res = await _api.topUpWallet(amount);
      if (res.statusCode == 200) {
        Get.snackbar('Payment started', 'Complete the top-up to clear your ৳${amount.toStringAsFixed(0)} due.',
            snackPosition: SnackPosition.BOTTOM);
        await _load();
      } else {
        Get.snackbar('Failed', (res.data is Map ? res.data['message'] : null)?.toString() ?? 'Could not start payment',
            snackPosition: SnackPosition.BOTTOM);
      }
    } catch (e) {
      Get.snackbar('Error', '$e', snackPosition: SnackPosition.BOTTOM);
    }
  }

  Widget _buildTransactionTile(Map<String, dynamic> tx) {
    final type = (tx['type'] ?? '').toString();
    final isCredit = type == 'credit';
    final amount = parseApiDouble(tx['amount']);
    final desc = (tx['description'] ?? tx['reference'] ?? (isCredit ? 'Top up' : 'Ride payment')).toString();
    final date = (tx['created_at'] ?? '').toString();
    final shortDate = date.length >= 10 ? date.substring(0, 10) : date;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: (isCredit ? Colors.green : Colors.red)[50], borderRadius: BorderRadius.circular(8)),
            child: Icon(isCredit ? Icons.add : Icons.directions_car,
                color: (isCredit ? Colors.green : Colors.red)[700], size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(desc, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(shortDate, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
          ),
          Text('${isCredit ? '+' : '-'}৳${amount.abs().toStringAsFixed(0)}',
              style: TextStyle(fontWeight: FontWeight.bold, color: isCredit ? Colors.green[700] : Colors.red)),
        ],
      ),
    );
  }
}

class SavedAddressScreen extends StatefulWidget {
  const SavedAddressScreen({super.key});

  @override
  State<SavedAddressScreen> createState() => _SavedAddressScreenState();
}

class _SavedAddressScreenState extends State<SavedAddressScreen> {
  final SavedAddressesService _service = Get.find<SavedAddressesService>();

  IconData _getIcon(String iconName) {
    switch (iconName) {
      case 'work':
      case 'business':
        return Icons.work;
      case 'gym':
      case 'fitness_center':
        return Icons.fitness_center;
      case 'star':
        return Icons.star;
      case 'location_on':
        return Icons.location_on;
      case 'home':
      default:
        return Icons.home;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Addresses'),
        backgroundColor: const Color(0xFF10713C),
        foregroundColor: Colors.white,
      ),
      body: Obx(() {
        if (_service.isLoading.value && _service.addresses.isEmpty) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF10713C)));
        }
        if (_service.addresses.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(color: const Color(0xFF10713C).withValues(alpha: 0.08), shape: BoxShape.circle),
                    child: const Icon(Icons.bookmark_border, size: 40, color: Color(0xFF10713C)),
                  ),
                  const SizedBox(height: 20),
                  const Text('No Saved Addresses', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Add your home, work, or favorite locations for quick booking.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => Get.to(() => const SavedAddressesScreen())?.then((_) => _service.fetchAddresses()),
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('Manage Addresses', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10713C), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _service.addresses.length,
          itemBuilder: (context, index) {
            final addr = _service.addresses[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: addr.isDefault ? const Color(0xFF10713C) : Colors.grey[200]!, width: addr.isDefault ? 1.5 : 1),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFF10713C).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: Icon(_getIcon(addr.iconName), color: const Color(0xFF10713C)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(addr.label.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF10713C), letterSpacing: 0.5)),
                            if (addr.isDefault) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: const Color(0xFF10713C).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                child: const Text('DEFAULT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF10713C))),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(addr.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(addr.address, style: TextStyle(color: Colors.grey[600], fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey[400]),
                ],
              ),
            );
          },
        );
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Get.to(() => const SavedAddressesScreen())?.then((_) => _service.fetchAddresses()),
        backgroundColor: const Color(0xFF10713C),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
