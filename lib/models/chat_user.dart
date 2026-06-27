class ChatUser {
  final int id;
  final String name;
  final String email;
  final String? image;
  final String? userType;

  ChatUser({
    required this.id,
    required this.name,
    required this.email,
    this.image,
    this.userType,
  });

  factory ChatUser.fromJson(Map<String, dynamic> json) {
    return ChatUser(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      image: json['image'],
      userType: json['user_type'],
    );
  }
}
