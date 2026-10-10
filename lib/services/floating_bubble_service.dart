import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FloatingBubbleService {
  static const MethodChannel _channel =
      MethodChannel('com.privateagent/accessibility');
  static const String prefsKey = 'isFloatingBubbleEnabled';
  static const String legacyPrefsKey = 'floating_bubble_enabled';

  /// Reads whether the user has enabled the Floating Assistant Bubble
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefsKey) ?? prefs.getBool(legacyPrefsKey) ?? false;
  }

  /// Checks if SYSTEM_ALERT_WINDOW permission is granted
  static Future<bool> isPermissionGranted() async {
    try {
      final res = await _channel.invokeMethod<bool>('checkOverlayPermission');
      if (res != null) return res;
    } catch (_) {}
    try {
      return await FlutterOverlayWindow.isPermissionGranted();
    } catch (_) {
      return false;
    }
  }

  /// Requests SYSTEM_ALERT_WINDOW permission
  static Future<void> requestPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } catch (_) {
      try {
        await FlutterOverlayWindow.requestPermission();
      } catch (_) {}
    }
  }

  /// Master Start: launches the floating bubble overlay
  static Future<bool> startBubble() async {
    final granted = await isPermissionGranted();
    if (!granted) {
      await requestPermission();
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKey, true);
    await prefs.setBool(legacyPrefsKey, true);

    // 1. Launch native Android FloatingOverlayService
    try {
      await _channel.invokeMethod('startFloatingBubble');
    } catch (e) {
      debugPrint('FloatingOverlayService start error: $e');
    }

    // 2. Also start FlutterOverlayWindow overlay if not active
    try {
      if (!await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.showOverlay(
          enableDrag: true,
          overlayTitle: 'BoopAgent',
          overlayContent: 'Floating Assistant',
          flag: OverlayFlag.focusPointer,
          alignment: OverlayAlignment.centerRight,
          visibility: NotificationVisibility.visibilitySecret,
          positionGravity: PositionGravity.auto,
          startPosition: const OverlayPosition(0, 200),
          width: 56,
          height: 56,
        );
      }
    } catch (e) {
      debugPrint('FlutterOverlayWindow show error: $e');
    }

    return true;
  }

  /// Master Stop: dismisses both native and flutter overlay views cleanly
  static Future<void> stopBubble() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKey, false);
    await prefs.setBool(legacyPrefsKey, false);

    // 1. Stop native FloatingOverlayService
    try {
      await _channel.invokeMethod('stopFloatingBubble');
    } catch (e) {
      debugPrint('FloatingOverlayService stop error: $e');
    }

    // 2. Stop FlutterOverlayWindow
    try {
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.closeOverlay();
      }
    } catch (e) {
      debugPrint('FlutterOverlayWindow close error: $e');
    }
  }

  /// Toggles the floating bubble master state
  static Future<bool> setEnabled(bool enable) async {
    if (enable) {
      return await startBubble();
    } else {
      await stopBubble();
      return true;
    }
  }
}
