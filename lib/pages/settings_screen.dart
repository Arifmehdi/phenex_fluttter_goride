import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/voice_guidance_service.dart';

/// App settings — shared by customer (passenger) and rider (driver).
/// Currently hosts the Voice Navigation master toggle.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final voice = Get.find<VoiceGuidanceService>();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: const Color(0xFF10713C),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionLabel('Navigation'),
          _card(
            child: Obx(() => SwitchListTile(
                  value: voice.isVoiceEnabled.value,
                  activeColor: const Color(0xFF10713C),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  secondary: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10713C).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      voice.isVoiceEnabled.value ? Icons.volume_up : Icons.volume_off,
                      color: const Color(0xFF10713C),
                    ),
                  ),
                  title: const Text('Voice Navigation',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  subtitle: Text(
                    voice.isVoiceEnabled.value
                        ? 'Spoken turn-by-turn directions are on'
                        : 'Voice directions are off',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12.5),
                  ),
                  onChanged: (val) => voice.setVoiceEnabled(val),
                )),
          ),
          const SizedBox(height: 6),
          // Info note that reflects the requirement
          Obx(() => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  voice.isVoiceEnabled.value
                      ? 'The voice control will appear on the live tracking screen during a trip.'
                      : 'The voice control is hidden on the live tracking screen.',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              )),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black54)),
      );

  Widget _card({required Widget child}) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: child,
      );
}
