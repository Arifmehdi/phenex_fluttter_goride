import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/firebase_service.dart';

const _kBrand = Color(0xFF10713C);

/// Real-time in-trip chat between the passenger and the driver — the
/// per-ride chat pattern used by Uber/Pathao/inDrive/Obhai. Messages live
/// under the shared Firestore trip document, so delivery is instant on both
/// phones and works across the app's separate driver/passenger accounts.
class TripChatScreen extends StatefulWidget {
  final String tripId;
  /// 'driver' or 'rider' — which side of the conversation I am.
  final String myRole;
  final String myName;
  final String otherName;
  final String otherPhone;

  const TripChatScreen({
    super.key,
    required this.tripId,
    required this.myRole,
    required this.myName,
    required this.otherName,
    this.otherPhone = '',
  });

  @override
  State<TripChatScreen> createState() => _TripChatScreenState();
}

class _TripChatScreenState extends State<TripChatScreen> {
  final FirebaseService _firebaseService = Get.find<FirebaseService>();
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;

  /// One-tap canned replies, role-appropriate (like Uber's suggestion chips).
  List<String> get _quickReplies => widget.myRole == 'driver'
      ? const [
          "I'm on my way",
          "I've arrived",
          'Please come to the pickup point',
          'Traffic — a few minutes late',
        ]
      : const [
          "I'm coming",
          'Please wait 2 minutes',
          'Where are you now?',
          "I'm at the pickup point",
        ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _firebaseService.sendTripMessage(
        widget.tripId,
        senderRole: widget.myRole,
        senderName: widget.myName,
        text: text,
      );
      if (preset == null) _controller.clear();
    } on FirebaseException catch (e) {
      debugPrint('Trip chat send failed [${e.code}]: ${e.message}');
      Get.snackbar(
        'Message Not Sent',
        e.code == 'permission-denied'
            // Rules don't cover the messages subcollection yet — a server
            // config issue, not the user's network.
            ? 'Chat is not enabled on the server yet (Firestore rules).'
            : 'Could not send (${e.code}). Please try again.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
    } catch (e) {
      debugPrint('Trip chat send failed: $e');
      Get.snackbar('Error', 'Message not sent. Check your connection.',
          backgroundColor: Colors.red, colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _call() async {
    if (widget.otherPhone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: widget.otherPhone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final t = ts.toDate();
    final h = t.hour > 12 ? t.hour - 12 : (t.hour == 0 ? 12 : t.hour);
    final ampm = t.hour >= 12 ? 'PM' : 'AM';
    return '$h:${t.minute.toString().padLeft(2, '0')} $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: _kBrand,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white,
              backgroundImage: widget.myRole == 'driver'
                  ? const AssetImage('assets/passenger.png')
                  : null,
              child: widget.myRole == 'driver'
                  ? null
                  : const Icon(Icons.person, color: _kBrand, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.otherName,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis),
                  Text(
                    widget.myRole == 'driver' ? 'Passenger' : 'Your Driver',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (widget.otherPhone.isNotEmpty)
            IconButton(icon: const Icon(Icons.call), onPressed: _call),
        ],
      ),
      body: Column(
        children: [
          // ── Messages (live) ──
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firebaseService.streamTripMessages(widget.tripId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: _kBrand));
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 56, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text('No messages yet',
                            style: TextStyle(color: Colors.grey[500])),
                        const SizedBox(height: 4),
                        Text('Messages are only kept for this trip',
                            style: TextStyle(
                                color: Colors.grey[400], fontSize: 12)),
                      ],
                    ),
                  );
                }
                // reverse + newest-first query keeps the view pinned to the
                // bottom as new messages stream in.
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    final isMine = data['senderRole'] == widget.myRole;
                    return _bubble(
                      text: data['text']?.toString() ?? '',
                      time: _formatTime(data['sentAt'] as Timestamp?),
                      isMine: isMine,
                    );
                  },
                );
              },
            ),
          ),

          // ── Quick replies ──
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _quickReplies
                  .map((q) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          label: Text(q,
                              style: const TextStyle(
                                  fontSize: 12.5, color: _kBrand)),
                          backgroundColor: _kBrand.withValues(alpha: 0.08),
                          side: BorderSide(
                              color: _kBrand.withValues(alpha: 0.3)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          onPressed: () => _send(q),
                        ),
                      ))
                  .toList(),
            ),
          ),

          // ── Input bar ──
          Container(
            color: Colors.white,
            padding: EdgeInsets.only(
              left: 12,
              right: 8,
              top: 8,
              bottom: 8 + MediaQuery.of(context).padding.bottom,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Type a message…',
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 22,
                  backgroundColor: _kBrand,
                  child: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : IconButton(
                          icon: const Icon(Icons.send,
                              color: Colors.white, size: 20),
                          onPressed: _send,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble({required String text, required String time, required bool isMine}) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMine ? _kBrand : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05), blurRadius: 4),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: TextStyle(
                  color: isMine ? Colors.white : Colors.black87,
                  fontSize: 14.5),
            ),
            const SizedBox(height: 2),
            Text(
              time,
              style: TextStyle(
                  color: isMine ? Colors.white70 : Colors.grey[400],
                  fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
