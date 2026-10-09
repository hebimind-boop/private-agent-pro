import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../config/feature_flags.dart';
import '../services/ai_service.dart';
import '../services/screen_automation_service.dart';
import '../services/floating_bubble_service.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  final ScreenAutomationService _screenAutomationService =
      ScreenAutomationService();
  final AiService _aiService = AiService();

  int _currentStep = 0;
  bool _isAccessibilityGranted = false;
  bool _isOverlayGranted = false;
  bool _isMicrophoneGranted = false;
  bool _isNotificationsGranted = false;
  bool _isContactsGranted = false;
  bool _isPhoneGranted = false;
  bool _isSmsGranted = false;

  // AI config states
  String _selectedProvider = 'nvidia';
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController(
    text: AiService.nvidiaBaseUrl,
  );
  final TextEditingController _modelController = TextEditingController(
    text: AiService.nvidiaDefaultModel,
  );
  bool _obscureKey = true;
  bool _isValidating = false;
  String? _validationError;

  // OLED Cyberpunk Palette
  static const Color _bgBlack = Color(0xFF000000);
  static const Color _surfaceCard = Color(0xFF111111);
  static const Color _surfaceCardAlt = Color(0xFF0D0D0D);
  static const Color _borderDark = Color(0xFF222222);
  static const Color _borderHighlight = Color(0xFFFFFFFF);
  static const Color _textWhite = Color(0xFFFFFFFF);
  static const Color _textMuted = Color(0xFF888888);
  static const Color _textSubtle = Color(0xFF555555);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAiDefaults();
    _checkPermissions();
  }

  Future<void> _loadAiDefaults() async {
    await _aiService.init();
    if (!mounted || !_aiService.isConfigured) return;
    setState(() {
      _selectedProvider = 'custom';
      _apiKeyController.text = _aiService.apiKey;
      _baseUrlController.text = _aiService.baseUrl;
      _modelController.text = _aiService.model;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    final accessibilityRunning =
        await _screenAutomationService.isServiceRunning();
    final overlayGranted = await FloatingBubbleService.isPermissionGranted();
    final microphoneStatus = await Permission.microphone.status;
    final notificationsStatus = await Permission.notification.status;
    final contactsStatus = await Permission.contacts.status;
    final phoneStatus = await Permission.phone.status;
    final smsStatus = await Permission.sms.status;

    if (mounted) {
      setState(() {
        _isAccessibilityGranted = accessibilityRunning;
        _isOverlayGranted = overlayGranted;
        _isMicrophoneGranted = microphoneStatus.isGranted;
        _isNotificationsGranted = notificationsStatus.isGranted;
        _isContactsGranted = contactsStatus.isGranted;
        _isPhoneGranted = phoneStatus.isGranted;
        _isSmsGranted = smsStatus.isGranted;
      });
    }
  }

  Future<void> _requestPermission(Permission permission) async {
    await permission.request();
    _checkPermissions();
  }

  Future<void> _requestAccessibility() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: _borderDark, width: 1.2),
        ),
        title: const Text(
          'Enable Screen Control',
          style: TextStyle(
            color: _textWhite,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        content: const Text(
          'If Android displays "Restricted setting", navigate to App Info, tap the three-dot menu, and tap "Allow restricted settings". Then enable PrivateAgent Screen Control in Accessibility.',
          style: TextStyle(
            color: _textMuted,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _screenAutomationService.openAccessibilitySettings();
            },
            child: const Text(
              'Accessibility',
              style: TextStyle(color: _textWhite, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _textWhite,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'App Info',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _requestOverlayPermission() async {
    await FloatingBubbleService.requestPermission();
    final granted = await FloatingBubbleService.isPermissionGranted();
    if (mounted) {
      setState(() {
        _isOverlayGranted = granted;
      });
    }
  }

  void _selectProvider(String provider) {
    setState(() {
      _selectedProvider = provider;
      _validationError = null;
      if (provider == 'nvidia') {
        _baseUrlController.text = AiService.nvidiaBaseUrl;
        _modelController.text = AiService.nvidiaDefaultModel;
      } else if (provider == 'deepseek') {
        _baseUrlController.text = 'https://api.deepseek.com';
        _modelController.text = 'deepseek-chat';
      } else if (provider == 'groq') {
        _baseUrlController.text = 'https://api.groq.com/openai/v1';
        _modelController.text = 'llama-3.3-70b-versatile';
      } else if (provider == 'ollama') {
        _baseUrlController.text = 'http://10.0.2.2:11434/v1';
        _modelController.text = 'gemma2';
      } else {
        _baseUrlController.clear();
        _modelController.clear();
      }
    });
  }

  Future<void> _testAndSave() async {
    setState(() {
      _isValidating = true;
      _validationError = null;
    });

    final apiKey = _apiKeyController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    final model = _modelController.text.trim();

    if (baseUrl.isEmpty || model.isEmpty) {
      setState(() {
        _validationError = 'API Base URL and Model Name are required.';
        _isValidating = false;
      });
      return;
    }

    if (_selectedProvider != 'ollama' && apiKey.isEmpty) {
      setState(() {
        _validationError = 'API Key is required for cloud providers.';
        _isValidating = false;
      });
      return;
    }

    try {
      final models = await _aiService.fetchAvailableModels(baseUrl, apiKey);
      if (models.isNotEmpty || _selectedProvider == 'ollama') {
        await _aiService.saveSettings(
          apiKey: apiKey,
          baseUrl: baseUrl,
          model: model,
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('onboarding_completed', true);

        // Auto-launch floating bubble if permissions allow
        if (_isOverlayGranted && FeatureFlags.floatingOverlayEnabled) {
          await FloatingBubbleService.startBubble();
        }

        if (mounted) {
          setState(() {
            _isValidating = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Neural engine verified. Initializing PrivateAgent...',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              backgroundColor: Colors.white,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      } else {
        setState(() {
          _validationError =
              'Could not connect to provider. Verify Base URL & API Key.';
          _isValidating = false;
        });
      }
    } catch (e) {
      setState(() {
        _validationError = 'Connection failed: ${e.toString().replaceFirst('Exception: ', '')}';
        _isValidating = false;
      });
    }
  }

  Future<void> _fetchModels() async {
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    if (baseUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Enter an API Base URL first.'),
          backgroundColor: const Color(0xFF1E1E1E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    setState(() {
      _isValidating = true;
    });

    try {
      final models = await _aiService.fetchAvailableModels(baseUrl, apiKey);
      setState(() {
        _isValidating = false;
      });

      if (models.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No models returned from endpoint.'),
              backgroundColor: const Color(0xFF1E1E1E),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
        return;
      }

      if (mounted) {
        showModalBottomSheet(
          context: context,
          backgroundColor: _surfaceCard,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (context) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AiService.isNvidiaBaseUrl(baseUrl)
                          ? 'Available NVIDIA NIM Models'
                          : 'Available Models',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _textWhite,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: models.length,
                        itemBuilder: (context, index) {
                          final modelName = models[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                            title: Text(
                              modelName,
                              style: const TextStyle(
                                fontSize: 13,
                                fontFamily: 'monospace',
                                color: _textWhite,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 14,
                              color: _textMuted,
                            ),
                            onTap: () {
                              setState(() {
                                _modelController.text = modelName;
                              });
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }
    } catch (e) {
      setState(() {
        _isValidating = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}'),
            backgroundColor: const Color(0xFF7F1D1D),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  bool get _canProceedToModel {
    return _isAccessibilityGranted &&
        (!FeatureFlags.floatingOverlayEnabled || _isOverlayGranted);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgBlack,
      body: SafeArea(
        child: Column(
          children: [
            // Minimalist OLED Segmented Dashes Progress Indicator
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 12),
              child: _buildProgressDashes(),
            ),

            // Step Content
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (page) {
                  setState(() {
                    _currentStep = page;
                  });
                },
                children: [
                  _buildWelcomePage(),
                  _buildPermissionsPage(),
                  _buildModelSetupPage(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressDashes() {
    final labels = ['IDENTITY', 'BRIDGE', 'ENGINE'];

    return Column(
      children: [
        Row(
          children: List.generate(3, (index) {
            final isActive = _currentStep == index;
            final isCompleted = _currentStep > index;

            return Expanded(
              child: Container(
                margin: EdgeInsets.only(
                  right: index < 2 ? 8.0 : 0.0,
                ),
                height: 3.5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: (isActive || isCompleted)
                      ? _borderHighlight
                      : const Color(0xFF2A2A2A),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(3, (index) {
            final isActive = _currentStep == index;
            return Text(
              labels[index],
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: 1.5,
                color: isActive ? _textWhite : _textSubtle,
              ),
            );
          }),
        ),
      ],
    );
  }

  // ==========================================
  // STEP 1: WELCOME / CORE IDENTITY
  // ==========================================
  Widget _buildWelcomePage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          const Spacer(flex: 2),

          // Cybernetic Agent Core Glyph (Minimalist white with subtle glow)
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _surfaceCardAlt,
              border: Border.all(color: _borderDark, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withOpacity(0.06),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Concentric inner boundary
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                ),
                const Icon(
                  Icons.terminal_rounded,
                  size: 46,
                  color: _textWhite,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Core Identity Header & Tagline
          const Text(
            'PrivateAgent',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: _textWhite,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Autonomous Device Control. Local-first intelligence.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: _textMuted,
              height: 1.4,
            ),
          ),
          const Spacer(flex: 2),

          // Feature Cards: Dark glassmorphic containers (0xFF111111, border 0xFF222222)
          _buildFeatureCard(
            Icons.shield_outlined,
            'Local-First Privacy',
            'Zero cloud telemetry. API keys and operational data remain strictly on-device.',
          ),
          const SizedBox(height: 12),
          _buildFeatureCard(
            Icons.touch_app_outlined,
            'Autonomous Screen Driver',
            'Performs native clicks, typing, and navigation across any Android application.',
          ),
          const SizedBox(height: 12),
          _buildFeatureCard(
            Icons.memory_rounded,
            'Neural Orchestration',
            'Full support for NVIDIA NIM, DeepSeek, Groq, and local Ollama inference.',
          ),

          const Spacer(flex: 3),

          // Action Button: High-contrast pure white pill with black text
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () {
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _textWhite,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Initialize Agent →',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderDark, width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderDark, width: 1),
            ),
            child: Icon(icon, size: 20, color: _textWhite),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    color: _textWhite,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: _textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // STEP 2: PRIVILEGES & SYSTEM BRIDGE
  // ==========================================
  Widget _buildPermissionsPage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          const Text(
            'System Bridge & Privileges',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: _textWhite,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Grant device permissions to enable screen reading and autonomous operations.',
            style: TextStyle(
              fontSize: 13,
              color: _textMuted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),

          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                // Core Required Section
                _buildSectionLabel('CORE REQUIRED'),
                _buildPermissionCard(
                  'Screen Control (Accessibility)',
                  'Allows the agent to read screen hierarchies and automate clicks, typing, and gestures.',
                  Icons.visibility_outlined,
                  _isAccessibilityGranted,
                  _requestAccessibility,
                ),
                const SizedBox(height: 10),
                if (FeatureFlags.floatingOverlayEnabled)
                  _buildPermissionCard(
                    'Display Over Other Apps (Overlay)',
                    'Shows the floating shortcut bubble over other apps for continuous agent control.',
                    Icons.layers_outlined,
                    _isOverlayGranted,
                    _requestOverlayPermission,
                  ),

                const SizedBox(height: 18),

                // Optional Section
                _buildSectionLabel('OPTIONAL DRIVERS'),
                _buildPermissionCard(
                  'Microphone',
                  'Enables speech recognition and voice-directed autonomous commands.',
                  Icons.mic_none_rounded,
                  _isMicrophoneGranted,
                  () => _requestPermission(Permission.microphone),
                ),
                const SizedBox(height: 10),
                _buildPermissionCard(
                  'Notifications',
                  'Displays task progress and alerts in the Android system notification tray.',
                  Icons.notifications_none_rounded,
                  _isNotificationsGranted,
                  () => _requestPermission(Permission.notification),
                ),
                const SizedBox(height: 10),
                _buildPermissionCard(
                  'Contacts',
                  'Enables the agent to lookup phone numbers and contacts upon request.',
                  Icons.contacts_outlined,
                  _isContactsGranted,
                  () => _requestPermission(Permission.contacts),
                ),
                const SizedBox(height: 10),
                _buildPermissionCard(
                  'Phone & SMS',
                  'Enables the agent to dial phone numbers and send messages autonomously.',
                  Icons.phone_android_rounded,
                  _isPhoneGranted && _isSmsGranted,
                  () async {
                    await _requestPermission(Permission.phone);
                    await _requestPermission(Permission.sms);
                  },
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),

          // Bottom Navigation Row
          Row(
            children: [
              TextButton(
                onPressed: () {
                  _pageController.previousPage(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                  );
                },
                child: const Text(
                  'Back',
                  style: TextStyle(
                    color: _textMuted,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _canProceedToModel
                      ? () {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOutCubic,
                          );
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _canProceedToModel ? _textWhite : const Color(0xFF1A1A1A),
                    foregroundColor: _canProceedToModel ? Colors.black : _textSubtle,
                    disabledBackgroundColor: const Color(0xFF1A1A1A),
                    disabledForegroundColor: _textSubtle,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                  ),
                  child: const Row(
                    children: [
                      Text(
                        'Continue',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4, left: 2),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: _textSubtle,
          letterSpacing: 1.8,
        ),
      ),
    );
  }

  Widget _buildPermissionCard(
    String title,
    String description,
    IconData icon,
    bool isGranted,
    VoidCallback onGrant,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isGranted ? Colors.white.withOpacity(0.3) : _borderDark,
          width: 1.2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: _textWhite),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: _textWhite,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 11,
                    color: _textMuted,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isGranted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _textWhite,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_rounded, color: Colors.black, size: 14),
                  SizedBox(width: 4),
                  Text(
                    'ACTIVE',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            )
          else
            OutlinedButton(
              onPressed: onGrant,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _textWhite, width: 1.2),
                backgroundColor: Colors.transparent,
                foregroundColor: _textWhite,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                minimumSize: const Size(60, 32),
              ),
              child: const Text(
                'GRANT',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ==========================================
  // STEP 3: NEURAL ENGINE SETUP
  // ==========================================
  Widget _buildModelSetupPage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          const Text(
            'Neural Engine Setup',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: _textWhite,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Select an inference provider to pre-configure connection parameters.',
            style: TextStyle(
              fontSize: 13,
              color: _textMuted,
            ),
          ),
          const SizedBox(height: 16),

          // Provider Selector Tiles (OLED cards, 1.5px white border when active)
          SizedBox(
            height: 74,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              children: [
                _buildProviderTile('nvidia', 'NVIDIA', Icons.memory_rounded),
                const SizedBox(width: 10),
                _buildProviderTile('deepseek', 'DeepSeek', Icons.analytics_outlined),
                const SizedBox(width: 10),
                _buildProviderTile('groq', 'Groq', Icons.speed_rounded),
                const SizedBox(width: 10),
                _buildProviderTile('ollama', 'Ollama', Icons.computer_rounded),
                const SizedBox(width: 10),
                _buildProviderTile('custom', 'Custom', Icons.tune_rounded),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Configuration Inputs
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                if (_selectedProvider != 'ollama') ...[
                  _buildMonospaceTextField(
                    controller: _apiKeyController,
                    label: 'API KEY',
                    hint: 'nvapi-xxxxxxxxxxxx / sk-xxxxxxxxxxxx',
                    obscure: _obscureKey,
                    suffix: IconButton(
                      icon: Icon(
                        _obscureKey
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: _textMuted,
                        size: 18,
                      ),
                      onPressed: () => setState(() => _obscureKey = !_obscureKey),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                _buildMonospaceTextField(
                  controller: _baseUrlController,
                  label: 'API BASE URL',
                  hint: 'https://integrate.api.nvidia.com/v1',
                ),
                const SizedBox(height: 14),
                _buildMonospaceTextField(
                  controller: _modelController,
                  label: 'MODEL IDENTIFIER',
                  hint: 'meta/llama-3.3-70b-instruct',
                  suffix: IconButton(
                    icon: _isValidating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _textWhite,
                            ),
                          )
                        : const Icon(
                            Icons.sync_rounded,
                            color: _textWhite,
                            size: 18,
                          ),
                    tooltip: 'Fetch models list',
                    onPressed: _isValidating ? null : _fetchModels,
                  ),
                ),

                if (_validationError != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E0A0A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF7F1D1D), width: 1),
                    ),
                    child: Text(
                      _validationError!,
                      style: const TextStyle(
                        color: Color(0xFFF87171),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),

          // Action Buttons Row
          Row(
            children: [
              TextButton(
                onPressed: _isValidating
                    ? null
                    : () {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutCubic,
                        );
                      },
                child: const Text(
                  'Back',
                  style: TextStyle(
                    color: _textMuted,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isValidating ? null : _testAndSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _textWhite,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: const Color(0xFF1A1A1A),
                    disabledForegroundColor: _textSubtle,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 26),
                  ),
                  child: _isValidating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Row(
                          children: [
                            Text(
                              'Finish Setup',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.check_circle_outline_rounded, size: 18),
                          ],
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _buildProviderTile(String id, String label, IconData icon) {
    final isSelected = _selectedProvider == id;

    return GestureDetector(
      onTap: () => _selectProvider(id),
      child: Container(
        width: 84,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: _surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? _borderHighlight : _borderDark,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? _textWhite : _textMuted,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? _textWhite : _textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonospaceTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obscure = false,
    Widget? suffix,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(
        color: _surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderDark, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: _textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: obscure,
                  style: const TextStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                    color: _textWhite,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: hint,
                    hintStyle: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: _textSubtle,
                    ),
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                  ),
                ),
              ),
              if (suffix != null) suffix,
            ],
          ),
        ],
      ),
    );
  }
}
