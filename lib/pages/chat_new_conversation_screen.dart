import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:goride/services/chat_service.dart';
import 'package:goride/models/chat_conversation.dart';
import 'package:goride/pages/chat_message_screen.dart';

class ChatNewConversationScreen extends StatefulWidget {
  const ChatNewConversationScreen({Key? key}) : super(key: key);

  @override
  State<ChatNewConversationScreen> createState() => _ChatNewConversationScreenState();
}

class _ChatNewConversationScreenState extends State<ChatNewConversationScreen> {
  final ChatService _chatService = Get.find<ChatService>();
  final TextEditingController _searchController = TextEditingController();
  final searchResults = <dynamic>[].obs;
  final isSearching = false.obs;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _search(String query) async {
    if (query.trim().isEmpty) {
      searchResults.clear();
      return;
    }
    isSearching.value = true;
    final results = await _chatService.searchUsers(query.trim());
    searchResults.value = results;
    isSearching.value = false;
  }

  void _startChat(int otherUserId, String userName) async {
    final conversationId = await _chatService.openOrCreatePrivateChat(otherUserId);
    if (conversationId != null) {
      final conv = _chatService.conversations.firstWhereOrNull((c) => c.id == conversationId);
      if (conv != null) {
        Get.off(() => ChatMessageScreen(conversation: conv));
      } else {
        final response = await _chatService.api.getConversation(conversationId);
        if (response.statusCode == 200 && response.data['success'] == true) {
          final newConv = ChatConversation.fromJson(response.data['conversation']);
          Get.off(() => ChatMessageScreen(conversation: newConv));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Chat'),
        backgroundColor: const Color(0xFF10713C),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search users by name or email...',
                prefixIcon: const Icon(Icons.search, color: Color(0xFF10713C)),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          searchResults.clear();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF10713C), width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: _search,
            ),
          ),
          Expanded(
            child: Obx(() {
              if (isSearching.value) {
                return const Center(child: CircularProgressIndicator(color: Color(0xFF10713C)));
              }
              if (_searchController.text.trim().isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        'Search for users to start chatting',
                        style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                );
              }
              if (searchResults.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_off_outlined, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        'No users found',
                        style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                );
              }
              return ListView.builder(
                itemCount: searchResults.length,
                itemBuilder: (context, index) {
                  final user = searchResults[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF10713C).withOpacity(0.1),
                      backgroundImage: user.image != null ? NetworkImage(user.image) : null,
                      child: user.image == null
                          ? Text(
                              user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                              style: const TextStyle(color: Color(0xFF10713C), fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                    title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(user.email, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                    onTap: () => _startChat(user.id, user.name),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}
