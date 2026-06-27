import 'chat_user.dart';
import 'chat_message.dart';

class ChatConversation {
  final int id;
  final String? title;
  final String type;
  final int createdBy;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final ChatUser? otherUser;
  final ChatMessage? latestMessage;
  final List<ChatUser> participants;
  final DateTime createdAt;

  ChatConversation({
    required this.id,
    this.title,
    required this.type,
    required this.createdBy,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.otherUser,
    this.latestMessage,
    this.participants = const [],
    required this.createdAt,
  });

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    // Participants come from backend as ConversationParticipant objects
    // with a nested 'user' key — extract the user from each participant.
    final rawParticipants = (json['participants'] as List?) ?? [];
    final participantUsers = rawParticipants
        .where((p) => p is Map && p['user'] != null)
        .map((p) => ChatUser.fromJson(p['user'] as Map<String, dynamic>))
        .toList();

    // Backend appends other_user directly; fallback to first participant user.
    ChatUser? otherUser;
    if (json['other_user'] != null) {
      otherUser = ChatUser.fromJson(json['other_user'] as Map<String, dynamic>);
    } else if (participantUsers.isNotEmpty) {
      otherUser = participantUsers.first;
    }

    return ChatConversation(
      id: json['id'] ?? 0,
      title: json['title'],
      type: json['type'] ?? 'private',
      createdBy: json['created_by'] ?? 0,
      lastMessageAt: json['last_message_at'] != null ? DateTime.parse(json['last_message_at']) : null,
      unreadCount: json['unread_count'] ?? 0,
      otherUser: otherUser,
      latestMessage: json['latest_message'] != null
          ? ChatMessage(
              id: json['latest_message']['id'] ?? 0,
              conversationId: json['id'] ?? 0,
              senderId: json['latest_message']['sender_id'] ?? 0,
              message: json['latest_message']['message'],
              messageType: json['latest_message']['message_type'] ?? 'text',
              fileUrl: json['latest_message']['file_url'],
              thumbnailUrl: json['latest_message']['thumbnail_url'],
              isRead: false,
              createdAt: json['latest_message']['created_at'] != null
                  ? DateTime.parse(json['latest_message']['created_at'])
                  : DateTime.now(),
              updatedAt: DateTime.now(),
            )
          : null,
      participants: participantUsers,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now(),
    );
  }

  String get displayName {
    if (title != null && title!.isNotEmpty) return title!;
    if (otherUser != null) return otherUser!.name;
    return 'Chat';
  }

  String get subtitle {
    if (latestMessage == null) return 'No messages yet';
    if (latestMessage!.isImage) return '📷 Photo';
    if (latestMessage!.isFile) return '📎 File';
    if (latestMessage!.isLocation) return '📍 Location';
    return latestMessage!.message ?? '';
  }
}
