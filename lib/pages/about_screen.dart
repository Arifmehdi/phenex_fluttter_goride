import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'legal_screen.dart';

/// Static "About GoRide" screen — app identity, version, company, and links
/// to the legal pages. Reached from the sidebar.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _brand = Color(0xFF10713C);
  static const _appName = 'GoRide';
  static const _company = 'Phenexsoft IT';
  static const _version = '1.0.0';
  static const _tagline = 'Your Journey, Our Priority';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 40),
        children: [
          // ── Logo + name ──
          Center(
            child: Column(
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: _brand.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Image.asset(
                    'assets/go_ride_logo.png',
                    height: 56,
                    width: 56,
                    errorBuilder: (context, error, stack) =>
                        const Icon(Icons.directions_car, size: 48, color: _brand),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  _appName,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _brand,
                  ),
                ),
                const SizedBox(height: 4),
                Text(_tagline,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                const SizedBox(height: 6),
                Text('Version $_version',
                    style: TextStyle(fontSize: 13, color: Colors.grey[500])),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // ── About text ──
          const Text(
            'About $_appName',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '$_appName is a ride-sharing platform that connects riders with nearby '
            'drivers for safe, affordable, and convenient trips. Book a car or bike, '
            'track your driver live, chat in-app, and pay by cash, wallet, or card.',
            style: const TextStyle(fontSize: 14, height: 1.55, color: Color(0xFF334155)),
          ),
          const SizedBox(height: 24),

          // ── Legal links ──
          _tile(Icons.description_outlined, 'Terms of Service',
              () => Get.to(() => LegalScreen.terms())),
          _tile(Icons.privacy_tip_outlined, 'Privacy Policy',
              () => Get.to(() => LegalScreen.privacy())),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '© 2026 $_company. All rights reserved.',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: _brand),
      title: Text(label, style: const TextStyle(fontSize: 15)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
      onTap: onTap,
    );
  }
}
