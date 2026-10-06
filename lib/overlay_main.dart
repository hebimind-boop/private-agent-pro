import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'services/ai_service.dart';
import 'services/task_executor.dart';
import 'services/screen_automation_service.dart';
import 'services/app_launcher_service.dart';
import 'services/shizuku_service.dart';
import 'services/chat_history_service.dart';
import 'models/chat_message.dart';
import 'widgets/message_bubble.dart';

class OverlayApp extends StatefulWidget {
  const OverlayApp({super.key});

  @override
  State<OverlayApp> createState() => _OverlayAppState();
}

class _OverlayAppState extends State<OverlayApp> {
  bool _isExpanded = false;
  final TextEditingController _taskController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSent = false;
  bool _isListening = false;
  final stt.SpeechToText _speech = stt.SpeechToText();
  final List<ChatMessage> _messages = [];

  late final AiService _aiService;
  late final ScreenAutomationService _screenService;
  late final AppLauncherService _appLauncher;
  late final ShizukuService _shizukuService;
  late final Future<void> _servicesReady;
  StreamSubscription<dynamic>? _overlaySubscription;
  TaskExecutor? _executor;
  Future<void> _overlayHistoryWrite = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _speech.initialize();

    _aiService = AiService();
    _screenService = ScreenAutomationService();
    _appLauncher = AppLauncherService();
    _shizukuService = ShizukuService();
    _servicesReady = _initializeServices();
    _overlaySubscription = FlutterOverlayWindow.overlayListener.listen(
      _handleMainAppEvent,
    );

    // Welcome message
    _messages.add(
      ChatMessage(
        role: 'assistant',
        content:
            'Hi! I am your Private Agent. Ask me to perform any task on your screen.',
      ),
    );
  }

  @override
  void dispose() {
    _overlaySubscription?.cancel();
    _taskController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleMainAppEvent(dynamic event) {
    if (event is! String || !event.startsWith('OVERLAY_')) return;

    final separator = event.indexOf('|');
    final type = separator == -1 ? event : event.substring(0, separator);
    final message = separator == -1 ? '' : event.substring(separator + 1);

    if (type == 'OVERLAY_HISTORY') {
      try {
        final decoded = jsonDecode(utf8.decode(base64Decode(message))) as List;
        final history = decoded
            .map(
              (item) =>
                  ChatMessage.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList();
        if (!mounted) return;
        setState(() {
          _messages
            ..clear()
            ..addAll(history);
          _isSent = true;
          _scrollToBottom();
        });
      } catch (error) {
        log('Overlay history sync failed: $error');
      }
      return;
    }

    if (type == 'OVERLAY_RESET') {
      if (!mounted) return;
      setState(() {
        _isExpanded = false;
        _isSent = false;
      });
      return;
    }

    if (message.isEmpty || !mounted) return;
    setState(() {
      _isSent = type != 'OVERLAY_TASK_FINISHED';
      _messages.add(ChatMessage(role: 'assistant', content: message));
      _scrollToBottom();
    });
  }

  Future<void> _initializeServices() async {
    // 1. Send registration broadcast first so native MethodChannels are active
    final intent = const AndroidIntent(
      action: 'com.orailnoor.privateagent.REGISTER_BACKGROUND_CHANNELS',
      package: 'com.orailnoor.privateagent',
    );
    try {
      await intent.sendBroadcast();
    } catch (e) {
      log("Broadcast error: $e");
    }

    // 2. Wait a brief moment for registration
    await Future.delayed(const Duration(milliseconds: 150));

    // 3. Initialize AI Service settings
    await _aiService.init();

    // 4. Safely query Shizuku without locking startup
    try {
      await _shizukuService.checkAvailability();
    } catch (e) {
      log("Shizuku check error: $e");
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _persistOverlayMessage(ChatMessage message) {
    _overlayHistoryWrite = _overlayHistoryWrite
        .then((_) => ChatHistoryService.appendOverlayMessage(message.toJson()))
        .catchError((Object error) {
          log('Overlay history handoff failed: $error');
        });
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }

    setState(() => _isListening = true);
    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        if (result.finalResult) {
          setState(() {
            _isListening = false;
            _taskController.text = result.recognizedWords;
          });
          _sendTask(result.recognizedWords);
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.confirmation,
        partialResults: false,
      ),
    );
  }

  Future<void> _sendTask(String task) async {
    if (task.trim().isEmpty || _isSent) return;

    final userTask = task.trim();
    final userMessage = ChatMessage(role: 'user', content: userTask);
    setState(() {
      _isSent = true;
      _messages.add(userMessage);
      _scrollToBottom();
    });
    _persistOverlayMessage(userMessage);

    _taskController.clear(); // Clear immediately for responsive UX feedback

    await _servicesReady;
    if (!await _screenService.waitUntilReady()) {
      // Re-broadcast once if engine was cold-starting
      try {
        final intent = const AndroidIntent(
          action: 'com.orailnoor.privateagent.REGISTER_BACKGROUND_CHANNELS',
          package: 'com.orailnoor.privateagent',
        );
        await intent.sendBroadcast();
        await Future.delayed(const Duration(milliseconds: 250));
      } catch (_) {}
    }
    if (!await _screenService.waitUntilReady()) {
      if (mounted) {
        final errorMessage = ChatMessage(
          role: 'assistant',
          content:
              'The background accessibility bridge did not respond. '
              'Close and reopen the floating overlay, then try again.',
        );
        setState(() {
          _isSent = false;
          _messages.add(errorMessage);
          _scrollToBottom();
        });
        _persistOverlayMessage(errorMessage);
      }
      return;
    }

    try {
      // Execute the task directly in the overlay isolate!
      _executor = TaskExecutor(
        aiService: _aiService,
        screenService: _screenService,
        appLauncher: _appLauncher,
        shizukuService: _shizukuService,
        onProgress: (msg) {
          log("Overlay Task Progress: $msg");
          if (mounted) {
            final progressMessage = ChatMessage(
              role: 'assistant',
              content: msg,
            );
            setState(() {
              _messages.add(progressMessage);
              _scrollToBottom();
            });
            _persistOverlayMessage(progressMessage);
          }
        },
      );

      _executor!
          .executeTask(userTask)
          .then((res) {
            log("Overlay Task Finished");
            if (mounted) {
              final resultMessage = ChatMessage(
                role: 'assistant',
                content: res,
              );
              setState(() {
                _isSent = false;
                _messages.add(resultMessage);
                _scrollToBottom();
              });
              _persistOverlayMessage(resultMessage);
            }
          })
          .catchError((e) {
            log("Overlay Task Error: $e");
            if (mounted) {
              final errorMessage = ChatMessage(
                role: 'assistant',
                content: 'I could not complete that task. Please try again.',
              );
              setState(() {
                _isSent = false;
                _messages.add(errorMessage);
                _scrollToBottom();
              });
              _persistOverlayMessage(errorMessage);
            }
          });
    } catch (e) {
      log("Overlay Task Execution Exception: $e");
      if (mounted) {
        final errorMessage = ChatMessage(
          role: 'assistant',
          content: 'I could not complete that task. Please try again.',
        );
        setState(() {
          _isSent = false;
          _messages.add(errorMessage);
          _scrollToBottom();
        });
        _persistOverlayMessage(errorMessage);
      }
    }
  }

  void _cancelTask() {
    _executor?.cancel();
    if (mounted) {
      setState(() {
        _isSent = false;
        final cancelMsg = ChatMessage(
          role: 'assistant',
          content: 'Task stopped by user.',
        );
        _messages.add(cancelMsg);
        _scrollToBottom();
        _persistOverlayMessage(cancelMsg);
      });
    }
  }

  OverlayPosition? _savedBubblePosition;

  Future<void> _toggleExpanded() async {
    if (!_isExpanded) {
      // Save current bubble position before expanding
      _savedBubblePosition = await FlutterOverlayWindow.getOverlayPosition();
      final initialPosition = OverlayPosition(
        10,
        _savedBubblePosition?.y ?? 300,
      );
      // Move to a safe position so the expanded panel stays on-screen
      await FlutterOverlayWindow.moveOverlay(initialPosition);
      await FlutterOverlayWindow.resizeOverlay(300, 360, false);
      setState(() {
        _isExpanded = true;
        _scrollToBottom();
      });
    } else {
      await FlutterOverlayWindow.resizeOverlay(56, 56, true);
      // Restore the original bubble position
      if (_savedBubblePosition != null) {
        await FlutterOverlayWindow.moveOverlay(_savedBubblePosition!);
      }
      setState(() => _isExpanded = false);
    }
  }

  Future<void> _openMainApp() async {
    if (mounted) {
      setState(() {
        _isExpanded = false;
        _isSent = false;
      });
    }
    await _overlayHistoryWrite;
    const intent = AndroidIntent(
      action: 'android.intent.action.MAIN',
      category: 'android.intent.category.LAUNCHER',
      package: 'com.orailnoor.privateagent',
      componentName: 'com.orailnoor.privateagent.MainActivity',
      flags: <int>[
        Flag.FLAG_ACTIVITY_NEW_TASK,
        Flag.FLAG_ACTIVITY_REORDER_TO_FRONT,
      ],
    );
    await intent.launch();
    await FlutterOverlayWindow.closeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(child: _buildContent()),
    );
  }

  Widget _buildContent() {
    if (!_isExpanded) {
      return GestureDetector(
        onTap: _toggleExpanded,
        child: SizedBox.expand(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF2C2C2E),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.7),
                  blurRadius: 10,
                  spreadRadius: 1,
                  offset: const Offset(0, 3),
                ),
                BoxShadow(
                  color: Colors.white.withOpacity(0.08),
                  blurRadius: 6,
                  spreadRadius: 0,
                ),
              ],
            ),
            padding: const EdgeInsets.all(8),
            child: Stack(
              alignment: Alignment.center,
              children: [
                ClipOval(
                  child: Image.asset(
                    'assets/app-logo.png',
                    fit: BoxFit.cover,
                    width: 28,
                    height: 28,
                  ),
                ),
                Positioned(
                  right: 1,
                  top: 1,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _isSent ? Colors.white : const Color(0xFF8E8E93),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF111111),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _isSent
                              ? Colors.white.withOpacity(0.9)
                              : Colors.white.withOpacity(0.3),
                          blurRadius: _isSent ? 6 : 3,
                          spreadRadius: _isSent ? 1 : 0,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Full Chat Interface Panel
    return OverflowBox(
      minWidth: 300,
      maxWidth: 300,
      minHeight: 360,
      maxHeight: 360,
      alignment: Alignment.center,
      child: Container(
        width: 300,
        height: 360,
        decoration: BoxDecoration(
          color: const Color(0xFF000000),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF2C2C2E), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.85),
              blurRadius: 18,
              spreadRadius: 2,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: Colors.white.withOpacity(0.05),
              blurRadius: 8,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Column(
          children: [
            // Header Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF111111),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  bottom: BorderSide(color: Color(0xFF2C2C2E), width: 1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      ClipOval(
                        child: Image.asset(
                          'assets/app-logo.png',
                          width: 18,
                          height: 18,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Private Agent',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _isSent ? Colors.white : const Color(0xFF636366),
                          shape: BoxShape.circle,
                          boxShadow: _isSent
                              ? [
                                  BoxShadow(
                                    color: Colors.white.withOpacity(0.8),
                                    blurRadius: 4,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Semantics(
                        button: true,
                        label: 'Open PrivateAgent',
                        child: GestureDetector(
                          onTap: () => unawaited(_openMainApp()),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(
                              Icons.open_in_new_rounded,
                              color: Color(0xFFE5E5EA),
                              size: 17,
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _toggleExpanded,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1C1E),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF2C2C2E),
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            Icons.remove,
                            color: Color(0xFFE5E5EA),
                            size: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Message Log List
            Expanded(
              child: Container(
                color: const Color(0xFF000000),
                child: ListView.builder(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) =>
                      MessageBubble(message: _messages[index]),
                ),
              ),
            ),

            // Input Controller Area
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF111111),
                border: Border(
                  top: BorderSide(color: Color(0xFF2C2C2E), width: 1),
                ),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: const Color(0xFF2C2C2E),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _taskController,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Type a command...',
                                hintStyle: TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF8E8E93),
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                              ),
                              onSubmitted: (val) => _sendTask(val),
                            ),
                          ),
                          if (!_isSent)
                            GestureDetector(
                              onTap: _toggleListening,
                              child: Icon(
                                _isListening ? Icons.mic : Icons.mic_none,
                                color: _isListening
                                    ? Colors.redAccent
                                    : Colors.white70,
                                size: 16,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _isSent
                      ? GestureDetector(
                          onTap: _cancelTask,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1C1E),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF2C2C2E),
                                width: 1,
                              ),
                            ),
                            child: const Icon(
                              Icons.stop_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        )
                      : GestureDetector(
                          onTap: () => _sendTask(_taskController.text),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFFFFF),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.arrow_upward_rounded,
                              color: Color(0xFF000000),
                              size: 16,
                            ),
                          ),
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
