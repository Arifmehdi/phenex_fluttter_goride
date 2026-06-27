import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/api_service.dart';

/// Show post-trip rating bottom sheet.
/// [mode] = 'rate_driver' or 'rate_rider'
Future<void> showPostTripRating({
  required BuildContext context,
  required String mode,
  required int rideRequestId,
  required int targetUserId,
  required String targetName,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: false,
    builder: (ctx) => _RatingSheet(
      mode: mode,
      rideRequestId: rideRequestId,
      targetUserId: targetUserId,
      targetName: targetName,
    ),
  );
}

class _RatingSheet extends StatefulWidget {
  final String mode;
  final int rideRequestId;
  final int targetUserId;
  final String targetName;

  const _RatingSheet({
    required this.mode,
    required this.rideRequestId,
    required this.targetUserId,
    required this.targetName,
  });

  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> {
  final _api = Get.find<ApiService>();
  final _reviewController = TextEditingController();

  int _stars = 0;
  final Set<String> _selectedTags = {};
  bool _submitting = false;

  static const Map<String, List<String>> _tags = {
    'rate_driver': ['On time', 'Polite', 'Clean car', 'Safe driving', 'Good route', 'Professional'],
    'rate_rider': ['Polite', 'Ready on time', 'No mess', 'Good directions', 'Friendly', 'Easy to find'],
  };

  bool get _isDriver => widget.mode == 'rate_driver';

  Future<void> _submit() async {
    if (_stars == 0) {
      Get.snackbar('Please rate', 'Tap a star to give a rating.',
          backgroundColor: Colors.orange, colorText: Colors.white);
      return;
    }
    setState(() => _submitting = true);

    if (_isDriver) {
      await _api.submitDriverRatingWithTags(
        rideRequestId: widget.rideRequestId,
        driverId: widget.targetUserId,
        rating: _stars,
        tags: _selectedTags.toList(),
        review: _reviewController.text.trim().isNotEmpty ? _reviewController.text.trim() : null,
      );
    } else {
      await _api.submitRiderRating(
        rideRequestId: widget.rideRequestId,
        riderId: widget.targetUserId,
        rating: _stars,
        tags: _selectedTags.toList(),
        review: _reviewController.text.trim().isNotEmpty ? _reviewController.text.trim() : null,
      );
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tagList = _tags[widget.mode] ?? [];
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
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
          const SizedBox(height: 20),

          // Avatar + name
          CircleAvatar(
            radius: 32,
            backgroundColor: const Color(0xFF10713C).withValues(alpha: 0.1),
            child: Text(
              widget.targetName.isNotEmpty ? widget.targetName[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF10713C)),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _isDriver ? 'How was ${widget.targetName}?' : 'Rate your passenger',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            _isDriver ? 'Rate your driver' : 'Rate ${widget.targetName}',
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
          const SizedBox(height: 20),

          // Stars
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) => GestureDetector(
              onTap: () => setState(() => _stars = i + 1),
              child: Icon(
                i < _stars ? Icons.star_rounded : Icons.star_outline_rounded,
                color: Colors.amber,
                size: 42,
              ),
            )),
          ),
          const SizedBox(height: 16),

          // Tag chips
          Wrap(
            spacing: 8, runSpacing: 8,
            children: tagList.map((tag) {
              final selected = _selectedTags.contains(tag);
              return GestureDetector(
                onTap: () => setState(() {
                  selected ? _selectedTags.remove(tag) : _selectedTags.add(tag);
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFF10713C) : Colors.white,
                    border: Border.all(color: selected ? const Color(0xFF10713C) : Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(tag,
                    style: TextStyle(
                      fontSize: 13,
                      color: selected ? Colors.white : Colors.black87,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    )),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // Optional review text
          TextField(
            controller: _reviewController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Add a comment (optional)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF10713C))),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(height: 16),

          // Submit
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10713C),
                disabledBackgroundColor: Colors.grey[300],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _submitting
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Submit Rating',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _submitting ? null : () => Navigator.pop(context),
            child: const Text('Skip', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }
}
