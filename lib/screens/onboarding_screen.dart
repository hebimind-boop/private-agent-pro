import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // Typing animation state for Screen 1
  Timer? _typingTimer;
  String _typedSubtitle = '';
  static const String _fullSubtitle = 'Next-Generation Autonomous Companion';

  // AI config states for Screen 3
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

  // Strict OLED Monochrome Palette
  static const Color _bgBlack = Color(0xFF000000);
  static const Color _surfaceCard = Color(0xFF111111);
  static const Color _surfaceCardAlt = Color(0xFF0D0D0D);
  static const Color _borderDark = Color(0xFF222222);
  static const Color _textWhite = Color(0xFFFFFFFF);
  static const Color _textMuted = Color(0xFF888888);
  static const Color _textSubtle = Color(0xFF555555);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTypingAnimation();
    _loadAiDefaults();
    _checkPermissions();
  }

  void _startTypingAnimation() {
    int charIndex = 0;
    _typingTimer?.cancel();
    _typingTimer = Timer.periodic(const Duration(milliseconds: 32), (timer) {
      if (charIndex < _fullSubtitle.length) {
        charIndex++;
        if (mounted) {
          setState(() {
            _typedSubtitle = _fullSubtitle.substring(0, charIndex);
          });
        }
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _loadAiDefaults() async {
    await _aiService.init();
    if (!mounted) return;
    if (_aiService.isConfigured) {
      setState(() {
        _selectedProvider = 'custom';
        _apiKeyController.text = _aiService.apiKey;
        _baseUrlController.text = _aiService.baseUrl;
        _modelController.text = _aiService.model;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _typingTimer?.cancel();
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

    if (mounted) {
      setState(() {
        _isAccessibilityGranted = accessibilityRunning;
        _isOverlayGranted = overlayGranted;
        _isMicrophoneGranted = microphoneStatus.isGranted;
        _isNotificationsGranted = notificationsStatus.isGranted;
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

  Future<void> _completeSetup({bool skipValidation = false}) async {
    final apiKey = _apiKeyController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    final model = _modelController.text.trim();

    if (!skipValidation) {
      if (baseUrl.isEmpty || model.isEmpty) {
        setState(() {
          _validationError = 'Base URL and Model name are required.';
        });
        return;
      }

      if (_selectedProvider != 'ollama' && apiKey.isEmpty) {
        setState(() {
          _validationError = 'API Key is required for cloud providers.';
        });
        return;
      }

      setState(() {
        _isValidating = true;
        _validationError = null;
      });

      try {
        final models = await _aiService.fetchAvailableModels(baseUrl, apiKey);
        if (models.isEmpty && _selectedProvider != 'ollama') {
          setState(() {
            _validationError =
                'Could not reach provider. Check your network & API Key.';
            _isValidating = false;
          });
          return;
        }
      } catch (e) {
        setState(() {
          _validationError =
              'Connection failed: ${e.toString().replaceFirst('Exception: ', '')}';
          _isValidating = false;
        });
        return;
      }
    }

    // Save configuration
    await _aiService.saveSettings(
      apiKey: apiKey,
      baseUrl: baseUrl.isNotEmpty ? baseUrl : AiService.nvidiaBaseUrl,
      model: model.isNotEmpty ? model : AiService.nvidiaDefaultModel,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);

    // Auto-launch floating bubble if privileges exist
    if (_isOverlayGranted && FeatureFlags.floatingOverlayEnabled) {
      await FloatingBubbleService.startBubble();
    }

    if (mounted) {
      setState(() => _isValidating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'BoopAgent terminal initialized.',
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
  }

  void _nextPage() {
    if (_currentStep < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _prevPage() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgBlack,
      body: SafeArea(
        child: Column(
          children: [
            // Top Terminal Bar
            _buildTerminalTopBar(),

            // PageView with 3 Terminal Screens
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) {
                  setState(() => _currentStep = index);
                },
                children: [
                  _buildScreen1Branding(),
                  _buildScreen2Permissions(),
                  _buildScreen3NeuralEngine(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // TOP TERMINAL STATUS BAR
  // --------------------------------------------------------------------------
  Widget _buildTerminalTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _borderDark, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: _textWhite,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'BOOP_CORE // v1.0.13',
                style: TextStyle(
                  color: _textMuted,
                  fontSize: 11,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          Row(
            children: List.generate(3, (index) {
              final isActive = index == _currentStep;
              final isPassed = index < _currentStep;
              return Container(
                margin: const EdgeInsets.only(left: 6),
                width: isActive ? 22 : 8,
                height: 4,
                decoration: BoxDecoration(
                  color: isActive
                      ? _textWhite
                      : (isPassed ? const Color(0xFF666666) : const Color(0xFF222222)),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // SCREEN 1: MINIMALIST CYBERNETIC BRANDING
  // --------------------------------------------------------------------------
  Widget _buildScreen1Branding() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),

          // Minimalist Cybernetic Glyph
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: _surfaceCard,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: _borderDark, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withOpacity(0.04),
                    blurRadius: 32,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.terminal_rounded,
                  color: _textWhite,
                  size: 42,
                ),
              ),
            ),
          ),
          const SizedBox(height: 36),

          // Monolithic Title
          const Center(
            child: Text(
              'BoopAgent',
              style: TextStyle(
                color: _textWhite,
                fontSize: 38,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.2,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Animated Typing Subtitle
          Center(
            child: Text(
              _typedSubtitle.isEmpty ? ' ' : _typedSubtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _textMuted,
                fontSize: 14,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 36),

          // Core System Pills
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surfaceCardAlt,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _borderDark, width: 1),
            ),
            child: Column(
              children: [
                _buildFeatureRow(
                  Icons.precision_manufacturing_outlined,
                  'Autonomous Phone Control',
                  'Local UI screen reading, taps & system navigation',
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(color: _borderDark, height: 1),
                ),
                _buildFeatureRow(
                  Icons.security_outlined,
                  'Privacy by Architecture',
                  'Zero data harvesting, direct inference pipeline',
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(color: _borderDark, height: 1),
                ),
                _buildFeatureRow(
                  Icons.layers_outlined,
                  'Floating Assistant HUD',
                  'Zero-friction autonomous bubble overlay',
                ),
              ],
            ),
          ),

          const Spacer(),

          // Monolithic "Enter Terminal →" Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _nextPage,
              style: ElevatedButton.styleFrom(
                backgroundColor: _textWhite,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Enter Terminal',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _surfaceCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _borderDark, width: 1),
          ),
          child: Icon(icon, color: _textWhite, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _textWhite,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: _textMuted,
                  fontSize: 11.5,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // SCREEN 2: INTERACTIVE PERMISSION GRID
  // --------------------------------------------------------------------------
  Widget _buildScreen2Permissions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '// STEP 02: SYSTEM PRIVILEGES',
            style: TextStyle(
              color: _textMuted,
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Bridge Authorizations',
            style: TextStyle(
              color: _textWhite,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Grant system bridge access to enable automated screen control and voice interface.',
            style: TextStyle(
              color: _textMuted,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),

          // Interactive Permission Grid (2x2 or compact vertical tiles)
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                _buildPermissionTile(
                  icon: Icons.visibility_outlined,
                  title: 'Screen Automation',
                  subtitle: 'Reads UI nodes and simulates taps/scrolls',
                  isGranted: _isAccessibilityGranted,
                  isRequired: true,
                  onTap: () => _screenAutomationService.openAccessibilitySettings(),
                ),
                const SizedBox(height: 12),
                _buildPermissionTile(
                  icon: Icons.layers_outlined,
                  title: 'Floating Overlay',
                  subtitle: 'Enables quick HUD shortcut over other apps',
                  isGranted: _isOverlayGranted,
                  isRequired: true,
                  onTap: () async {
                    await FloatingBubbleService.requestPermission();
                    _checkPermissions();
                  },
                ),
                const SizedBox(height: 12),
                _buildPermissionTile(
                  icon: Icons.mic_none_outlined,
                  title: 'Voice Input',
                  subtitle: 'Audio capture for hands-free speech prompt',
                  isGranted: _isMicrophoneGranted,
                  isRequired: false,
                  onTap: () async {
                    await Permission.microphone.request();
                    _checkPermissions();
                  },
                ),
                const SizedBox(height: 12),
                _buildPermissionTile(
                  icon: Icons.notifications_none_outlined,
                  title: 'Task Notifications',
                  subtitle: 'Background progress alerts and completion reports',
                  isGranted: _isNotificationsGranted,
                  isRequired: false,
                  onTap: () async {
                    await Permission.notification.request();
                    _checkPermissions();
                  },
                ),
              ],
            ),
          ),

          // Navigation Row
          Row(
            children: [
              OutlinedButton(
                onPressed: _prevPage,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _textWhite,
                  side: const BorderSide(color: _borderDark),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('← Back'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _nextPage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _textWhite,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Configure Engine →',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildPermissionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isGranted,
    required bool isRequired,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isGranted ? const Color(0xFF333333) : _borderDark,
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isGranted ? Colors.white : const Color(0xFF18181A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 20,
              color: isGranted ? Colors.black : Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _textWhite,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (isRequired) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF222222),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'REQ',
                          style: TextStyle(
                            color: Color(0xFFAAAAAA),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _textMuted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isGranted ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isGranted ? const Color(0xFF333333) : Colors.transparent,
                ),
              ),
              child: Text(
                isGranted ? 'ONLINE' : 'GRANT',
                style: TextStyle(
                  color: isGranted ? Colors.white : Colors.black,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace',
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // SCREEN 3: MINIMALIST NEURAL ENGINE SELECT
  // --------------------------------------------------------------------------
  Widget _buildScreen3NeuralEngine() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '// STEP 03: NEURAL ENGINE INFERENCE',
            style: TextStyle(
              color: _textMuted,
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Neural Engine',
            style: TextStyle(
              color: _textWhite,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Choose your inference provider. Encrypted on-device.',
            style: TextStyle(
              color: _textMuted,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),

          // Monochrome Provider Badges
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildProviderBadge('nvidia', 'NVIDIA NIM'),
                _buildProviderBadge('deepseek', 'DeepSeek'),
                _buildProviderBadge('groq', 'Groq'),
                _buildProviderBadge('ollama', 'Ollama / Local'),
                _buildProviderBadge('custom', 'Custom Endpoint'),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                // API Key field (Monospace)
                Container(
                  decoration: BoxDecoration(
                    color: _surfaceCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _borderDark, width: 1),
                  ),
                  child: TextField(
                    controller: _apiKeyController,
                    obscureText: _obscureKey,
                    style: const TextStyle(
                      color: _textWhite,
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      labelStyle: const TextStyle(color: _textMuted, fontSize: 13),
                      hintText: _selectedProvider == 'nvidia'
                          ? 'nvapi-...'
                          : (_selectedProvider == 'ollama'
                              ? 'Optional for local Ollama'
                              : 'sk-...'),
                      hintStyle: const TextStyle(color: _textSubtle, fontSize: 12),
                      prefixIcon: const Icon(Icons.key_rounded, color: _textMuted, size: 18),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureKey ? Icons.visibility_off : Icons.visibility,
                          color: _textMuted,
                          size: 18,
                        ),
                        onPressed: () => setState(() => _obscureKey = !_obscureKey),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Base URL field
                Container(
                  decoration: BoxDecoration(
                    color: _surfaceCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _borderDark, width: 1),
                  ),
                  child: TextField(
                    controller: _baseUrlController,
                    style: const TextStyle(
                      color: _textWhite,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Base URL',
                      labelStyle: TextStyle(color: _textMuted, fontSize: 13),
                      prefixIcon: Icon(Icons.dns_rounded, color: _textMuted, size: 18),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Model name field
                Container(
                  decoration: BoxDecoration(
                    color: _surfaceCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _borderDark, width: 1),
                  ),
                  child: TextField(
                    controller: _modelController,
                    style: const TextStyle(
                      color: _textWhite,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Model Name',
                      labelStyle: TextStyle(color: _textMuted, fontSize: 13),
                      prefixIcon: Icon(Icons.smart_toy_rounded, color: _textMuted, size: 18),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),

                if (_validationError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E0D0D),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF4A1E1E), width: 1),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _validationError!,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Bottom Action Row
          Row(
            children: [
              OutlinedButton(
                onPressed: _prevPage,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _textWhite,
                  side: const BorderSide(color: _borderDark),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('← Back'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isValidating ? null : () => _completeSetup(skipValidation: false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _textWhite,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isValidating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.black),
                            ),
                          )
                        : const Text(
                            'Initialize BoopAgent →',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => _completeSetup(skipValidation: true),
              child: const Text(
                'Skip for now (configure later in Settings)',
                style: TextStyle(color: _textSubtle, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildProviderBadge(String id, String label) {
    final isSelected = _selectedProvider == id;
    return GestureDetector(
      onTap: () => _selectProvider(id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _textWhite : _surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.transparent : _borderDark,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : _textMuted,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
