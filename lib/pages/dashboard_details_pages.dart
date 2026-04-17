import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../locale_controller.dart';

// ============== EDIT PROFILE SCREEN ==============
class EditProfileScreen extends StatelessWidget {
  const EditProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final localeController = Get.find<LocaleController>();
    return Scaffold(
      appBar: AppBar(title: Text(localeController.get('Edit Profile', 'প্রোফাইল এডিট'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const CircleAvatar(radius: 50, child: Icon(Icons.camera_alt, size: 30)),
            const SizedBox(height: 20),
            _buildField(localeController.get('Full Name', 'পুরো নাম'), 'Karim Ahmed'),
            _buildField(localeController.get('Email', 'ইমেইল'), 'karim@example.com'),
            _buildField(localeController.get('Phone', 'ফোন'), '+880 1700000000'),
            _buildField(localeController.get('Address', 'ঠিকানা'), 'Dhaka, Bangladesh'),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Get.back(),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10713C)),
                child: Text(localeController.get('Save Changes', 'পরিবর্তন সংরক্ষণ করুন'), style: const TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, String initialValue) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        initialValue: initialValue,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }
}

// ============== DOCUMENTS SCREEN ==============
class DocumentsScreen extends StatelessWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final localeController = Get.find<LocaleController>();
    return Scaffold(
      appBar: AppBar(title: Text(localeController.get('My Documents', 'আমার নথিপত্র'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _docItem(context, localeController.get('NID / Smart Card', 'এনআইডি কার্ড'), true),
          _docItem(context, localeController.get('Driving License', 'ড্রাইভিং লাইসেন্স'), true),
          _docItem(context, localeController.get('Trade License', 'ট্রেড লাইসেন্স'), false),
          _docItem(context, localeController.get('TIN Certificate', 'টিন সার্টিফিকেট'), false),
        ],
      ),
    );
  }

  Widget _docItem(BuildContext context, String title, bool isUploaded) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(isUploaded ? 'Uploaded' : 'Pending', style: TextStyle(color: isUploaded ? Colors.green : Colors.orange)),
        trailing: Icon(isUploaded ? Icons.check_circle : Icons.upload_file, color: isUploaded ? Colors.green : Colors.grey),
        onTap: () {},
      ),
    );
  }
}

// ============== TRIP HISTORY SCREEN ==============
class TripHistoryScreen extends StatelessWidget {
  const TripHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final localeController = Get.find<LocaleController>();
    return Scaffold(
      appBar: AppBar(title: Text(localeController.get('Trip History', 'ট্রিপ হিস্ট্রি'))),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        itemBuilder: (context, index) => Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Trip #102$index', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Text('৳ 450', style: TextStyle(color: Color(0xFF10713C), fontWeight: FontWeight.bold)),
                  ],
                ),
                const Divider(),
                const Text('From: Dhaka Airport', style: TextStyle(fontSize: 13)),
                const Text('To: Gulshan 2', style: TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                    SizedBox(width: 4),
                    Text('12 April 2026', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============== MY VEHICLES SCREEN ==============
class MyVehiclesScreen extends StatelessWidget {
  const MyVehiclesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final localeController = Get.find<LocaleController>();
    return Scaffold(
      appBar: AppBar(
        title: Text(localeController.get('My Vehicles', 'আমার যানবাহন')),
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: () {})],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _carCard('Toyota Prius', 'DH-1234', 'Active'),
          _carCard('Honda Civic', 'DH-5678', 'In Review'),
        ],
      ),
    );
  }

  Widget _carCard(String model, String plate, String status) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.directions_car, color: Color(0xFF10713C), size: 30),
        title: Text(model, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('Plate: $plate'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: status == 'Active' ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
          child: Text(status, style: TextStyle(fontSize: 12, color: status == 'Active' ? Colors.green : Colors.orange, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
