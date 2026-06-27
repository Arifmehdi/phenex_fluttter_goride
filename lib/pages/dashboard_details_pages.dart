import 'dart:io';
import 'package:dio/dio.dart' as dio_lib;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import '../locale_controller.dart';
import '../services/api_service.dart';

// ============== EDIT PROFILE SCREEN ==============
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _api = Get.find<ApiService>();
  final _locale = Get.find<LocaleController>();
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _mobile;
  late final TextEditingController _address;
  late final TextEditingController _bloodGroup;
  late final TextEditingController _emergencyName;
  late final TextEditingController _emergencyPhone;

  XFile? _pickedImage;
  bool _saving = false;
  String? _existingImageUrl;

  @override
  void initState() {
    super.initState();
    final user = _api.getUser() ?? {};
    _name          = TextEditingController(text: user['name'] ?? '');
    _email         = TextEditingController(text: user['email'] ?? '');
    _mobile        = TextEditingController(text: user['mobile'] ?? '');
    _address       = TextEditingController(text: user['address'] ?? '');
    _bloodGroup    = TextEditingController(text: user['blood_group'] ?? '');
    _emergencyName  = TextEditingController(text: user['emergency_contact_name'] ?? '');
    _emergencyPhone = TextEditingController(text: user['emergency_contact_phone'] ?? '');
    _existingImageUrl = user['image'] as String?;
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _mobile, _address, _bloodGroup, _emergencyName, _emergencyPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final img = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (img != null) setState(() => _pickedImage = img);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      // Build multipart-capable request data
      final data = {
        'name':                    _name.text.trim(),
        'email':                   _email.text.trim(),
        'mobile':                  _mobile.text.trim(),
        'address':                 _address.text.trim(),
        'blood_group':             _bloodGroup.text.trim(),
        'emergency_contact_name':  _emergencyName.text.trim(),
        'emergency_contact_phone': _emergencyPhone.text.trim(),
      };

      dio_lib.Response res;
      if (_pickedImage != null) {
        final formData = dio_lib.FormData.fromMap({
          ...data,
          'image': await dio_lib.MultipartFile.fromFile(_pickedImage!.path,
              filename: _pickedImage!.name),
        });
        res = await _api.dio.post('/user/profile',
            data: formData,
            options: dio_lib.Options(method: 'POST', headers: {'X-HTTP-Method-Override': 'PATCH'}));
      } else {
        res = await _api.dio.patch('/user/profile', data: data);
      }

      if (res.statusCode == 200) {
        // Refresh local storage with new user data
        final updated = res.data is Map ? res.data : res.data['data'];
        if (updated != null) await _api.refreshUser(updated as Map<String, dynamic>);
        Get.back(result: true);
        Get.snackbar('Saved', 'Profile updated successfully.',
            backgroundColor: const Color(0xFF10713C), colorText: Colors.white);
      } else {
        final msg = res.data?['message'] ?? 'Failed to save profile.';
        Get.snackbar('Error', msg, backgroundColor: Colors.red, colorText: Colors.white);
      }
    } catch (e) {
      Get.snackbar('Error', 'Could not save. Check your connection.',
          backgroundColor: Colors.red, colorText: Colors.white);
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(_locale.get('Edit Profile', 'প্রোফাইল এডিট')),
        backgroundColor: const Color(0xFF10713C),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar picker
              Center(
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 52,
                        backgroundColor: const Color(0xFF10713C).withValues(alpha: 0.1),
                        backgroundImage: _pickedImage != null
                            ? FileImage(File(_pickedImage!.path)) as ImageProvider
                            : (_existingImageUrl != null ? NetworkImage(_existingImageUrl!) : null),
                        child: (_pickedImage == null && _existingImageUrl == null)
                            ? const Icon(Icons.person, size: 52, color: Color(0xFF10713C))
                            : null,
                      ),
                      Positioned(
                        bottom: 0, right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Color(0xFF10713C), shape: BoxShape.circle),
                          child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),

              _sectionLabel('Personal Info'),
              _field(_name, 'Full Name', Icons.person_outline, required: true),
              _field(_email, 'Email', Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress),
              _field(_mobile, 'Phone', Icons.phone_outlined,
                  keyboardType: TextInputType.phone),
              _field(_address, 'Address', Icons.location_on_outlined),
              _field(_bloodGroup, 'Blood Group', Icons.bloodtype_outlined,
                  hint: 'e.g. A+, O-'),
              const SizedBox(height: 8),

              _sectionLabel('Emergency Contact'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade100),
                ),
                child: Column(
                  children: [
                    Row(children: [
                      Icon(Icons.warning_amber_outlined, color: Colors.red.shade400, size: 18),
                      const SizedBox(width: 8),
                      Text('Used for SOS alerts during trips',
                          style: TextStyle(color: Colors.red.shade600, fontSize: 12)),
                    ]),
                    const SizedBox(height: 12),
                    _field(_emergencyName, 'Contact Name', Icons.person_outline),
                    _field(_emergencyPhone, 'Contact Phone', Icons.phone_outlined,
                        keyboardType: TextInputType.phone),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10713C),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _saving
                      ? const SizedBox(width: 24, height: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(_locale.get('Save Changes', 'পরিবর্তন সংরক্ষণ করুন'),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black54)),
  );

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType? keyboardType,
    String? hint,
    bool required = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextFormField(
          controller: ctrl,
          keyboardType: keyboardType,
          validator: required ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null : null,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            prefixIcon: Icon(icon, color: const Color(0xFF10713C), size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF10713C), width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      );
}

// ============== DOCUMENTS SCREEN ==============
class DocumentsScreen extends StatelessWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final localeController = Get.find<LocaleController>();
    return Scaffold(
      appBar: AppBar(
        title: Text(localeController.get('My Documents', 'আমার নথিপত্র')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _docItem(
            context,
            localeController.get('NID / Smart Card', 'এনআইডি কার্ড'),
            true,
          ),
          _docItem(
            context,
            localeController.get('Driving License', 'ড্রাইভিং লাইসেন্স'),
            true,
          ),
          _docItem(
            context,
            localeController.get('Trade License', 'ট্রেড লাইসেন্স'),
            false,
          ),
          _docItem(
            context,
            localeController.get('TIN Certificate', 'টিন সার্টিফিকেট'),
            false,
          ),
        ],
      ),
    );
  }

  Widget _docItem(BuildContext context, String title, bool isUploaded) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          isUploaded ? 'Uploaded' : 'Pending',
          style: TextStyle(color: isUploaded ? Colors.green : Colors.orange),
        ),
        trailing: Icon(
          isUploaded ? Icons.check_circle : Icons.upload_file,
          color: isUploaded ? Colors.green : Colors.grey,
        ),
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
      appBar: AppBar(
        title: Text(localeController.get('Trip History', 'ট্রিপ হিস্ট্রি')),
      ),
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
                    Text(
                      'Trip #102$index',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Text(
                      '৳ 450',
                      style: TextStyle(
                        color: Color(0xFF10713C),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Divider(),
                const Text(
                  'From: Dhaka Airport',
                  style: TextStyle(fontSize: 13),
                ),
                const Text('To: Gulshan 2', style: TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                    SizedBox(width: 4),
                    Text(
                      '12 April 2026',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
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
        leading: const Icon(
          Icons.directions_car,
          color: Color(0xFF10713C),
          size: 30,
        ),
        title: Text(model, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('Plate: $plate'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: status == 'Active'
                ? Colors.green.withOpacity(0.1)
                : Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            status,
            style: TextStyle(
              fontSize: 12,
              color: status == 'Active' ? Colors.green : Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

// ============== ADMIN PAGES ==============

// ============== USER MANAGEMENT SCREEN ==============
class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Riders'),
            Tab(text: 'Owners'),
            Tab(text: 'Corporate'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUserList('driver'),
          _buildUserList('owner'),
          _buildUserList('corporate'),
        ],
      ),
    );
  }

  Widget _buildUserList(String type) {
    final users = type == 'driver'
        ? [
            {
              'name': 'Karim Ahmed',
              'phone': '+8801700000001',
              'status': 'Active',
              'vehicles': '2',
            },
            {
              'name': 'Rahim Islam',
              'phone': '+8801700000002',
              'status': 'Active',
              'vehicles': '1',
            },
            {
              'name': 'Ali Hassan',
              'phone': '+8801700000003',
              'status': 'Pending',
              'vehicles': '1',
            },
          ]
        : type == 'owner'
        ? [
            {
              'name': 'Mr. Khan',
              'phone': '+8801800000001',
              'status': 'Active',
              'vehicles': '5',
            },
            {
              'name': 'Mr. Rahman',
              'phone': '+8801800000002',
              'status': 'Active',
              'vehicles': '3',
            },
          ]
        : [
            {
              'name': 'TechCorp Ltd.',
              'phone': '+8801900000001',
              'status': 'Active',
              'employees': '50',
            },
            {
              'name': 'ABC Company',
              'phone': '+8801900000002',
              'status': 'Pending',
              'employees': '25',
            },
          ];

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF10713C).withOpacity(0.1),
              child: Icon(
                type == 'driver'
                    ? Icons.drive_eta
                    : (type == 'owner' ? Icons.car_rental : Icons.business),
                color: const Color(0xFF10713C),
              ),
            ),
            title: Text(
              user['name']!,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('${user['phone']} • ${user['status']}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (user['status'] == 'Pending')
                  IconButton(
                    icon: const Icon(Icons.check_circle, color: Colors.green),
                    onPressed: () {},
                  ),
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => _showUserOptions(context, user['name']!),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showUserOptions(BuildContext context, String name) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.visibility),
            title: const Text('View Details'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.block),
            title: const Text('Suspend User'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('Delete', style: TextStyle(color: Colors.red)),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

// ============== VEHICLE MANAGEMENT SCREEN ==============
class VehicleManagementScreen extends StatelessWidget {
  const VehicleManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vehicles = [
      {
        'model': 'Toyota Prius',
        'plate': 'DH-1234',
        'owner': 'Mr. Khan',
        'status': 'Approved',
        'type': 'Sedan',
      },
      {
        'model': 'Honda Civic',
        'plate': 'DH-5678',
        'owner': 'Mr. Rahman',
        'status': 'Approved',
        'type': 'Sedan',
      },
      {
        'model': 'Toyota Hiace',
        'plate': 'DH-9012',
        'owner': 'TechCorp Ltd.',
        'status': 'Pending',
        'type': 'Mini Bus',
      },
      {
        'model': 'BMW X5',
        'plate': 'DH-3456',
        'owner': 'Mr. Ali',
        'status': 'Rejected',
        'type': 'SUV',
      },
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Vehicle Management')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: vehicles.length,
        itemBuilder: (context, index) {
          final v = vehicles[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _getStatusColor(v['status']!).withOpacity(0.1),
                child: Icon(
                  Icons.directions_car,
                  color: _getStatusColor(v['status']!),
                ),
              ),
              title: Text(
                '${v['model']} (${v['plate']})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('${v['owner']} • ${v['type']}'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor(v['status']!).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  v['status']!,
                  style: TextStyle(
                    fontSize: 12,
                    color: _getStatusColor(v['status']!),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              onTap: () => _showVehicleOptions(context, v),
            ),
          );
        },
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Approved':
        return Colors.green;
      case 'Pending':
        return Colors.orange;
      case 'Rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  void _showVehicleOptions(BuildContext context, Map<String, String> vehicle) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.visibility),
            title: const Text('View Details'),
            onTap: () {},
          ),
          if (vehicle['status'] == 'Pending') ...[
            ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: const Text('Approve'),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.cancel, color: Colors.red),
              title: const Text('Reject'),
              onTap: () {},
            ),
          ],
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('Remove', style: TextStyle(color: Colors.red)),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

// ============== PAYMENT MANAGEMENT SCREEN ==============
class PaymentManagementScreen extends StatelessWidget {
  const PaymentManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final transactions = [
      {
        'id': 'TXN-001',
        'user': 'Karim Ahmed',
        'type': 'Trip Payment',
        'amount': '৳ 450',
        'status': 'Completed',
        'date': '18 Apr 2026',
      },
      {
        'id': 'TXN-002',
        'user': 'Mr. Khan',
        'type': 'Payout',
        'amount': '৳ 5,000',
        'status': 'Pending',
        'date': '18 Apr 2026',
      },
      {
        'id': 'TXN-003',
        'user': 'TechCorp Ltd.',
        'type': 'Corporate Payment',
        'amount': '৳ 25,000',
        'status': 'Completed',
        'date': '17 Apr 2026',
      },
      {
        'id': 'TXN-004',
        'user': 'Rahim Islam',
        'type': 'Trip Payment',
        'amount': '৳ 320',
        'status': 'Completed',
        'date': '17 Apr 2026',
      },
      {
        'id': 'TXN-005',
        'user': 'Mr. Rahman',
        'type': 'Payout',
        'amount': '৳ 8,500',
        'status': 'Completed',
        'date': '16 Apr 2026',
      },
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Payment Management')),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            color: const Color(0xFF10713C).withOpacity(0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statItem('Total Revenue', '৳ 1.2M', Colors.green),
                _statItem('Pending Payouts', '৳ 15K', Colors.orange),
                _statItem('Today Transactions', '42', Colors.blue),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: transactions.length,
              itemBuilder: (context, index) {
                final t = transactions[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: t['type'] == 'Payout'
                          ? Colors.orange.withOpacity(0.1)
                          : Colors.green.withOpacity(0.1),
                      child: Icon(
                        t['type'] == 'Payout' ? Icons.output : Icons.payment,
                        color: t['type'] == 'Payout'
                            ? Colors.orange
                            : Colors.green,
                      ),
                    ),
                    title: Text(
                      t['user']!,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('${t['type']} • ${t['date']}'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          t['amount']!,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          t['status']!,
                          style: TextStyle(
                            fontSize: 12,
                            color: t['status'] == 'Completed'
                                ? Colors.green
                                : Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ============== SUPPORT TICKETS SCREEN ==============
class SupportTicketsScreen extends StatelessWidget {
  const SupportTicketsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tickets = [
      {
        'id': 'TKT-001',
        'subject': 'Payment not received',
        'user': 'Karim Ahmed',
        'priority': 'High',
        'status': 'Open',
        'date': '18 Apr 2026',
      },
      {
        'id': 'TKT-002',
        'subject': 'Vehicle verification issue',
        'user': 'Mr. Khan',
        'priority': 'Medium',
        'status': 'Open',
        'date': '17 Apr 2026',
      },
      {
        'id': 'TKT-003',
        'subject': 'Account suspended',
        'user': 'Ali Hassan',
        'priority': 'High',
        'status': 'Pending',
        'date': '16 Apr 2026',
      },
      {
        'id': 'TKT-004',
        'subject': 'App bug report',
        'user': 'Rahim Islam',
        'priority': 'Low',
        'status': 'Resolved',
        'date': '15 Apr 2026',
      },
      {
        'id': 'TKT-005',
        'subject': 'Corporate billing query',
        'user': 'TechCorp Ltd.',
        'priority': 'Medium',
        'status': 'Open',
        'date': '14 Apr 2026',
      },
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Support Tickets')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: tickets.length,
        itemBuilder: (context, index) {
          final t = tickets[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _getPriorityColor(
                  t['priority']!,
                ).withOpacity(0.1),
                child: Icon(
                  Icons.support_agent,
                  color: _getPriorityColor(t['priority']!),
                ),
              ),
              title: Text(
                t['subject']!,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('${t['user']} • ${t['date']}'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _getPriorityColor(t['priority']!).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      t['priority']!,
                      style: TextStyle(
                        fontSize: 10,
                        color: _getPriorityColor(t['priority']!),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t['status']!,
                    style: TextStyle(
                      fontSize: 10,
                      color: t['status'] == 'Open'
                          ? Colors.green
                          : (t['status'] == 'Resolved'
                                ? Colors.blue
                                : Colors.orange),
                    ),
                  ),
                ],
              ),
              onTap: () => _showTicketDetails(context, t),
            ),
          );
        },
      ),
    );
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'High':
        return Colors.red;
      case 'Medium':
        return Colors.orange;
      case 'Low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  void _showTicketDetails(BuildContext context, Map<String, String> ticket) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 40, height: 4, color: Colors.grey[300]),
              ),
              const SizedBox(height: 20),
              Text(
                ticket['subject']!,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ticket ID: ${ticket['id']}',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              _detailRow('User', ticket['user']!),
              _detailRow('Priority', ticket['priority']!),
              _detailRow('Status', ticket['status']!),
              _detailRow('Date', ticket['date']!),
              const SizedBox(height: 20),
              const Text(
                'Message:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Please help resolve this issue as soon as possible.',
              ),
              const SizedBox(height: 20),
              if (ticket['status'] != 'Resolved')
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10713C),
                    ),
                    child: const Text('Reply & Resolve'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// ============== REPORTS & ANALYTICS SCREEN ==============
class ReportsAnalyticsScreen extends StatelessWidget {
  const ReportsAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports & Analytics')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Overview',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _chartCard(
                    'Daily Trips',
                    '156',
                    Icons.route,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _chartCard(
                    'Weekly Growth',
                    '+12%',
                    Icons.trending_up,
                    Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _chartCard(
                    'Active Users',
                    '850',
                    Icons.people,
                    Colors.purple,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _chartCard(
                    'Revenue',
                    '৳ 45K',
                    Icons.account_balance,
                    Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Top Performing Areas',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _areaItem('Gulshan', '245 trips', 0.8),
            _areaItem('Banani', '198 trips', 0.65),
            _areaItem('Dhanmondi', '156 trips', 0.5),
            _areaItem('Mirpur', '132 trips', 0.4),
            _areaItem('Uttara', '98 trips', 0.3),
            const SizedBox(height: 24),
            const Text(
              'Vehicle Types',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _vehicleTypeItem('Sedan', '65%', Colors.blue),
            _vehicleTypeItem('SUV', '20%', Colors.green),
            _vehicleTypeItem('Mini Bus', '10%', Colors.orange),
            _vehicleTypeItem('Others', '5%', Colors.grey),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.download, color: Colors.white),
                label: const Text(
                  'Export Report',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10713C),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _chartCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _areaItem(String area, String trips, double progress) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(area, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(trips, style: const TextStyle(color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.grey[200],
              valueColor: const AlwaysStoppedAnimation(Color(0xFF10713C)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vehicleTypeItem(String type, String percentage, Color color) {
    return ListTile(
      leading: CircleAvatar(
        radius: 15,
        backgroundColor: color.withOpacity(0.1),
        child: Icon(Icons.directions_car, size: 16, color: color),
      ),
      title: Text(type),
      trailing: Text(
        '$percentage',
        style: TextStyle(fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

// ============== SYSTEM SETTINGS SCREEN ==============
class SystemSettingsScreen extends StatefulWidget {
  const SystemSettingsScreen({super.key});

  @override
  State<SystemSettingsScreen> createState() => _SystemSettingsScreenState();
}

class _SystemSettingsScreenState extends State<SystemSettingsScreen> {
  bool _maintenanceMode = false;
  bool _registrationOpen = true;
  bool _driverApproval = true;
  bool _pushNotifications = true;
  String _commissionRate = '15%';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('System Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader('General'),
          _settingsTile(
            'Maintenance Mode',
            'Put app in maintenance',
            Icons.build,
            trailing: Switch(
              value: _maintenanceMode,
              onChanged: (v) => setState(() => _maintenanceMode = v),
            ),
          ),
          _settingsTile(
            'Registration',
            'Allow new user registration',
            Icons.person_add,
            trailing: Switch(
              value: _registrationOpen,
              onChanged: (v) => setState(() => _registrationOpen = v),
            ),
          ),
          const Divider(),
          _buildSectionHeader('Approval Settings'),
          _settingsTile(
            'Rider Approval',
            'Manual driver approval required',
            Icons.approval,
            trailing: Switch(
              value: _driverApproval,
              onChanged: (v) => setState(() => _driverApproval = v),
            ),
          ),
          const Divider(),
          _buildSectionHeader('Commission'),
          _settingsTile(
            'Commission Rate',
            _commissionRate,
            Icons.percent,
            onTap: () => _showCommissionDialog(),
          ),
          const Divider(),
          _buildSectionHeader('Notifications'),
          _settingsTile(
            'Push Notifications',
            'Send push notifications',
            Icons.notifications,
            trailing: Switch(
              value: _pushNotifications,
              onChanged: (v) => setState(() => _pushNotifications = v),
            ),
          ),
          const Divider(),
          _buildSectionHeader('App Info'),
          _settingsTile('App Version', '1.0.0', Icons.info),
          _settingsTile('Build Number', '2026.04.18', Icons.code),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10713C),
                padding: const EdgeInsets.symmetric(vertical: 14),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
              ),
              child: const Text(
                'Save Settings',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Color(0xFF10713C),
        ),
      ),
    );
  }

  Widget _settingsTile(
    String title,
    String subtitle,
    IconData icon, {
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF10713C).withOpacity(0.1),
        child: Icon(icon, color: const Color(0xFF10713C)),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle),
      trailing: trailing ?? const Icon(Icons.arrow_forward_ios, size: 14),
      onTap: onTap,
    );
  }

  void _showCommissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Commission Rate'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _commissionOption('10%'),
            _commissionOption('15%'),
            _commissionOption('20%'),
            _commissionOption('25%'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _commissionOption(String rate) {
    return RadioListTile<String>(
      title: Text(rate),
      value: rate,
      groupValue: _commissionRate,
      onChanged: (v) => setState(() => _commissionRate = v!),
    );
  }
}
