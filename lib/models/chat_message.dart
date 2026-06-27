import 'chat_user.dart';

class ChatMessage {
  final int id;
  final int conversationId;
  final int senderId;
  final String? message;
  final String messageType;
  final String? fileUrl;
  final String? thumbnailUrl;
  final bool isRead;
  final ChatUser? sender;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.message,
    required this.messageType,
    this.fileUrl,
    this.thumbnailUrl,
    required this.isRead,
    this.sender,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] ?? 0,
      conversationId: json['conversation_id'] ?? 0,
      senderId: json['sender_id'] ?? 0,
      message: json['message'],
      messageType: json['message_type'] ?? 'text',
      fileUrl: json['file_url'],
      thumbnailUrl: json['thumbnail_url'],
      isRead: json['is_read'] ?? false,
      sender: json['sender'] != null ? ChatUser.fromJson(json['sender']) : null,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : DateTime.now(),
    );
  }

  bool get isImage => messageType == 'image';
  bool get isFile => messageType == 'file';
  bool get isLocation => messageType == 'location';
  bool get isText => messageType == 'text';
}
