import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:goride/services/chat_service.dart';
import 'package:goride/models/chat_conversation.dart';
import 'package:goride/pages/chat_message_screen.dart';
import 'package:goride/pages/chat_new_conversation_screen.dart';

class ChatConversationListScreen extends StatefulWidget {
  const ChatConversationListScreen({Key? key}) : super(key: key);

  @override
  State<ChatConversationListScreen> createState() => _ChatConversationListScreenState();
}

class _ChatConversationListScreenState extends State<ChatConversationListScreen> {
  final ChatService _chatService = Get.find<ChatService>();

  @override
  void initState() {
    super.initState();
    _chatService.loadConversations();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        backgroundColor: const Color(0xFF10713C),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: () => Get.to(() => const ChatNewConversationScreen()),
          ),
        ],
      ),
      body: Obx(() {
        if (_chatService.isLoadingConversations.value && _chatService.conversations.isEmpty) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF10713C)));
        }

        if (_chatService.conversations.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  'No conversations yet',
                  style: TextStyle(fontSize: 18, color: Colors.grey[500], fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start a chat with your driver or rider',
                  style: TextStyle(fontSize: 14, color: Colors.grey[400]),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => Get.to(() => const ChatNewConversationScreen()),
                  icon: const Icon(Icons.add),
                  label: const Text('New Chat'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10713C),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => _chatService.loadConversations(),
          color: const Color(0xFF10713C),
          child: ListView.builder(
            itemCount: _chatService.conversations.length,
            itemBuilder: (context, index) {
              final conv = _chatService.conversations[index];
              return _ConversationTile(conversation: conv);
            },
          ),
        );
      }),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final ChatConversation conversation;

  const _ConversationTile({required this.conversation});

  @override
  Widget build(BuildContext context) {
    final lastTime = conversation.lastMessageAt;
    String timeStr = '';
    if (lastTime != null) {
      final now = DateTime.now();
      final diff = now.difference(lastTime);
      if (diff.inDays > 0) {
        timeStr = '${diff.inDays}d ago';
      } else if (diff.inHours > 0) {
        timeStr = '${diff.inHours}h ago';
      } else if (diff.inMinutes > 0) {
        timeStr = '${diff.inMinutes}m ago';
      } else {
        timeStr = 'Just now';
      }
    }

    return InkWell(
      onTap: () {
        Get.to(() => ChatMessageScreen(conversation: conversation));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: const Color(0xFF10713C).withOpacity(0.1),
              backgroundImage: conversation.otherUser?.image != null
                  ? NetworkImage(conversation.otherUser!.image!)
                  : null,
              child: conversation.otherUser?.image == null
                  ? Text(
                      conversation.displayName.isNotEmpty ? conversation.displayName[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF10713C)),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          conversation.displayName,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (timeStr.isNotEmpty)
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 12,
                            color: conversation.unreadCount > 0 ? const Color(0xFF10713C) : Colors.grey[400],
                            fontWeight: conversation.unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.subtitle,
                          style: TextStyle(
                            fontSize: 14,
                            color: conversation.unreadCount > 0 ? Colors.black87 : Colors.grey[500],
                            fontWeight: conversation.unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (conversation.unreadCount > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10713C),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${conversation.unreadCount}',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
