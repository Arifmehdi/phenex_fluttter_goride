import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:get/get.dart';

class VoiceGuidanceService extends GetxService {
  late FlutterTts _tts;
  final RxBool isVoiceEnabled = true.obs;
  bool _isSpeaking = false;

  @override
  void onInit() {
    super.onInit();
    _initTts();
  }

  Future<void> _initTts() async {
    _tts = FlutterTts();

    // Set speech rate slightly slower for clear navigation announcements
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);

    // Listen for completion to reset the speaking flag
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
    });

    _tts.setErrorHandler((msg) {
      _isSpeaking = false;
      debugPrint('TTS Error: $msg');
    });

    // Try to set English as default language
    try {
      await _tts.setLanguage('en-US');
    } catch (e) {
      debugPrint('Could not set TTS language: $e');
    }
  }

  /// Speak a navigation instruction aloud
  Future<void> announceInstruction(String instruction) async {
    if (!isVoiceEnabled.value || _isSpeaking) return;

    try {
      _isSpeaking = true;
      await _tts.speak(instruction);
    } catch (e) {
      debugPrint('TTS speak error: $e');
      _isSpeaking = false;
    }
  }

  /// Speak a distance-based update (e.g., "In 200 meters, turn right")
  Future<void> announceDistanceUpdate({
    required String instruction,
    String? distanceText,
  }) async {
    if (!isVoiceEnabled.value) return;

    String message;
    if (distanceText != null && distanceText.isNotEmpty) {
      message = '$distanceText, $instruction';
    } else {
      message = instruction;
    }

    await announceInstruction(message);
  }

  /// Speak the destination arrival message
  Future<void> announceArrival() async {
    await announceInstruction('You have arrived at your destination.');
  }

  /// Toggle voice guidance on/off
  void toggleVoice() {
    isVoiceEnabled.value = !isVoiceEnabled.value;
    if (!isVoiceEnabled.value) {
      _tts.stop();
      _isSpeaking = false;
    }
  }

  /// Stop any ongoing speech
  Future<void> stop() async {
    await _tts.stop();
    _isSpeaking = false;
  }

  @override
  void onClose() {
    _tts.stop();
    super.onClose();
  }
}
