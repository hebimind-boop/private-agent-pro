import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/chat_message.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isGenerating;
  final VoidCallback? onStop;

  const MessageBubble({
    super.key,
    required this.message,
    this.isGenerating = false,
    this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Check if user attached an image
    final hasUserImage = isUser &&
        ((message.imagePath != null && message.imagePath!.isNotEmpty) ||
            (message.imageBase64 != null && message.imageBase64!.isNotEmpty));

    // Assistant thinking state
    final isThinking = !isUser && message.content.isEmpty && isGenerating;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        margin: EdgeInsets.only(
          left: isUser ? 48 : 8,
          right: isUser ? 8 : 48,
          top: 6,
          bottom: 6,
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. User Image Thumbnail (Claude-style above text prompt)
            if (hasUserImage) ...[
              _buildUserImageThumbnail(context, isDark),
              if (message.content.isNotEmpty) const SizedBox(height: 6),
            ],

            // 2. Message Bubble Container
            if (!isUser || message.content.isNotEmpty)
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isThinking ? 14 : 16,
                  vertical: isThinking ? 10 : 12,
                ),
                decoration: BoxDecoration(
                  color: isUser
                      ? Theme.of(context).colorScheme.primary
                      : (isDark ? const Color(0xFF141414) : Theme.of(context).colorScheme.surface),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(isUser ? 20 : 6),
                    bottomRight: Radius.circular(isUser ? 6 : 20),
                  ),
                  border: isUser
                      ? null
                      : Border.all(
                          color: isDark
                              ? const Color(0xFF262626)
                              : Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
                          width: 1.2,
                        ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.25 : 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Action result badge
                    if (message.actionResult != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: message.actionResult!.success
                              ? Colors.green.withOpacity(0.12)
                              : Colors.red.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: message.actionResult!.success
                                ? Colors.green.withOpacity(0.3)
                                : Colors.red.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              message.actionResult!.success
                                  ? Icons.check_circle_rounded
                                  : Icons.error_rounded,
                              size: 14,
                              color: message.actionResult!.success
                                  ? Colors.green
                                  : Colors.red,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              message.actionResult!.actionType
                                  .toUpperCase()
                                  .replaceAll('_', ' '),
                              style: TextStyle(
                                fontSize: 10,
                                color: message.actionResult!.success
                                    ? Colors.green
                                    : Colors.red,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Thinking state inside assistant bubble
                    if (isThinking) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ThinkingDotWave(isDark: isDark),
                          const SizedBox(width: 12),
                          if (onStop != null)
                            _buildStopButton(context, isDark),
                        ],
                      ),
                    ] else if (isUser) ...[
                      // User message text
                      SelectableText(
                        message.content,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                    ] else ...[
                      // Assistant response markdown text
                      MarkdownBody(
                        data: message.content,
                        selectable: true,
                        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                          p: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: 15,
                            height: 1.45,
                          ),
                          listBullet: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black87,
                            fontSize: 15,
                          ),
                          code: TextStyle(
                            backgroundColor: isDark
                                ? const Color(0xFF1E1E20)
                                : Colors.grey[200],
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: 13,
                          ),
                        ),
                      ),

                      // If actively streaming text, show subtle Stop button at bottom
                      if (isGenerating && onStop != null) ...[
                        const SizedBox(height: 10),
                        _buildStopButton(context, isDark),
                      ],
                    ],

                    // Timestamp
                    if (!isThinking) ...[
                      const SizedBox(height: 4),
                      Text(
                        _formatTime(message.timestamp),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isUser
                              ? Theme.of(context)
                                  .colorScheme
                                  .onPrimary
                                  .withOpacity(0.6)
                              : (isDark ? Colors.grey[500] : Colors.grey[600]),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStopButton(BuildContext context, bool isDark) {
    return InkWell(
      onTap: onStop,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E20) : Colors.grey[200],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? const Color(0xFF333336) : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.stop_circle_rounded,
              size: 13,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
            const SizedBox(width: 4),
            Text(
              'Stop',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserImageThumbnail(BuildContext context, bool isDark) {
    Widget imageWidget;
    Uint8List? rawBytes;
    File? rawFile;

    if (message.imagePath != null && File(message.imagePath!).existsSync()) {
      rawFile = File(message.imagePath!);
      imageWidget = Image.file(
        rawFile,
        fit: BoxFit.cover,
      );
    } else if (message.imageBase64 != null && message.imageBase64!.isNotEmpty) {
      String cleanBase64 = message.imageBase64!;
      if (cleanBase64.contains(',')) {
        cleanBase64 = cleanBase64.split(',').last;
      }
      try {
        rawBytes = base64Decode(cleanBase64);
        imageWidget = Image.memory(
          rawBytes,
          fit: BoxFit.cover,
        );
      } catch (_) {
        imageWidget = const Icon(Icons.broken_image_rounded, size: 40);
      }
    } else {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () => _showFullScreenImage(context, file: rawFile, bytes: rawBytes),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 180, maxWidth: 240),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0xFF2C2C2E) : Colors.grey[300]!,
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: imageWidget,
        ),
      ),
    );
  }

  void _showFullScreenImage(
    BuildContext context, {
    File? file,
    Uint8List? bytes,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(color: Colors.black.withOpacity(0.92)),
            ),
            Center(
              child: InteractiveViewer(
                panEnabled: true,
                boundaryMargin: const EdgeInsets.all(20),
                minScale: 0.5,
                maxScale: 4.0,
                child: file != null
                    ? Image.file(file)
                    : (bytes != null
                        ? Image.memory(bytes)
                        : const SizedBox.shrink()),
              ),
            ),
            Positioned(
              top: 48,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _ThinkingDotWave extends StatefulWidget {
  final bool isDark;
  const _ThinkingDotWave({required this.isDark});

  @override
  State<_ThinkingDotWave> createState() => _ThinkingDotWaveState();
}

class _ThinkingDotWaveState extends State<_ThinkingDotWave>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dotColor = widget.isDark ? Colors.white : Colors.black87;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            final val = (_controller.value - delay) % 1.0;
            final opacity =
                (0.25 + 0.75 * (0.5 * (1 + math.sin(val * 2 * math.pi)))).clamp(0.2, 1.0);
            final scale =
                0.8 + 0.35 * (0.5 * (1 + math.sin(val * 2 * math.pi)));
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              width: 6.5 * scale,
              height: 6.5 * scale,
              decoration: BoxDecoration(
                color: dotColor.withOpacity(opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
