import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/api_service.dart';

/// Shows a fare breakdown + promo code sheet before confirming a booking.
/// Returns true if user confirms, false/null if cancelled.
Future<Map<String, dynamic>?> showFareEstimateSheet({
  required BuildContext context,
  required String rideType,
  required double distanceKm,
  required double baseFare,
  required double perKmRate,
  required double totalFare,
}) async {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _FareEstimateSheet(
      rideType: rideType,
      distanceKm: distanceKm,
      baseFare: baseFare,
      perKmRate: perKmRate,
      totalFare: totalFare,
    ),
  );
}

class _FareEstimateSheet extends StatefulWidget {
  final String rideType;
  final double distanceKm;
  final double baseFare;
  final double perKmRate;
  final double totalFare;

  const _FareEstimateSheet({
    required this.rideType,
    required this.distanceKm,
    required this.baseFare,
    required this.perKmRate,
    required this.totalFare,
  });

  @override
  State<_FareEstimateSheet> createState() => _FareEstimateSheetState();
}

class _FareEstimateSheetState extends State<_FareEstimateSheet> {
  final _promoController = TextEditingController();
  final _api = Get.find<ApiService>();

  double _discount = 0;
  double _finalFare = 0;
  String _promoMessage = '';
  bool _promoValid = false;
  bool _checkingPromo = false;

  @override
  void initState() {
    super.initState();
    _finalFare = widget.totalFare;
  }

  @override
  void dispose() {
    _promoController.dispose();
    super.dispose();
  }

  Future<void> _applyPromo() async {
    final code = _promoController.text.trim();
    if (code.isEmpty) return;
    setState(() { _checkingPromo = true; _promoMessage = ''; _promoValid = false; });

    final res = await _api.validatePromo(code, widget.totalFare);
    setState(() { _checkingPromo = false; });

    if (res.statusCode == 200 && res.data['success'] == true) {
      setState(() {
        _discount = (res.data['discount'] as num).toDouble();
        _finalFare = (res.data['final_fare'] as num).toDouble();
        _promoMessage = '✅ ${res.data['description']}';
        _promoValid = true;
      });
    } else {
      setState(() {
        _discount = 0;
        _finalFare = widget.totalFare;
        _promoMessage = res.data?['message'] ?? 'Invalid promo code';
        _promoValid = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final distCharge = widget.distanceKm * widget.perKmRate;
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        top: 8, left: 20, right: 20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),

          // Header
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF10713C).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.receipt_long, color: Color(0xFF10713C)),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Fare Breakdown', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text(widget.rideType.toUpperCase(),
                  style: const TextStyle(color: Color(0xFF10713C), fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ]),
          const SizedBox(height: 20),

          // Fare rows
          _fareRow('Base fare', '৳${widget.baseFare.toStringAsFixed(0)}'),
          _fareRow('${widget.distanceKm.toStringAsFixed(1)} km × ৳${widget.perKmRate.toStringAsFixed(0)}/km',
              '৳${distCharge.toStringAsFixed(0)}'),
          if (_discount > 0)
            _fareRow('Promo discount', '−৳${_discount.toStringAsFixed(0)}',
                valueColor: Colors.green),
          const Divider(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Total', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              Text('৳${_finalFare.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF10713C))),
            ]),
          ),
          const SizedBox(height: 16),

          // Promo code
          Row(children: [
            Expanded(
              child: TextField(
                controller: _promoController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'Promo code',
                  prefixIcon: const Icon(Icons.local_offer_outlined, color: Color(0xFF10713C)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF10713C), width: 2)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _checkingPromo ? null : _applyPromo,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10713C),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              child: _checkingPromo
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Apply', style: TextStyle(color: Colors.white)),
            ),
          ]),
          if (_promoMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_promoMessage,
                    style: TextStyle(
                      color: _promoValid ? Colors.green : Colors.red,
                      fontSize: 12, fontWeight: FontWeight.w500,
                    )),
              ),
            ),
          const SizedBox(height: 20),

          // Confirm button
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, {
                'confirmed': true,
                'final_fare': _finalFare,
                'discount': _discount,
                'promo_code': _promoValid ? _promoController.text.trim() : null,
              }),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10713C),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(
                'Confirm Booking  •  ৳${_finalFare.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Widget _fareRow(String label, String value, {Color? valueColor}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
      Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
          color: valueColor ?? Colors.black87)),
    ]),
  );
}
