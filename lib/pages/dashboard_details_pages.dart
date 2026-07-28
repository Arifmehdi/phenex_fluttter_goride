import 'dart:io';
import 'package:dio/dio.dart' as dio_lib;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import '../locale_controller.dart';
import '../services/api_service.dart';
import 'admin_screens.dart' show AdminTicketDetailScreen;

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
    // Users store their photo in 'image'; drivers in 'profile_image'.
    // Normalize to a full URL — login responses hold the raw storage path.
    _existingImageUrl =
        ApiService.fileUrl((user['image'] ?? user['profile_image']) as String?);
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
        // Refresh local storage with the updated user. The payload arrives
        // wrapped ({user: {...}} / {data: {...}}) — unwrap it; merging the
        // wrapper itself would leave the stored profile unchanged, making
        // the save look like it silently failed.
        final body = res.data;
        final updated = (body is Map && body['user'] is Map)
            ? body['user']
            : (body is Map && body['data'] is Map)
                ? body['data']
                : null;
        if (updated != null) {
          await _api.refreshUser(Map<String, dynamic>.from(updated as Map));
        }
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

// ============== MY VEHICLES SCREEN ==============
/// The driver's own registered vehicle, straight from their verification
/// profile (vehicle info lives on the drivers table, entered during signup).
class MyVehiclesScreen extends StatefulWidget {
  const MyVehiclesScreen({super.key});

  @override
  State<MyVehiclesScreen> createState() => _MyVehiclesScreenState();
}

class _MyVehiclesScreenState extends State<MyVehiclesScreen> {
  final _api = Get.find<ApiService>();
  Map<String, dynamic>? _data;
  String _verification = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _api.getDriverProfileStatus();
      if (mounted && res.statusCode == 200 && res.data is Map && res.data['success'] == true) {
        setState(() {
          _data = Map<String, dynamic>.from(res.data['data'] as Map? ?? {});
          _verification = res.data['verification_status']?.toString() ?? '';
          _loading = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final localeController = Get.find<LocaleController>();
    final hasVehicle = (_data?['vehicle_type'] ?? '').toString().isNotEmpty ||
        (_data?['vehicle_plate'] ?? '').toString().isNotEmpty;
    final verified = _verification == 'verified';

    return Scaffold(
      appBar: AppBar(
        title: Text(localeController.get('My Vehicle', 'আমার গাড়ি')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10713C)))
          : RefreshIndicator(
              color: const Color(0xFF10713C),
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (!hasVehicle)
                    Padding(
                      padding: const EdgeInsets.only(top: 120),
                      child: Column(children: [
                        Icon(Icons.directions_car, size: 56, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text('No vehicle registered yet',
                            style: TextStyle(color: Colors.grey[600])),
                        const SizedBox(height: 4),
                        Text('Add your vehicle from the verification steps',
                            style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                      ]),
                    )
                  else ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Icon(Icons.directions_car,
                                  color: Color(0xFF10713C), size: 34),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '${_data?['vehicle_model'] ?? _data?['vehicle_type'] ?? 'Vehicle'}',
                                  style: const TextStyle(
                                      fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: (verified ? Colors.green : Colors.orange)
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  verified ? 'Verified' : (_verification.isEmpty ? 'Pending' : _verification),
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: verified ? Colors.green : Colors.orange),
                                ),
                              ),
                            ]),
                            const Divider(height: 24),
                            _row('Type', _data?['vehicle_type']),
                            _row('Model', _data?['vehicle_model']),
                            _row('Plate number', _data?['vehicle_plate']),
                            _row('Color', _data?['vehicle_color']),
                            _row('Year', _data?['vehicle_year']),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'To change vehicle details, update them in your driver verification profile.',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _row(String label, dynamic value) {
    final v = (value ?? '').toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13))),
        Expanded(
            child: Text(v.isEmpty ? '—' : v,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
      ]),
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
    _tabController = TabController(length: 4, vsync: this);
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
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Passengers'),
            Tab(text: 'Riders'),
            Tab(text: 'Owners'),
            Tab(text: 'Corporate'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _AdminUserList(role: 'user'),
          _AdminUserList(role: 'driver'),
          _AdminUserList(role: 'owner'),
          _AdminUserList(role: 'corporate'),
        ],
      ),
    );
  }

}

/// Real-data user list for one role (Passengers/Riders/Owners/Corporate),
/// with approve / suspend / reject actions wired to the admin API.
class _AdminUserList extends StatefulWidget {
  final String role;
  const _AdminUserList({required this.role});

  @override
  State<_AdminUserList> createState() => _AdminUserListState();
}

class _AdminUserListState extends State<_AdminUserList> {
  final ApiService _api = Get.find<ApiService>();
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final res = await _api.getAdminUsers(role: widget.role);
      if (res.statusCode == 200 && res.data is Map && res.data['success'] == true) {
        final list = res.data['users'] as List? ?? [];
        _users = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _action(Map<String, dynamic> user, String action) async {
    final res = await _api.adminUserAction(user['id'] as int, action);
    final ok = res.statusCode == 200 && res.data is Map && res.data['success'] == true;
    Get.snackbar(
      ok ? 'Done' : 'Error',
      (res.data is Map ? res.data['message'] : null)?.toString() ??
          (ok ? 'Updated' : 'Action failed'),
      backgroundColor: ok ? const Color(0xFF10713C) : Colors.red,
      colorText: Colors.white,
    );
    if (ok) _load();
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'active':
        return Colors.green;
      case 'pending':
      case '0':
        return Colors.orange;
      case 'suspended':
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF10713C)));
    }
    if (_users.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 140),
            Center(child: Text('No ${widget.role} users found',
                style: TextStyle(color: Colors.grey[600]))),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF10713C),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _users.length,
        itemBuilder: (context, i) {
          final u = _users[i];
          final status = (u['status'] ?? '').toString();
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF10713C).withOpacity(0.1),
                child: const Icon(Icons.person, color: Color(0xFF10713C)),
              ),
              title: Text(u['name']?.toString() ?? 'User',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${u['mobile'] ?? u['email'] ?? ''}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _statusColor(status).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(status.isEmpty ? '—' : status,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _statusColor(status))),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (a) => _action(u, a),
                    itemBuilder: (_) => [
                      if (status != 'active')
                        const PopupMenuItem(value: 'approve', child: Text('Approve')),
                      if (status != 'suspended')
                        const PopupMenuItem(value: 'suspend', child: Text('Suspend')),
                      const PopupMenuItem(value: 'reject', child: Text('Reject')),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============== LIVE RIDE MONITORING SCREEN ==============
class LiveRideMonitorScreen extends StatefulWidget {
  const LiveRideMonitorScreen({super.key});

  @override
  State<LiveRideMonitorScreen> createState() => _LiveRideMonitorScreenState();
}

class _LiveRideMonitorScreenState extends State<LiveRideMonitorScreen> {
  final ApiService _api = Get.find<ApiService>();
  List<Map<String, dynamic>> _rides = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final res = await _api.getAdminActiveRides();
      if (res.statusCode == 200 && res.data is Map && res.data['success'] == true) {
        final list = res.data['rides'] as List? ?? [];
        _rides = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'accepted':
        return Colors.blue;
      case 'arriving':
        return Colors.orange;
      case 'in_progress':
        return const Color(0xFF10713C);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Ride Monitoring'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10713C)))
          : RefreshIndicator(
              onRefresh: _load,
              color: const Color(0xFF10713C),
              child: _rides.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 160),
                      Center(
                        child: Column(children: [
                          Icon(Icons.map_outlined, size: 48, color: Colors.grey[300]),
                          const SizedBox(height: 8),
                          Text('No active rides right now',
                              style: TextStyle(color: Colors.grey[600])),
                        ]),
                      ),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _rides.length,
                      itemBuilder: (context, i) {
                        final r = _rides[i];
                        final status = (r['status'] ?? '').toString();
                        final rider = r['rider'] as Map?;
                        final driver = r['driver'] as Map?;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: _statusColor(status).withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(status.replaceAll('_', ' '),
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: _statusColor(status))),
                                    ),
                                    const Spacer(),
                                    Text('৳${(r['fare'] ?? 0)}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF10713C))),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text('${r['pickup_address'] ?? ''} → ${r['destination_address'] ?? ''}',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                const SizedBox(height: 6),
                                Text('Rider: ${rider?['name'] ?? '—'} (${rider?['mobile'] ?? '—'})',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                                Text('Driver: ${driver?['name'] ?? '—'} (${driver?['mobile'] ?? '—'})',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

// ============== SURGE PRICING SCREEN ==============
class SurgeManagementScreen extends StatefulWidget {
  const SurgeManagementScreen({super.key});

  @override
  State<SurgeManagementScreen> createState() => _SurgeManagementScreenState();
}

class _SurgeManagementScreenState extends State<SurgeManagementScreen> {
  final ApiService _api = Get.find<ApiService>();
  List<Map<String, dynamic>> _zones = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final res = await _api.getSurgeZones();
      if (res.statusCode == 200 && res.data is Map && res.data['success'] == true) {
        final list = res.data['zones'] as List? ?? [];
        _zones = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggle(Map<String, dynamic> z) async {
    final res = await _api.updateSurgeZone(z['id'] as int, isActive: !(z['is_active'] == true));
    if (res.statusCode == 200) _load();
  }

  void _showAddDialog() {
    final name = TextEditingController();
    final lat = TextEditingController();
    final lng = TextEditingController();
    final radius = TextEditingController(text: '3');
    final mult = TextEditingController(text: '1.5');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Surge Zone'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Zone name')),
            TextField(controller: lat, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Center latitude')),
            TextField(controller: lng, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Center longitude')),
            TextField(controller: radius, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Radius (km)')),
            TextField(controller: mult, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Multiplier (1-5)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final res = await _api.createSurgeZone(
                name: name.text.trim(),
                centerLat: double.tryParse(lat.text) ?? 0,
                centerLng: double.tryParse(lng.text) ?? 0,
                radiusKm: int.tryParse(radius.text) ?? 3,
                multiplier: double.tryParse(mult.text) ?? 1.5,
              );
              final ok = res.statusCode == 201 || (res.data is Map && res.data['success'] == true);
              Get.snackbar(ok ? 'Added' : 'Error', ok ? 'Surge zone created' : 'Could not create',
                  backgroundColor: ok ? const Color(0xFF10713C) : Colors.red, colorText: Colors.white);
              if (ok) _load();
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Surge Pricing'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF10713C),
        onPressed: _showAddDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Zone'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10713C)))
          : RefreshIndicator(
              onRefresh: _load,
              color: const Color(0xFF10713C),
              child: _zones.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 160),
                      Center(child: Text('No surge zones. Tap "Add Zone".',
                          style: TextStyle(color: Colors.grey[600]))),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _zones.length,
                      itemBuilder: (context, i) {
                        final z = _zones[i];
                        final active = z['is_active'] == true;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: (active ? const Color(0xFF10713C) : Colors.grey).withOpacity(0.1),
                              child: Icon(Icons.bolt, color: active ? const Color(0xFF10713C) : Colors.grey),
                            ),
                            title: Text(z['name']?.toString() ?? 'Zone',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('${z['multiplier']}x • ${z['radius_km'] ?? '-'} km radius'),
                            trailing: Switch(
                              value: active,
                              activeColor: const Color(0xFF10713C),
                              onChanged: (_) => _toggle(z),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

// ============== VEHICLE MANAGEMENT SCREEN ==============
class VehicleManagementScreen extends StatefulWidget {
  const VehicleManagementScreen({super.key});

  @override
  State<VehicleManagementScreen> createState() => _VehicleManagementScreenState();
}

class _VehicleManagementScreenState extends State<VehicleManagementScreen> {
  final ApiService _api = Get.find<ApiService>();
  List<Map<String, dynamic>> _vehicles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final res = await _api.getAdminVehicles();
      if (res.statusCode == 200 && res.data is Map && res.data['success'] == true) {
        final list = res.data['vehicles'] as List? ?? [];
        _vehicles = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setStatus(Map<String, dynamic> v, String status) async {
    final res = await _api.adminVehicleStatus(v['id'] as int, status);
    final ok = res.statusCode == 200 && res.data is Map && res.data['success'] == true;
    Get.snackbar(ok ? 'Updated' : 'Error',
        ok ? 'Vehicle marked $status' : 'Could not update',
        backgroundColor: ok ? const Color(0xFF10713C) : Colors.red,
        colorText: Colors.white);
    if (ok) _load();
  }

  Color _statusColor(String s) {
    switch (s.toLowerCase()) {
      case 'approved':
      case 'active':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Management'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10713C)))
          : RefreshIndicator(
              onRefresh: _load,
              color: const Color(0xFF10713C),
              child: _vehicles.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 160),
                      Center(child: Text('No vehicles',
                          style: TextStyle(color: Colors.grey[600]))),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _vehicles.length,
                      itemBuilder: (context, i) {
                        final v = _vehicles[i];
                        final status = (v['status'] ?? '').toString();
                        final owner = v['owner'] as Map?;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _statusColor(status).withOpacity(0.1),
                              child: Icon(Icons.directions_car, color: _statusColor(status)),
                            ),
                            title: Text(
                                '${v['vehicle_type'] ?? 'Vehicle'} (${v['plate_number'] ?? '-'})',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('${owner?['name'] ?? 'No owner'} • cap ${v['capacity'] ?? '-'}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: _statusColor(status).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(status.isEmpty ? '—' : status,
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: _statusColor(status))),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (s) => _setStatus(v, s),
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'approved', child: Text('Approve')),
                                    PopupMenuItem(value: 'pending', child: Text('Set Pending')),
                                    PopupMenuItem(value: 'rejected', child: Text('Reject')),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
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
class SupportTicketsScreen extends StatefulWidget {
  const SupportTicketsScreen({super.key});

  @override
  State<SupportTicketsScreen> createState() => _SupportTicketsScreenState();
}

class _SupportTicketsScreenState extends State<SupportTicketsScreen> {
  final ApiService _api = Get.find<ApiService>();
  List<Map<String, dynamic>> _tickets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final res = await _api.getAdminSupportTickets();
      if (res.statusCode == 200 && res.data is Map && res.data['success'] == true) {
        final raw = res.data['tickets'];
        final list = (raw is Map ? raw['data'] : raw) as List? ?? [];
        _tickets = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setStatus(Map<String, dynamic> t, String status) async {
    final res = await _api.updateSupportTicketStatus(t['id'] as int, status: status);
    final ok = res.statusCode == 200 && res.data is Map && res.data['success'] == true;
    Get.snackbar(ok ? 'Updated' : 'Error',
        ok ? 'Ticket marked ${status.replaceAll('_', ' ')}' : 'Could not update',
        backgroundColor: ok ? const Color(0xFF10713C) : Colors.red,
        colorText: Colors.white);
    if (ok) _load();
  }

  Color _priorityColor(String p) {
    switch (p) {
      case 'urgent':
      case 'high':
        return Colors.red;
      case 'normal':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'open':
        return Colors.orange;
      case 'in_progress':
        return Colors.blue;
      case 'resolved':
      case 'closed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Support Tickets'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10713C)))
          : RefreshIndicator(
              onRefresh: _load,
              color: const Color(0xFF10713C),
              child: _tickets.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 160),
                      Center(child: Text('No support tickets',
                          style: TextStyle(color: Colors.grey[600]))),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _tickets.length,
                      itemBuilder: (context, i) {
                        final t = _tickets[i];
                        final status = (t['status'] ?? '').toString();
                        final priority = (t['priority'] ?? '').toString();
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _priorityColor(priority).withOpacity(0.1),
                              child: Icon(Icons.support_agent, color: _priorityColor(priority)),
                            ),
                            title: Text(t['subject']?.toString() ?? 'Ticket',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(
                                '#${t['id']} • ${priority.isEmpty ? '' : priority} • ${t['replies_count'] ?? 0} replies'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: _statusColor(status).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(status.replaceAll('_', ' '),
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: _statusColor(status))),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (s) => _setStatus(t, s),
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'in_progress', child: Text('Mark In Progress')),
                                    PopupMenuItem(value: 'resolved', child: Text('Mark Resolved')),
                                    PopupMenuItem(value: 'closed', child: Text('Close')),
                                  ],
                                ),
                              ],
                            ),
                            // Open the full thread — read the customer's
                            // messages and reply from inside the app.
                            onTap: () async {
                              await Get.to(() =>
                                  AdminTicketDetailScreen(ticketId: t['id'] as int));
                              _load();
                            },
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

// ============== REPORTS & ANALYTICS SCREEN ==============
class ReportsAnalyticsScreen extends StatefulWidget {
  const ReportsAnalyticsScreen({super.key});

  @override
  State<ReportsAnalyticsScreen> createState() => _ReportsAnalyticsScreenState();
}

class _ReportsAnalyticsScreenState extends State<ReportsAnalyticsScreen> {
  final ApiService _api = Get.find<ApiService>();
  bool _loading = true;
  double _totalRevenue = 0;
  int _totalRides = 0;
  Map<String, dynamic> _byStatus = {};
  Map<String, dynamic> _byType = {};
  List<Map<String, dynamic>> _topDrivers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.getAdminRevenueReport(),
        _api.getAdminRidesReport(),
        _api.getAdminDriversReport(),
      ]);
      final rev = results[0], rides = results[1], drv = results[2];
      if (rev.statusCode == 200 && rev.data is Map) {
        _totalRevenue = _d(rev.data['total_revenue']);
      }
      if (rides.statusCode == 200 && rides.data is Map) {
        _totalRides = (rides.data['total_rides'] as num?)?.toInt() ?? 0;
        _byStatus = Map<String, dynamic>.from(rides.data['by_status'] ?? {});
        _byType = Map<String, dynamic>.from(rides.data['by_ride_type'] ?? {});
      }
      if (drv.statusCode == 200 && drv.data is Map) {
        final list = (drv.data['drivers'] ?? drv.data['rows'] ?? drv.data['result'] ?? []) as List;
        _topDrivers = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final revStr = _totalRevenue >= 1000
        ? '৳${(_totalRevenue / 1000).toStringAsFixed(1)}k'
        : '৳${_totalRevenue.toStringAsFixed(0)}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & Analytics'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10713C)))
          : RefreshIndicator(
              onRefresh: _load,
              color: const Color(0xFF10713C),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Overview (last 30 days)',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(child: _chartCard('Total Rides', '$_totalRides', Icons.route, Colors.blue)),
                      const SizedBox(width: 12),
                      Expanded(child: _chartCard('Revenue', revStr, Icons.account_balance, Colors.orange)),
                    ]),
                    const SizedBox(height: 24),
                    const Text('Rides by Status',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    if (_byStatus.isEmpty)
                      Text('No data', style: TextStyle(color: Colors.grey[600]))
                    else
                      ..._byStatus.entries.map((e) => _rowItem(
                          e.key.toString().replaceAll('_', ' '), '${e.value}')),
                    const SizedBox(height: 24),
                    const Text('Rides by Vehicle Type',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    if (_byType.isEmpty)
                      Text('No data', style: TextStyle(color: Colors.grey[600]))
                    else
                      ..._byType.entries.map((e) => _rowItem(e.key.toString(), '${e.value}')),
                    const SizedBox(height: 24),
                    const Text('Top Drivers (by earnings)',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    if (_topDrivers.isEmpty)
                      Text('No data', style: TextStyle(color: Colors.grey[600]))
                    else
                      ..._topDrivers.take(10).map((d) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const CircleAvatar(
                              backgroundColor: Color(0x1A10713C),
                              child: Icon(Icons.person, color: Color(0xFF10713C)),
                            ),
                            title: Text(d['name']?.toString() ?? 'Driver'),
                            subtitle: Text('${d['trips'] ?? 0} trips • ⭐ ${d['rating'] ?? '-'}'),
                            trailing: Text('৳${_d(d['earnings']).toStringAsFixed(0)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, color: Color(0xFF10713C))),
                          )),
                    const SizedBox(height: 40),
                  ],
                ),
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _rowItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label[0].toUpperCase() + label.substring(1),
              style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10713C))),
        ],
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
  final ApiService _api = Get.find<ApiService>();
  bool _maintenanceMode = false;
  bool _registrationOpen = true;
  bool _driverApproval = true;
  bool _pushNotifications = true;
  double _commissionValue = 15;
  double _perKm = 20;
  int _matchingRadius = 10; // km — how far to search for drivers on a ride call
  // Rewards / referral economics (0 disables that part of the programme)
  double _takaPerPoint = 10;
  double _referralBonus = 50;
  double _refereeBonus = 50;
  double _payLaterLimit = 0;
  bool _loading = true;
  bool _saving = false;

  String get _commissionRate => '${_commissionValue.toStringAsFixed(0)}%';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _api.getAdminSettings();
      if (res.statusCode == 200 && res.data is Map && res.data['success'] == true) {
        final s = res.data['settings'] as Map;
        _maintenanceMode = s['maintenance_mode'] == true;
        _registrationOpen = s['registration_open'] == true;
        _commissionValue = (s['commission_rate'] as num?)?.toDouble() ?? 15;
        _perKm = (s['per_km_rate'] as num?)?.toDouble() ?? 20;
        _matchingRadius = (s['matching_radius_km'] as num?)?.toInt() ?? 10;
        _takaPerPoint = (s['taka_per_point'] as num?)?.toDouble() ?? 10;
        _referralBonus = (s['referral_bonus'] as num?)?.toDouble() ?? 50;
        _refereeBonus = (s['referee_bonus'] as num?)?.toDouble() ?? 50;
        _payLaterLimit = (s['pay_later_limit'] as num?)?.toDouble() ?? 0;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final res = await _api.saveAdminSettings({
      'maintenance_mode': _maintenanceMode,
      'registration_open': _registrationOpen,
      'commission_rate': _commissionValue,
      'per_km_rate': _perKm,
      'matching_radius_km': _matchingRadius,
      'taka_per_point': _takaPerPoint,
      'referral_bonus': _referralBonus,
      'referee_bonus': _refereeBonus,
      'pay_later_limit': _payLaterLimit,
    });
    final ok = res.statusCode == 200 && res.data is Map && res.data['success'] == true;
    if (mounted) setState(() => _saving = false);
    Get.snackbar(
      ok ? 'Saved' : 'Error',
      ok
          ? 'Settings saved'
          : ((res.data is Map ? res.data['message'] : null)?.toString() ?? 'Could not save'),
      backgroundColor: ok ? const Color(0xFF10713C) : Colors.red,
      colorText: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('System Settings')),
        body: const Center(child: CircularProgressIndicator(color: Color(0xFF10713C))),
      );
    }
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
          _buildSectionHeader('Ride Matching'),
          _buildMatchingRadiusControl(),
          const Divider(),
          _buildSectionHeader('Rewards & Referrals'),
          _settingsTile(
            '৳ per 1 point',
            '1 point per ৳${_takaPerPoint.toStringAsFixed(0)} of completed fare',
            Icons.stars,
            onTap: () => _showAmountDialog(
              title: '৳ per 1 point',
              current: _takaPerPoint,
              min: 1,
              onSaved: (v) => setState(() => _takaPerPoint = v),
            ),
          ),
          _settingsTile(
            'Referral bonus',
            '৳${_referralBonus.toStringAsFixed(0)} to the inviter (0 = off)',
            Icons.card_giftcard,
            onTap: () => _showAmountDialog(
              title: 'Referral bonus (৳)',
              current: _referralBonus,
              onSaved: (v) => setState(() => _referralBonus = v),
            ),
          ),
          _settingsTile(
            'Welcome bonus',
            '৳${_refereeBonus.toStringAsFixed(0)} to the new user (0 = off)',
            Icons.redeem,
            onTap: () => _showAmountDialog(
              title: 'Welcome bonus (৳)',
              current: _refereeBonus,
              onSaved: (v) => setState(() => _refereeBonus = v),
            ),
          ),
          _settingsTile(
            'Pay Later limit',
            _payLaterLimit <= 0
                ? 'Disabled'
                : '৳${_payLaterLimit.toStringAsFixed(0)} credit',
            Icons.schedule,
            onTap: () => _showAmountDialog(
              title: 'Pay Later limit (৳)',
              current: _payLaterLimit,
              onSaved: (v) => setState(() => _payLaterLimit = v),
            ),
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
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10713C),
                padding: const EdgeInsets.symmetric(vertical: 14),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text(
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

  // Preset radius options (km) shown in the dropdown.
  static const List<int> _radiusOptions = [3, 5, 8, 10, 12, 15, 20, 25, 30, 40, 50, 60, 75, 100];

  /// Admin control for the driver search radius — a dropdown of preset km
  /// values plus an "ideal range" note and the exact selected result.
  Widget _buildMatchingRadiusControl() {
    // Ideal band shown to the admin as guidance.
    String idealHint() {
      if (_matchingRadius < 3) return 'Very tight — may miss available drivers';
      if (_matchingRadius <= 10) return 'Ideal for cities & towns';
      if (_matchingRadius <= 15) return 'Good for suburbs / highways';
      return 'Wide — reaches far drivers, longer pickups';
    }

    // Make sure the current value is always selectable, even if it isn't a preset.
    final options = [..._radiusOptions];
    if (!options.contains(_matchingRadius)) {
      options.add(_matchingRadius);
      options.sort();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label row
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF10713C).withOpacity(0.1),
                child: const Icon(Icons.my_location, color: Color(0xFF10713C), size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Driver Search Radius',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Modern full-width dropdown
          DropdownButtonFormField<int>(
            value: _matchingRadius,
            isExpanded: true,
            borderRadius: BorderRadius.circular(14),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF10713C)),
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 16, color: Color(0xFF10713C)),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF10713C).withOpacity(0.05),
              prefixIcon: const Icon(Icons.social_distance_rounded, color: Color(0xFF10713C)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: const Color(0xFF10713C).withOpacity(0.4)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF10713C), width: 1.5),
              ),
            ),
            items: [
              ...options.map((km) => DropdownMenuItem<int>(
                    value: km,
                    child: Text('$km km'),
                  )),
              // -1 is a sentinel that opens the custom-entry dialog.
              const DropdownMenuItem<int>(
                value: -1,
                child: Row(
                  children: [
                    Icon(Icons.edit_rounded, size: 18, color: Color(0xFF10713C)),
                    SizedBox(width: 8),
                    Text('Custom…'),
                  ],
                ),
              ),
            ],
            onChanged: (v) {
              if (v == null) return;
              if (v == -1) {
                _showCustomRadiusDialog();
              } else {
                setState(() => _matchingRadius = v);
              }
            },
          ),
          const SizedBox(height: 10),
          // Exact selected result — Expanded so the hint wraps on any width
          // instead of overflowing off the right edge.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.check_circle, size: 16, color: Color(0xFF16A34A)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Selected: $_matchingRadius km — ${idealHint()}',
                    softWrap: true,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF16A34A))),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF10713C).withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18, color: Color(0xFF10713C)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'When a rider requests a ride, only drivers within $_matchingRadius km get the call.\n'
                    'Ideal: 5–10 km for cities, 10–15 km for suburbs/highways.',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF10713C)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Prompt for any custom radius (1–100 km) when the admin picks "Custom…".
  void _showCustomRadiusDialog() {
    final ctrl = TextEditingController(text: '$_matchingRadius');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom radius'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Radius in km (1–100)',
            suffixText: 'km',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10713C)),
            onPressed: () {
              final v = int.tryParse(ctrl.text.trim());
              if (v == null || v < 1 || v > 100) {
                Get.snackbar('Invalid', 'Enter a number between 1 and 100',
                    backgroundColor: Colors.red, colorText: Colors.white);
                return;
              }
              Navigator.pop(ctx);
              setState(() => _matchingRadius = v);
            },
            child: const Text('Set', style: TextStyle(color: Colors.white)),
          ),
        ],
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
      onChanged: (v) => setState(() =>
          _commissionValue = double.tryParse(v!.replaceAll('%', '')) ?? _commissionValue),
    );
  }

  /// Generic "type a ৳ amount" editor used by the rewards/PayLater settings.
  /// Values are only applied locally — "Save Settings" persists them.
  void _showAmountDialog({
    required String title,
    required double current,
    required ValueChanged<double> onSaved,
    double min = 0,
  }) {
    final controller = TextEditingController(text: current.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(
            prefixText: '৳ ',
            helperText: min > 0 ? 'Minimum $min' : '0 turns this off',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(controller.text.trim());
              if (v != null && v >= min) onSaved(v);
              Navigator.pop(ctx);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// ============== BANNER MANAGEMENT SCREEN ==============
// Admin CRUD for the passenger home-screen banners. Uses the same
// /admin/banners API the web admin panel uses, so changes are managed
// everywhere from one backend.
class BannerManagementScreen extends StatefulWidget {
  const BannerManagementScreen({super.key});

  @override
  State<BannerManagementScreen> createState() => _BannerManagementScreenState();
}

class _BannerManagementScreenState extends State<BannerManagementScreen> {
  final ApiService _api = Get.find<ApiService>();
  final ImagePicker _picker = ImagePicker();
  List<Map<String, dynamic>> _banners = [];
  // Plain guidance shown in the UI — not enforced anywhere.
  static const String _sizeHint = '4727 x 2000';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final res = await _api.getAdminBanners();
      if (res.statusCode == 200 && res.data is Map && res.data['success'] == true) {
        final list = res.data['banners'] as List? ?? [];
        _banners = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } else if (res.statusCode == 403) {
        Get.snackbar('Unauthorized', 'Only admins can manage banners',
            backgroundColor: Colors.red, colorText: Colors.white);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggle(Map<String, dynamic> b) async {
    final res = await _api.saveBanner(
      id: b['id'] as int,
      isActive: !(b['is_active'] == true || b['is_active'] == 1),
    );
    final ok = res.statusCode == 200 || (res.data is Map && res.data['success'] == true);
    if (ok) {
      _load();
    } else {
      Get.snackbar('Error', 'Could not update banner',
          backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  Future<void> _delete(Map<String, dynamic> b) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete banner?'),
        content: const Text('This removes it from the passenger home screen.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final res = await _api.deleteBanner(b['id'] as int);
    final ok = res.statusCode == 200 || (res.data is Map && res.data['success'] == true);
    Get.snackbar(ok ? 'Deleted' : 'Error', ok ? 'Banner removed' : 'Could not delete',
        backgroundColor: ok ? const Color(0xFF10713C) : Colors.red, colorText: Colors.white);
    if (ok) _load();
  }

  void _showEditor([Map<String, dynamic>? existing]) {
    final title = TextEditingController(text: existing?['title']?.toString() ?? '');
    final link = TextEditingController(text: existing?['link']?.toString() ?? '');
    final imageUrl = TextEditingController(text: existing?['image_url']?.toString() ?? '');
    final sortOrder = TextEditingController(text: (existing?['sort_order'] ?? 0).toString());
    String? pickedPath;
    bool active = existing == null
        ? true
        : (existing['is_active'] == true || existing['is_active'] == 1);
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 18,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 14),
                Text(existing == null ? 'Add Banner' : 'Edit Banner',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10713C).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 18, color: Color(0xFF10713C)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('For good result use $_sizeHint px',
                            style: const TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFF10713C),
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
                // Image preview
                if (pickedPath != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(File(pickedPath!),
                        height: 110, width: double.infinity, fit: BoxFit.cover),
                  )
                else if ((existing?['image_url']?.toString() ?? '').isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(existing!['image_url'].toString(),
                        height: 110, width: double.infinity, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox()),
                  ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final x = await _picker.pickImage(
                        source: ImageSource.gallery, imageQuality: 90);
                    if (x != null) setSheet(() => pickedPath = x.path);
                  },
                  icon: const Icon(Icons.image, color: Color(0xFF10713C)),
                  label: Text(pickedPath == null ? 'Pick image from gallery' : 'Change image',
                      style: const TextStyle(color: Color(0xFF10713C))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF10713C)),
                    minimumSize: const Size(double.infinity, 44),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: imageUrl,
                  decoration: const InputDecoration(
                    labelText: '…or paste image URL',
                    hintText: 'https://…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: title,
                  decoration: const InputDecoration(
                      labelText: 'Title (optional)', border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: link,
                  decoration: const InputDecoration(
                      labelText: 'Link (optional)', border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: sortOrder,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Sort order', border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFF10713C),
                  title: const Text('Active'),
                  value: active,
                  onChanged: (v) => setSheet(() => active = v),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10713C),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: saving
                        ? null
                        : () async {
                            if (pickedPath == null && imageUrl.text.trim().isEmpty && existing == null) {
                              Get.snackbar('Image required', 'Pick an image or paste a URL',
                                  backgroundColor: Colors.red, colorText: Colors.white);
                              return;
                            }
                            setSheet(() => saving = true);
                            final res = await _api.saveBanner(
                              id: existing?['id'] as int?,
                              title: title.text.trim(),
                              link: link.text.trim(),
                              imagePath: pickedPath,
                              imageUrl: imageUrl.text.trim(),
                              sortOrder: int.tryParse(sortOrder.text) ?? 0,
                              isActive: active,
                            );
                            final ok = res.statusCode == 200 ||
                                res.statusCode == 201 ||
                                (res.data is Map && res.data['success'] == true);
                            if (ok) {
                              Navigator.pop(ctx);
                              Get.snackbar('Saved', 'Banner saved',
                                  backgroundColor: const Color(0xFF10713C), colorText: Colors.white);
                              _load();
                            } else {
                              setSheet(() => saving = false);
                              final msg = (res.data is Map ? res.data['message'] : null)
                                      ?.toString() ??
                                  'Could not save banner';
                              Get.snackbar('Error', msg,
                                  backgroundColor: Colors.red, colorText: Colors.white);
                            }
                          },
                    child: saving
                        ? const SizedBox(
                            height: 18, width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(existing == null ? 'Create Banner' : 'Save Changes',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Banner Management'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF10713C),
        onPressed: () => _showEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Add Banner'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10713C)))
          : RefreshIndicator(
              onRefresh: _load,
              color: const Color(0xFF10713C),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10713C).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.aspect_ratio, color: Color(0xFF10713C)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'For good result use $_sizeHint px',
                            style: const TextStyle(
                                color: Color(0xFF10713C), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_banners.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 80),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.image_outlined, size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 8),
                            Text('No banners yet. Tap "Add Banner".',
                                style: TextStyle(color: Colors.grey[600])),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._banners.map(_bannerCard),
                ],
              ),
            ),
    );
  }

  Widget _bannerCard(Map<String, dynamic> b) {
    final active = b['is_active'] == true || b['is_active'] == 1;
    final url = b['image_url']?.toString() ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (url.isNotEmpty)
            AspectRatio(
              aspectRatio: 2.36,
              child: Image.network(url, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey[200],
                        child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                      )),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (b['title']?.toString().isNotEmpty ?? false)
                            ? b['title'].toString()
                            : 'Untitled banner',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Order ${b['sort_order'] ?? 0} • ${active ? 'Active' : 'Hidden'}',
                        style: TextStyle(
                            fontSize: 12,
                            color: active ? const Color(0xFF16A34A) : Colors.grey),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: active,
                  activeColor: const Color(0xFF10713C),
                  onChanged: (_) => _toggle(b),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Color(0xFF10713C)),
                  onPressed: () => _showEditor(b),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _delete(b),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
