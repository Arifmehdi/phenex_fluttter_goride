import 'package:flutter/material.dart';

/// A simple, reusable static-content screen for legal pages.
/// Use [LegalScreen.terms] and [LegalScreen.privacy] for the two pages.
///
/// The text below is a standard starting template for a ride-share app —
/// edit the section bodies to match your final policy, and have it reviewed
/// by legal counsel before launch.
class LegalScreen extends StatelessWidget {
  final String title;
  final String effectiveDate;
  final List<LegalSection> sections;

  const LegalScreen._({
    required this.title,
    required this.effectiveDate,
    required this.sections,
  });

  static const _brand = Color(0xFF10713C);
  static const _company = 'Phenexsoft IT';
  static const _appName = 'GoRide';
  static const _contactEmail = 'support@goride.app';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: _brand,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Effective date: $effectiveDate',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 20),
          for (final s in sections) ...[
            Text(
              s.heading,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              s.body,
              style: const TextStyle(
                fontSize: 14,
                height: 1.55,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 18),
          ],
          const Divider(),
          const SizedBox(height: 8),
          Text(
            'Questions? Contact $_company at $_contactEmail.',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  // ── Terms of Service ──────────────────────────────────────────────
  factory LegalScreen.terms() => const LegalScreen._(
        title: 'Terms of Service',
        effectiveDate: '12 July 2026',
        sections: [
          LegalSection('1. Acceptance of Terms',
              'By creating an account or using the $_appName app, you agree to these Terms of Service. If you do not agree, please do not use the app.'),
          LegalSection('2. The Service',
              '$_appName is a technology platform that connects riders with independent drivers for transportation. $_company provides the platform; drivers provide the transportation.'),
          LegalSection('3. Accounts',
              'You must provide accurate information when registering and keep your login credentials secure. You are responsible for all activity under your account. You must be at least 18 years old to register as a driver.'),
          LegalSection('4. Rider Responsibilities',
              'You agree to provide accurate pickup and destination details, treat drivers with respect, pay the fare shown for each trip, and not use the service for any unlawful purpose.'),
          LegalSection('5. Driver Responsibilities',
              'Drivers must hold a valid driving licence and vehicle documents, comply with all traffic laws, keep their vehicle roadworthy, and complete accepted trips safely and professionally.'),
          LegalSection('6. Fares and Payment',
              'Fares are calculated from distance, time, and any applicable surge pricing, and are shown before you confirm a ride. Payment may be made by cash, wallet, card, or supported mobile payment. Cancellation fees may apply as described in the app.'),
          LegalSection('7. Cancellations',
              'Either party may cancel a ride before it begins. Cancellations after a driver has been assigned or has arrived may incur a cancellation fee, which is disclosed in the app.'),
          LegalSection('8. Conduct and Safety',
              'Harassment, discrimination, unsafe behaviour, or fraud will result in account suspension or termination. Safety features such as SOS and trip sharing are provided to help protect users.'),
          LegalSection('9. Limitation of Liability',
              'The platform is provided "as is". To the extent permitted by law, $_company is not liable for the acts of independent drivers or riders, or for indirect or consequential damages arising from use of the service.'),
          LegalSection('10. Changes to These Terms',
              'We may update these Terms from time to time. Continued use of the app after changes take effect constitutes acceptance of the revised Terms.'),
        ],
      );

  // ── Privacy Policy ────────────────────────────────────────────────
  factory LegalScreen.privacy() => const LegalScreen._(
        title: 'Privacy Policy',
        effectiveDate: '12 July 2026',
        sections: [
          LegalSection('1. Information We Collect',
              'We collect information you provide (name, mobile number, email), trip details (pickup, destination, route), device location while you use the app, and payment information needed to complete transactions.'),
          LegalSection('2. How We Use Your Information',
              'We use your information to match riders with drivers, calculate fares, process payments, provide live tracking and support, improve the service, and keep the platform safe and secure.'),
          LegalSection('3. Location Data',
              'With your permission, we use your device location to show nearby drivers, enable navigation, and provide live trip tracking. Drivers share location while online so riders can track their trip. You can control location permission in your device settings.'),
          LegalSection('4. Sharing Your Information',
              'During a trip we share limited details between the matched rider and driver (such as name and approximate location) so the ride can be completed. We share data with payment providers to process payments and with authorities where required by law. We do not sell your personal data.'),
          LegalSection('5. Push Notifications',
              'We use notifications to alert you about ride requests, ride status, and important account activity. You can disable notifications in your device settings, though some features may not work correctly without them.'),
          LegalSection('6. Data Security',
              'We use reasonable technical and organisational measures to protect your information. No method of transmission or storage is completely secure, but we work to safeguard your data.'),
          LegalSection('7. Data Retention',
              'We retain your information for as long as your account is active and as needed to provide the service, comply with legal obligations, resolve disputes, and enforce our agreements.'),
          LegalSection('8. Your Rights',
              'You may request access to, correction of, or deletion of your personal data, subject to legal requirements. Contact us using the details below to make a request.'),
          LegalSection('9. Changes to This Policy',
              'We may update this Privacy Policy from time to time. We will make the updated version available in the app, and continued use constitutes acceptance of the changes.'),
        ],
      );
}

class LegalSection {
  final String heading;
  final String body;
  const LegalSection(this.heading, this.body);
}
