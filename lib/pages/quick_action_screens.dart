import 'package:flutter/material.dart';

class PayLaterScreen extends StatelessWidget {
  const PayLaterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pay Later')),
      body: const Center(child: Text('Pay Later Screen')),
    );
  }
}

class SavedAddressScreen extends StatelessWidget {
  const SavedAddressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Addresses')),
      body: const Center(child: Text('Saved Addresses Screen')),
    );
  }
}

class MembershipScreen extends StatelessWidget {
  const MembershipScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Membership')),
      body: const Center(child: Text('Membership Screen')),
    );
  }
}

class PointsScreen extends StatelessWidget {
  const PointsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Points')),
      body: const Center(child: Text('Points Screen')),
    );
  }
}
