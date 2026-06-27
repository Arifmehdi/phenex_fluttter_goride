import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:goride/services/api_service.dart';
import 'package:goride/models/chat_conversation.dart';
import 'package:goride/models/chat_message.dart';
import 'package:goride/models/chat_user.dart';

class ChatService extends GetxService {
  final ApiService _apiService = Get.find<ApiService>();

  ApiService get api => _apiService;

  final conversations = <ChatConversation>[].obs;
  final messages = <ChatMessage>[].obs;
  final isLoadingConversations = false.obs;
  final isLoadingMessages = false.obs;
  final unreadCount = 0.obs;

  Timer? _pollingTimer;
  int? _currentConversationId;
  int _lastMessageId = 0;
  bool _isPolling = false;

  @override
  void onInit() {
    super.onInit();
    loadConversations();
  }

  @override
  void onClose() {
    stopPolling();
    super.onClose();
  }

  Future<void> loadConversations() async {
    isLoadingConversations.value = true;
    try {
      final response = await _apiService.getConversations();
      if (response.statusCode == 200 && response.data['success'] == true) {
        final data = response.data['conversations'];
        if (data != null && data['data'] != null) {
          conversations.value = (data['data'] as List)
              .map((c) => ChatConversation.fromJson(c))
              .toList();
          _updateUnreadCount();
        }
      }
    } catch (e) {
      debugPrint('Error loading conversations: $e');
    } finally {
      isLoadingConversations.value = false;
    }
  }

  void _updateUnreadCount() {
    int total = 0;
    for (final c in conversations) {
      total += c.unreadCount;
    }
    unreadCount.value = total;
  }

  Future<int?> openOrCreatePrivateChat(int otherUserId) async {
    try {
      final response = await _apiService.getOrCreatePrivateChat(otherUserId);
      if (response.statusCode == 200 && response.data['success'] == true) {
        final conversation = ChatConversation.fromJson(response.data['conversation']);
        final idx = conversations.indexWhere((c) => c.id == conversation.id);
        if (idx >= 0) {
          conversations[idx] = conversation;
        } else {
          conversations.insert(0, conversation);
        }
        return conversation.id;
      }
    } catch (e) {
      debugPrint('Error creating conversation: $e');
    }
    return null;
  }

  Future<void> loadMessages(int conversationId, {bool refresh = false}) async {
    if (_currentConversationId != conversationId || refresh) {
      _currentConversationId = conversationId;
      _lastMessageId = 0;
      messages.clear();
    }

    isLoadingMessages.value = true;
    try {
      final response = await _apiService.getMessages(conversationId);
      if (response.statusCode == 200 && response.data['success'] == true) {
        final data = response.data['messages'];
        if (data != null && data['data'] != null) {
          final newMessages = (data['data'] as List)
              .map((m) => ChatMessage.fromJson(m))
              .toList();
          messages.value = newMessages;
          if (newMessages.isNotEmpty) {
            _lastMessageId = newMessages.last.id;
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading messages: $e');
    } finally {
      isLoadingMessages.value = false;
    }
  }

  Future<void> sendMessage({
    required int conversationId,
    required String messageType,
    String? message,
    String? fileUrl,
    String? thumbnailUrl,
  }) async {
    try {
      final response = await _apiService.sendMessage(
        conversationId: conversationId,
        messageType: messageType,
        message: message,
        fileUrl: fileUrl,
        thumbnailUrl: thumbnailUrl,
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (response.data['message'] != null) {
          final newMsg = ChatMessage.fromJson(response.data['message']);
          messages.add(newMsg);
          _lastMessageId = newMsg.id;
          _updateConversationLastMessage(conversationId, newMsg);
        }
      }
    } catch (e) {
      debugPrint('Error sending message: $e');
    }
  }

  Future<void> sendImageMessage({
    required int conversationId,
    required String filePath,
  }) async {
    try {
      final response = await _apiService.sendMultipartMessage(
        conversationId: conversationId,
        messageType: 'image',
        filePath: filePath,
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (response.data['message'] != null) {
          final newMsg = ChatMessage.fromJson(response.data['message']);
          messages.add(newMsg);
          _lastMessageId = newMsg.id;
          _updateConversationLastMessage(conversationId, newMsg);
        }
      }
    } catch (e) {
      debugPrint('Error sending image: $e');
    }
  }

  Future<void> sendFileMessage({
    required int conversationId,
    required String filePath,
  }) async {
    try {
      final response = await _apiService.sendMultipartMessage(
        conversationId: conversationId,
        messageType: 'file',
        filePath: filePath,
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (response.data['message'] != null) {
          final newMsg = ChatMessage.fromJson(response.data['message']);
          messages.add(newMsg);
          _lastMessageId = newMsg.id;
          _updateConversationLastMessage(conversationId, newMsg);
        }
      }
    } catch (e) {
      debugPrint('Error sending file: $e');
    }
  }

  void _updateConversationLastMessage(int conversationId, ChatMessage msg) {
    final idx = conversations.indexWhere((c) => c.id == conversationId);
    if (idx >= 0) {
      final conv = conversations[idx];
      conversations[idx] = ChatConversation(
        id: conv.id,
        title: conv.title,
        type: conv.type,
        createdBy: conv.createdBy,
        lastMessageAt: msg.createdAt,
        unreadCount: conv.unreadCount,
        otherUser: conv.otherUser,
        latestMessage: msg,
        participants: conv.participants,
        createdAt: conv.createdAt,
      );
      conversations.sort((a, b) => (b.lastMessageAt ?? DateTime(2000)).compareTo(a.lastMessageAt ?? DateTime(2000)));
    }
  }

  Future<void> markAsRead(int conversationId) async {
    try {
      await _apiService.markMessagesRead(conversationId);
      final idx = conversations.indexWhere((c) => c.id == conversationId);
      if (idx >= 0) {
        final conv = conversations[idx];
        conversations[idx] = ChatConversation(
          id: conv.id,
          title: conv.title,
          type: conv.type,
          createdBy: conv.createdBy,
          lastMessageAt: conv.lastMessageAt,
          unreadCount: 0,
          otherUser: conv.otherUser,
          latestMessage: conv.latestMessage,
          participants: conv.participants,
          createdAt: conv.createdAt,
        );
      }
      _updateUnreadCount();
    } catch (e) {
      debugPrint('Error marking as read: $e');
    }
  }

  void startPolling(int conversationId) {
    stopPolling();
    _currentConversationId = conversationId;
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollMessages(conversationId));
  }

  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _isPolling = false;
  }

  Future<void> _pollMessages(int conversationId) async {
    if (_isPolling) return;
    _isPolling = true;
    try {
      final response = await _apiService.getNewMessages(conversationId, afterId: _lastMessageId > 0 ? _lastMessageId : null);
      if (response.statusCode == 200 && response.data['success'] == true) {
        final newMessages = (response.data['messages'] as List)
            .map((m) => ChatMessage.fromJson(m))
            .toList();
        if (newMessages.isNotEmpty) {
          messages.addAll(newMessages);
          _lastMessageId = newMessages.last.id;
        }
      }
    } catch (e) {
      debugPrint('Polling error: $e');
    } finally {
      _isPolling = false;
    }
  }

  Future<void> deleteMessage(int messageId) async {
    try {
      await _apiService.deleteMessage(messageId);
      messages.removeWhere((m) => m.id == messageId);
    } catch (e) {
      debugPrint('Error deleting message: $e');
    }
  }

  Future<List<ChatUser>> searchUsers(String query) async {
    try {
      final response = await _apiService.searchChatUsers(query);
      if (response.statusCode == 200 && response.data['success'] == true) {
        return (response.data['users'] as List)
            .map((u) => ChatUser.fromJson(u))
            .toList();
      }
    } catch (e) {
      debugPrint('Error searching users: $e');
    }
    return [];
  }
}
