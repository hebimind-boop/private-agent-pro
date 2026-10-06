class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime timestamp;
  final AgentActionResult? actionResult;
  final String? imageBase64;
  final String? imagePath;

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.actionResult,
    this.imageBase64,
    this.imagePath,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isUser => role == 'user';

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'actionResult': actionResult?.toJson(),
        'imageBase64': imageBase64,
        'imagePath': imagePath,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'] as String,
        content: json['content'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        actionResult: json['actionResult'] != null
            ? AgentActionResult.fromJson(json['actionResult'] as Map<String, dynamic>)
            : null,
        imageBase64: json['imageBase64'] as String?,
        imagePath: json['imagePath'] as String?,
      );
}

class AgentActionResult {
  final String actionType;
  final bool success;
  final String? details;

  AgentActionResult({
    required this.actionType,
    required this.success,
    this.details,
  });

  Map<String, dynamic> toJson() => {
        'actionType': actionType,
        'success': success,
        'details': details,
      };

  factory AgentActionResult.fromJson(Map<String, dynamic> json) => AgentActionResult(
        actionType: json['actionType'] as String,
        success: json['success'] as bool,
        details: json['details'] as String?,
      );
}
