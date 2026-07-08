import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/api_service.dart';

const _kBrandColor = Color(0xFF10713C);

const List<String> _kTicketCategories = ['general', 'payment', 'ride', 'account', 'other'];

Color _statusColor(String status) {
  switch (status) {
    case 'open':
      return Colors.blue;
    case 'in_progress':
      return Colors.orange;
    case 'resolved':
      return Colors.green;
    case 'closed':
      return Colors.grey;
    default:
      return Colors.grey;
  }
}

Color _priorityColor(String priority) {
  switch (priority) {
    case 'urgent':
      return Colors.red;
    case 'high':
      return Colors.deepOrange;
    case 'low':
      return Colors.green;
    default:
      return Colors.blueGrey;
  }
}

/// User-facing "My Support Tickets" — list + create + reply thread.
/// Reachable from the sidebar's "Help & Support" entry for every role.
class MySupportTicketsScreen extends StatefulWidget {
  const MySupportTicketsScreen({super.key});

  @override
  State<MySupportTicketsScreen> createState() => _MySupportTicketsScreenState();
}

class _MySupportTicketsScreenState extends State<MySupportTicketsScreen> {
  final ApiService _apiService = Get.find<ApiService>();
  List<Map<String, dynamic>> _tickets = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTickets();
  }

  Future<void> _loadTickets() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await _apiService.getMySupportTickets();
      if (res.statusCode == 200 && res.data['success'] == true) {
        final raw = res.data['tickets'];
        final list = (raw is Map ? raw['data'] : raw) as List? ?? [];
        setState(() {
          _tickets = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load your tickets';
          _isLoading = false;
        });
      }
    } catch (_) {
      setState(() {
        _error = 'Connection error';
        _isLoading = false;
      });
    }
  }

  Future<void> _openNewTicketSheet() async {
    final subjectController = TextEditingController();
    final messageController = TextEditingController();
    String category = _kTicketCategories.first;

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: StatefulBuilder(
          builder: (context, setSheetState) => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('New Support Ticket',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextField(
                  controller: subjectController,
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: _kTicketCategories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c[0].toUpperCase() + c.substring(1))))
                      .toList(),
                  onChanged: (v) => setSheetState(() => category = v ?? category),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: messageController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Describe your issue',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _kBrandColor),
                    onPressed: () async {
                      final subject = subjectController.text.trim();
                      final message = messageController.text.trim();
                      if (subject.isEmpty || message.isEmpty) {
                        Get.snackbar('Error', 'Please fill in subject and message',
                            backgroundColor: Colors.red, colorText: Colors.white);
                        return;
                      }
                      final res = await _apiService.createSupportTicket(
                        subject: subject,
                        message: message,
                        category: category,
                      );
                      if (res.statusCode == 200 || res.statusCode == 201) {
                        Navigator.pop(context, true);
                      } else {
                        Get.snackbar('Error', res.data?['message'] ?? 'Could not create ticket',
                            backgroundColor: Colors.red, colorText: Colors.white);
                      }
                    },
                    child: const Text('Submit', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (created == true) {
      Get.snackbar('Success', 'Your ticket has been submitted',
          backgroundColor: _kBrandColor, colorText: Colors.white);
      _loadTickets();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Support Tickets'),
        backgroundColor: _kBrandColor,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewTicketSheet,
        backgroundColor: _kBrandColor,
        icon: const Icon(Icons.add),
        label: const Text('New Ticket'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: _kBrandColor));
    if (_error != null) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _loadTickets, child: const Text('Retry')),
        ]),
      );
    }
    if (_tickets.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.support_agent, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('No support tickets yet', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          Text('Tap "New Ticket" if you need help', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ]),
      );
    }
    return RefreshIndicator(
      color: _kBrandColor,
      onRefresh: _loadTickets,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _tickets.length,
        itemBuilder: (context, index) {
          final t = _tickets[index];
          final status = t['status']?.toString() ?? 'open';
          final priority = t['priority']?.toString() ?? 'normal';
          final repliesCount = t['replies_count'] ?? 0;
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _priorityColor(priority).withOpacity(0.1),
                child: Icon(Icons.support_agent, color: _priorityColor(priority)),
              ),
              title: Text(t['subject']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${t['category'] ?? 'general'} • $repliesCount replies'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor(status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  status.replaceAll('_', ' '),
                  style: TextStyle(fontSize: 10, color: _statusColor(status), fontWeight: FontWeight.bold),
                ),
              ),
              onTap: () async {
                await Get.to(() => SupportTicketDetailScreen(ticketId: t['id'] as int));
                _loadTickets();
              },
            ),
          );
        },
      ),
    );
  }
}

class SupportTicketDetailScreen extends StatefulWidget {
  final int ticketId;
  const SupportTicketDetailScreen({super.key, required this.ticketId});

  @override
  State<SupportTicketDetailScreen> createState() => _SupportTicketDetailScreenState();
}

class _SupportTicketDetailScreenState extends State<SupportTicketDetailScreen> {
  final ApiService _apiService = Get.find<ApiService>();
  final TextEditingController _replyController = TextEditingController();
  Map<String, dynamic>? _ticket;
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadTicket();
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _loadTicket() async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiService.getSupportTicketDetail(widget.ticketId);
      if (res.statusCode == 200 && res.data['success'] == true) {
        setState(() {
          _ticket = Map<String, dynamic>.from(res.data['ticket']);
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendReply() async {
    final message = _replyController.text.trim();
    if (message.isEmpty) return;
    setState(() => _isSending = true);
    try {
      final res = await _apiService.replySupportTicket(widget.ticketId, message);
      if (res.statusCode == 200 || res.statusCode == 201) {
        _replyController.clear();
        await _loadTicket();
      } else {
        Get.snackbar('Error', res.data?['message'] ?? 'Could not send reply',
            backgroundColor: Colors.red, colorText: Colors.white);
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_ticket?['subject']?.toString() ?? 'Ticket'),
        backgroundColor: _kBrandColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _kBrandColor))
          : _ticket == null
              ? const Center(child: Text('Ticket not found'))
              : Column(
                  children: [
                    Expanded(child: _buildThread()),
                    _buildReplyBar(),
                  ],
                ),
    );
  }

  Widget _buildThread() {
    final replies = (_ticket!['replies'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final status = _ticket!['status']?.toString() ?? 'open';
    final priority = _ticket!['priority']?.toString() ?? 'normal';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _statusColor(status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(status.replaceAll('_', ' '),
                  style: TextStyle(fontSize: 11, color: _statusColor(status), fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _priorityColor(priority).withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(priority,
                  style: TextStyle(fontSize: 11, color: _priorityColor(priority), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _messageBubble(_ticket!['message']?.toString() ?? '', isMine: true, senderLabel: 'You'),
        const SizedBox(height: 12),
        ...replies.map((r) {
          final senderType = r['sender_type']?.toString() ?? '';
          final isAdmin = senderType == 'admin';
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _messageBubble(
              r['message']?.toString() ?? '',
              isMine: !isAdmin,
              senderLabel: isAdmin ? 'GoRide Support' : 'You',
            ),
          );
        }),
      ],
    );
  }

  Widget _messageBubble(String message, {required bool isMine, required String senderLabel}) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMine ? _kBrandColor.withOpacity(0.1) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(senderLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(message),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyBar() {
    final status = _ticket?['status']?.toString() ?? 'open';
    final isClosed = status == 'closed';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _replyController,
                enabled: !isClosed,
                decoration: InputDecoration(
                  hintText: isClosed ? 'This ticket is closed' : 'Type a reply...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: (_isSending || isClosed) ? null : _sendReply,
              icon: _isSending
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send, color: _kBrandColor),
            ),
          ],
        ),
      ),
    );
  }
}
