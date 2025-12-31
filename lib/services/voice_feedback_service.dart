// lib/services/voice_feedback_service.dart

import 'package:flutter_tts/flutter_tts.dart';
import 'dart:developer';

class VoiceFeedbackService {
  static FlutterTts? _flutterTts;
  static bool _isInitialized = false;

  static Future<void> initialize() async {
    try {
      _flutterTts = FlutterTts();
      await _flutterTts?.setLanguage('en-US');
      await _flutterTts?.setPitch(1.0);
      await _flutterTts?.setSpeechRate(0.6);
      await _flutterTts?.setVolume(0.8);
      _isInitialized = true;
      log('✅ Voice service initialized');
    } catch (e) {
      log('❌ Voice service init error: $e');
    }
  }

  static Future<void> speak(String message) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    try {
      await _flutterTts?.speak(message);
      log('🔊 Voice: $message');
    } catch (e) {
      log('❌ Voice speak error: $e');
    }
  }

  static Future<void> stop() async {
    try {
      await _flutterTts?.stop();
    } catch (e) {
      log('❌ Voice stop error: $e');
    }
  }
}
