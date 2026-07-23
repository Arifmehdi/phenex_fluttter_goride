import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_service.dart';
import '../utils/num_utils.dart';

const _kBrand = Color(0xFF10713C);

/// Rewards & Invite — loyalty tier + points from completed rides, plus the
/// referral program ("invite a friend, both earn"), the same pattern used
/// by Uber Rewards / Pathao points.
class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  final _api = Get.find<ApiService>();
  Map<String, dynamic> _data = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final res = await _api.getRewards();
    if (!mounted) return;
    if (res.statusCode == 200 && res.data is Map && res.data['success'] == true) {
      setState(() {
        _data = Map<String, dynamic>.from(res.data);
        _loading = false;
      });
    } else {
      setState(() { _error = 'Could not load rewards'; _loading = false; });
    }
  }

  Color _tierColor(String tier) => switch (tier) {
        'Platinum' => const Color(0xFF7B8794),
        'Gold' => const Color(0xFFD4A017),
        'Silver' => const Color(0xFF9E9E9E),
        _ => const Color(0xFFB08D57), // Bronze
      };

  @override
  Widget build(BuildContext context) {
    final tier = _data['tier']?.toString() ?? 'Bronze';
    final points = parseApiInt(_data['points']);
    final nextTier = _data['next_tier']?.toString();
    final nextPoints = parseApiInt(_data['next_tier_points']);
    final code = _data['referral_code']?.toString();
    final link = _data['referral_link']?.toString();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Rewards & Invite'),
        backgroundColor: _kBrand,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kBrand))
          : _error != null
              ? Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(_error!, style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 12),
                    ElevatedButton(
                        onPressed: _load,
                        style: ElevatedButton.styleFrom(backgroundColor: _kBrand),
                        child: const Text('Retry', style: TextStyle(color: Colors.white))),
                  ]),
                )
              : RefreshIndicator(
                  color: _kBrand,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // ── Tier card ──
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_tierColor(tier), _tierColor(tier).withValues(alpha: 0.7)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Icon(Icons.workspace_premium, color: Colors.white, size: 30),
                              const SizedBox(width: 10),
                              Text('$tier Member',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold)),
                            ]),
                            const SizedBox(height: 14),
                            Text('$points points',
                                style: const TextStyle(color: Colors.white, fontSize: 16)),
                            Text('${_data['total_rides'] ?? 0} completed rides',
                                style: const TextStyle(color: Colors.white70, fontSize: 13)),
                            if (nextTier != null) ...[
                              const SizedBox(height: 14),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: nextPoints > 0 ? (points / nextPoints).clamp(0.0, 1.0) : 0,
                                  minHeight: 8,
                                  backgroundColor: Colors.white24,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text('${nextPoints - points} points to $nextTier',
                                  style: const TextStyle(color: Colors.white, fontSize: 12)),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _kBrand.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(children: [
                          const Icon(Icons.info_outline, color: _kBrand, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Earn 1 point for every ৳10 of completed ride fare. '
                              'Tiers: Bronze → Silver (500) → Gold (2,000) → Platinum (5,000).',
                              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                            ),
                          ),
                        ]),
                      ),

                      // ── Referral / Invite ──
                      if (code != null && code.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Text('Invite friends, earn ৳50',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(
                          'Your friend signs up with your code — when they complete '
                          'their first ride, you get ৳50 in your wallet.',
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _kBrand, width: 1.4),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('YOUR CODE',
                                        style: TextStyle(
                                            fontSize: 10,
                                            letterSpacing: 1,
                                            color: Colors.grey[500])),
                                    Text(code,
                                        style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 2,
                                            color: _kBrand)),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy, color: _kBrand),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: code));
                                  Get.snackbar('Copied', 'Referral code copied',
                                      backgroundColor: _kBrand, colorText: Colors.white);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              SharePlus.instance.share(ShareParams(
                                text: 'Ride with GoRide! 🚗 Sign up with my code '
                                    '$code and I earn ৳50 when you take your first ride.'
                                    '${link != null ? '\n$link' : ''}',
                              ));
                            },
                            icon: const Icon(Icons.share, color: Colors.white),
                            label: const Text('Share Invite',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kBrand,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(children: [
                          Expanded(
                              child: _miniStat('Friends joined',
                                  '${_data['total_referred'] ?? 0}', Icons.group_add)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _miniStat('Referral earned',
                                  '৳${parseApiDouble(_data['referral_earned']).toStringAsFixed(0)}',
                                  Icons.payments)),
                        ]),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _miniStat(String label, String value, IconData icon) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(children: [
          Icon(icon, color: _kBrand, size: 22),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ]),
      );
}
