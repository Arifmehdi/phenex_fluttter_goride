import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../services/api_service.dart';

/// OTP verification screen.
/// Pass [mobile] and [onVerified] callback.
class OtpScreen extends StatefulWidget {
  final String mobile;
  final String purpose;
  final VoidCallback onVerified;

  const OtpScreen({
    super.key,
    required this.mobile,
    required this.onVerified,
    this.purpose = 'registration',
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _api = Get.find<ApiService>();
  final List<TextEditingController> _controllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  int _resendSeconds = 60;
  Timer? _timer;
  bool _verifying = false;
  bool _resending = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    super.dispose();
  }

  void _startTimer() {
    _resendSeconds = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendSeconds == 0) { t.cancel(); return; }
      if (mounted) setState(() => _resendSeconds--);
    });
  }

  String get _otp => _controllers.map((c) => c.text).join();

  Future<void> _verify() async {
    if (_otp.length < 6) {
      Get.snackbar('Enter OTP', 'Please enter the 6-digit code.',
          backgroundColor: Colors.orange, colorText: Colors.white);
      return;
    }
    setState(() => _verifying = true);
    final res = await _api.verifyOtp(widget.mobile, _otp, purpose: widget.purpose);
    setState(() => _verifying = false);

    if (res.statusCode == 200 && res.data['success'] == true) {
      widget.onVerified();
    } else {
      final msg = res.data?['message'] ?? 'Invalid OTP. Please try again.';
      Get.snackbar('Error', msg, backgroundColor: Colors.red, colorText: Colors.white);
      for (final c in _controllers) c.clear();
      _focusNodes[0].requestFocus();
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    final res = await _api.sendOtp(widget.mobile, purpose: widget.purpose);
    setState(() => _resending = false);

    if (res.statusCode == 200) {
      _startTimer();
      Get.snackbar('Sent', 'A new OTP has been sent to ${widget.mobile}.',
          backgroundColor: const Color(0xFF10713C), colorText: Colors.white);
    } else {
      Get.snackbar('Error', 'Could not resend OTP.', backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        title: const Text('Verify Phone', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF10713C).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.sms_outlined, size: 48, color: Color(0xFF10713C)),
            ),
            const SizedBox(height: 24),
            const Text('Enter Verification Code',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'We sent a 6-digit code to\n${widget.mobile}',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 15),
            ),
            const SizedBox(height: 36),

            // 6 OTP boxes
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(6, (i) => SizedBox(
                width: 46,
                height: 56,
                child: TextField(
                  controller: _controllers[i],
                  focusNode: _focusNodes[i],
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    counterText: '',
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF10713C), width: 2),
                    ),
                  ),
                  onChanged: (val) {
                    if (val.isNotEmpty && i < 5) {
                      _focusNodes[i + 1].requestFocus();
                    } else if (val.isEmpty && i > 0) {
                      _focusNodes[i - 1].requestFocus();
                    }
                    if (_otp.length == 6) _verify();
                  },
                ),
              )),
            ),
            const SizedBox(height: 36),

            // Verify button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _verifying ? null : _verify,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10713C),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _verifying
                    ? const SizedBox(width: 24, height: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Verify', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 20),

            // Resend
            _resendSeconds > 0
                ? Text('Resend code in ${_resendSeconds}s',
                    style: TextStyle(color: Colors.grey[500]))
                : _resending
                    ? const CircularProgressIndicator(color: Color(0xFF10713C), strokeWidth: 2)
                    : TextButton(
                        onPressed: _resend,
                        child: const Text('Resend Code',
                            style: TextStyle(color: Color(0xFF10713C), fontWeight: FontWeight.w600)),
                      ),
          ],
        ),
      ),
    );
  }
}
