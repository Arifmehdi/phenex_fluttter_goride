import 'package:flutter/material.dart';

class PayLaterScreen extends StatefulWidget {
  const PayLaterScreen({super.key});

  @override
  State<PayLaterScreen> createState() => _PayLaterScreenState();
}

class _PayLaterScreenState extends State<PayLaterScreen> {
  final double _creditLimit = 50000;
  final double _usedAmount = 12500;
  final List<Map<String, dynamic>> _transactions = [
    {'date': '10 Apr', 'desc': 'Airport Trip', 'amount': -850.0},
    {'date': '08 Apr', 'desc': 'Gulshan to Dhanmondi', 'amount': -450.0},
    {'date': '05 Apr', 'desc': 'Office Commute', 'amount': -320.0},
    {'date': '03 Apr', 'desc': 'Shopping Mall', 'amount': -280.0},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pay Later'),
        backgroundColor: const Color(0xFF10713C),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
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
                  Text('\৳${(_creditLimit - _usedAmount).toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Limit: \৳${_creditLimit.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('Recent Transactions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ..._transactions.map((tx) => _buildTransactionTile(tx['date'], tx['desc'], tx['amount'])),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10713C), padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Pay Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionTile(String date, String desc, double amount) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.directions_car, color: Colors.red[700], size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(desc, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(date, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
          ),
          Text('\৳${amount.abs()}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
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
  final List<Map<String, dynamic>> _addresses = [
    {'type': 'Home', 'address': 'House 12, Road 5, Gulshan 2, Dhaka', 'icon': Icons.home},
    {'type': 'Office', 'address': 'Prime Tower, Banani, Dhaka', 'icon': Icons.business},
    {'type': 'Gym', 'address': 'Fitness First, Dhanmondi', 'icon': Icons.fitness_center},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Addresses'),
        backgroundColor: const Color(0xFF10713C),
        foregroundColor: Colors.white,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _addresses.length,
        itemBuilder: (context, index) {
          final addr = _addresses[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFF10713C).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: Icon(addr['icon'], color: const Color(0xFF10713C)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(addr['type'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(addr['address'], style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    ],
                  ),
                ),
                Icon(Icons.edit, color: Colors.grey[400], size: 18),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: const Color(0xFF10713C),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class MembershipScreen extends StatefulWidget {
  const MembershipScreen({super.key});

  @override
  State<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends State<MembershipScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Membership'),
        backgroundColor: const Color(0xFF10713C),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFD2691E), Color(0xFF8B4513)]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Text('Bronze Member', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Valid till Dec 2026', style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildBenefitTile(Icons.discount, '5% discount on rides'),
            _buildBenefitTile(Icons.bookmark, 'Priority booking'),
            _buildBenefitTile(Icons.support_agent, '24/7 support'),
            _buildBenefitTile(Icons.credit_card, 'Exclusive offers'),
            const SizedBox(height: 24),
            const Text('Upgrade to Silver for more benefits!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[700], padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Upgrade Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBenefitTile(IconData icon, String title) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF10713C)),
          const SizedBox(width: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class PointsScreen extends StatefulWidget {
  const PointsScreen({super.key});

  @override
  State<PointsScreen> createState() => _PointsScreenState();
}

class _PointsScreenState extends State<PointsScreen> {
  final int _totalPoints = 1250;
  final List<Map<String, dynamic>> _rewards = [
    {'points': 100, 'reward': '\৳50 off', 'icon': Icons.local_offer},
    {'points': 250, 'reward': 'Free airport ride', 'icon': Icons.flight},
    {'points': 500, 'reward': '\৳200 off', 'icon': Icons.discount},
    {'points': 1000, 'reward': 'Free day pass', 'icon': Icons.card_giftcard},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Points'),
        backgroundColor: const Color(0xFF10713C),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF10713C),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 40),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Your Points', style: TextStyle(color: Colors.white70)),
                      Text('$_totalPoints', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('Redeem Rewards', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ..._rewards.map((item) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(10)),
                    child: Icon(item['icon'], color: Colors.amber[700]),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(item['reward'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xFF10713C), borderRadius: BorderRadius.circular(20)),
                    child: Text('${item['points']} pts', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}