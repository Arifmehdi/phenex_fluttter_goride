import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';

/// Multi-step driver (rider) verification & profile completion.
/// Steps: Personal → NID → License → Vehicle → Photo.
/// Shows a live completion % and uploads text + images per step.
class DriverVerificationScreen extends StatefulWidget {
  const DriverVerificationScreen({super.key});

  @override
  State<DriverVerificationScreen> createState() => _DriverVerificationScreenState();
}

class _DriverVerificationScreenState extends State<DriverVerificationScreen> {
  final ApiService _api = Get.find<ApiService>();
  final ImagePicker _picker = ImagePicker();

  int _step = 0;
  bool _loading = true;
  bool _saving = false;
  int _completion = 0;
  String _verificationStatus = 'incomplete';
  String? _rejectionReason;

  // Text controllers
  final _c = <String, TextEditingController>{};
  // Picked image files (field -> local path)
  final _picked = <String, XFile>{};
  // Existing image URLs from server (field -> url)
  final _existing = <String, String>{};

  static const _steps = ['Personal', 'NID', 'License', 'Vehicle', 'Photo'];

  static const _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
  static const _vehicleTypes = ['car', 'motor', 'cng', 'ambulance'];

  @override
  void initState() {
    super.initState();
    for (final k in [
      'father_name', 'mother_name', 'dob', 'blood_group', 'present_address', 'permanent_address',
      'emergency_contact_name', 'emergency_contact_phone', 'nid', 'license_no',
      'license_expiry', 'vehicle_type', 'vehicle_model', 'vehicle_plate',
      'vehicle_color', 'vehicle_year',
    ]) {
      _c[k] = TextEditingController();
    }
    _load();
  }

  @override
  void dispose() {
    for (final ctrl in _c.values) ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getDriverProfileStatus();
    if (res.statusCode == 200 && res.data['success'] == true) {
      final data = Map<String, dynamic>.from(res.data['data'] ?? {});
      for (final entry in data.entries) {
        final v = entry.value;
        if (v == null) continue;
        if (v is String && v.startsWith('http')) {
          _existing[entry.key] = v;
        } else if (_c.containsKey(entry.key)) {
          _c[entry.key]!.text = v.toString();
        }
      }
      _completion = res.data['profile_completion'] ?? 0;
      _verificationStatus = res.data['verification_status'] ?? 'incomplete';
      _rejectionReason = res.data['rejection_reason'];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickImage(String field) async {
    final img = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (img != null) setState(() => _picked[field] = img);
  }

  Future<void> _saveStep({bool advance = true}) async {
    setState(() => _saving = true);

    final fields = <String, dynamic>{};
    final images = <String, String>{};

    for (final f in _stepTextFields(_step)) {
      if (_c[f]!.text.trim().isNotEmpty) fields[f] = _c[f]!.text.trim();
    }
    for (final f in _stepImageFields(_step)) {
      if (_picked.containsKey(f)) images[f] = _picked[f]!.path;
    }

    final res = await _api.updateDriverProfile(fields: fields, images: images);
    setState(() => _saving = false);

    if (res.statusCode == 200 && res.data['success'] == true) {
      _completion = res.data['profile_completion'] ?? _completion;
      _verificationStatus = res.data['verification_status'] ?? _verificationStatus;
      // Merge returned image URLs
      final data = Map<String, dynamic>.from(res.data['data'] ?? {});
      for (final e in data.entries) {
        if (e.value is String && (e.value as String).startsWith('http')) {
          _existing[e.key] = e.value as String;
          _picked.remove(e.key);
        }
      }
      if (advance && _step < _steps.length - 1) {
        setState(() => _step++);
      } else if (_step == _steps.length - 1) {
        _showDoneDialog();
      } else {
        setState(() {});
      }
    } else {
      Get.snackbar('Error', res.data?['message'] ?? 'Could not save. Try again.',
          backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  List<String> _stepTextFields(int step) {
    switch (step) {
      case 0: return ['father_name', 'mother_name', 'dob', 'blood_group', 'present_address', 'permanent_address', 'emergency_contact_name', 'emergency_contact_phone'];
      case 1: return ['nid'];
      case 2: return ['license_no', 'license_expiry'];
      case 3: return ['vehicle_type', 'vehicle_model', 'vehicle_plate', 'vehicle_color', 'vehicle_year'];
      default: return [];
    }
  }

  List<String> _stepImageFields(int step) {
    switch (step) {
      case 1: return ['nid_front_image', 'nid_back_image'];
      case 2: return ['license_image'];
      case 4: return ['profile_image'];
      default: return [];
    }
  }

  void _showDoneDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _completion >= 100 ? Colors.green.shade50 : Colors.orange.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _completion >= 100 ? Icons.verified : Icons.hourglass_top,
                color: _completion >= 100 ? Colors.green : Colors.orange,
                size: 44,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _completion >= 100 ? 'Submitted for Review' : 'Progress Saved',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _completion >= 100
                  ? 'Your profile is $_completion% complete and is now pending admin verification.'
                  : 'Your profile is $_completion% complete. Finish the remaining fields to get verified.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () { Navigator.pop(ctx); Get.back(); },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10713C)),
              child: const Text('Done', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Driver Verification'),
        backgroundColor: const Color(0xFF10713C),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10713C)))
          : Column(
              children: [
                _buildProgressHeader(),
                _buildStepIndicator(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: _buildStepBody(),
                  ),
                ),
                _buildBottomBar(),
              ],
            ),
    );
  }

  Widget _buildProgressHeader() {
    final color = _completion >= 100
        ? Colors.green
        : (_completion >= 50 ? Colors.orange : const Color(0xFFED1C24));
    final statusLabel = {
      'incomplete': 'Incomplete',
      'pending': 'Pending Review',
      'verified': 'Verified ✓',
      'rejected': 'Rejected',
    }[_verificationStatus] ?? 'Incomplete';

    return Container(
      color: const Color(0xFF10713C),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$_completion% complete',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(statusLabel,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _completion / 100,
              minHeight: 8,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          if (_verificationStatus == 'rejected' && _rejectionReason != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Rejected: $_rejectionReason',
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Row(
        children: List.generate(_steps.length, (i) {
          final active = i == _step;
          final done = i < _step;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _step = i),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: active || done ? const Color(0xFF10713C) : Colors.grey[300],
                    child: done
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : Text('${i + 1}',
                            style: TextStyle(
                                fontSize: 12,
                                color: active ? Colors.white : Colors.grey[600])),
                  ),
                  const SizedBox(height: 4),
                  Text(_steps[i],
                      style: TextStyle(
                          fontSize: 10,
                          color: active ? const Color(0xFF10713C) : Colors.grey[500],
                          fontWeight: active ? FontWeight.bold : FontWeight.normal)),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStepBody() {
    switch (_step) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Personal Information'),
            _field('father_name', "Father's Name", Icons.person_outline),
            _field('mother_name', "Mother's Name", Icons.person_outline),
            _dateField('dob', 'Date of Birth'),
            _dropdownField('blood_group', 'Blood Group', _bloodGroups),
            _field('present_address', 'Present Address', Icons.home_outlined, lines: 2),
            _field('permanent_address', 'Permanent Address', Icons.location_city_outlined, lines: 2),
            _field('emergency_contact_name', 'Emergency Contact Name', Icons.contact_phone_outlined),
            _field('emergency_contact_phone', 'Emergency Contact Phone', Icons.phone_outlined, keyboard: TextInputType.phone),
          ],
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('National ID (NID)'),
            _field('nid', 'NID Number', Icons.badge_outlined, keyboard: TextInputType.number),
            const SizedBox(height: 8),
            _imagePicker('nid_front_image', 'NID Front Photo'),
            _imagePicker('nid_back_image', 'NID Back Photo'),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Driving License'),
            _field('license_no', 'License Number', Icons.drive_eta_outlined),
            _dateField('license_expiry', 'License Expiry Date'),
            const SizedBox(height: 8),
            _imagePicker('license_image', 'License Photo'),
          ],
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Vehicle Information'),
            _dropdownField('vehicle_type', 'Vehicle Type', _vehicleTypes),
            _field('vehicle_model', 'Vehicle Model', Icons.directions_car_outlined),
            _field('vehicle_plate', 'Plate Number', Icons.confirmation_number_outlined),
            _field('vehicle_color', 'Color', Icons.color_lens_outlined),
            _field('vehicle_year', 'Year', Icons.calendar_today_outlined, keyboard: TextInputType.number),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Profile Photo'),
            Text('Upload a clear photo of your face. This is shown to passengers.',
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            const SizedBox(height: 16),
            Center(child: _avatarPicker('profile_image')),
          ],
        );
    }
  }

  Widget _buildBottomBar() {
    final isLast = _step == _steps.length - 1;
    return Container(
      padding: EdgeInsets.only(
          left: 16, right: 16, top: 12,
          bottom: MediaQuery.of(context).padding.bottom + 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))],
      ),
      child: Row(
        children: [
          if (_step > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: _saving ? null : () => setState(() => _step--),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Back'),
              ),
            ),
          if (_step > 0) const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _saving ? null : () => _saveStep(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10713C),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(isLast ? 'Submit for Review' : 'Save & Continue',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Field builders ──

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      );

  Widget _field(String key, String label, IconData icon,
      {TextInputType? keyboard, int lines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: _c[key],
        keyboardType: keyboard,
        maxLines: lines,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: const Color(0xFF10713C), size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF10713C), width: 2),
          ),
        ),
      ),
    );
  }

  Widget _dropdownField(String key, String label, List<String> options) {
    final current = _c[key]!.text.isNotEmpty && options.contains(_c[key]!.text)
        ? _c[key]!.text
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        value: current,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: options
            .map((o) => DropdownMenuItem(value: o, child: Text(o.toUpperCase())))
            .toList(),
        onChanged: (v) => setState(() => _c[key]!.text = v ?? ''),
      ),
    );
  }

  Widget _dateField(String key, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: _c[key],
        readOnly: true,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_today, color: Color(0xFF10713C), size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: DateTime(2000),
            firstDate: DateTime(1950),
            lastDate: DateTime(2100),
          );
          if (picked != null) {
            _c[key]!.text =
                '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
          }
        },
      ),
    );
  }

  Widget _imagePicker(String key, String label) {
    final hasPicked = _picked.containsKey(key);
    final hasExisting = _existing.containsKey(key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: () => _pickImage(key),
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: (hasPicked || hasExisting) ? const Color(0xFF10713C) : Colors.grey.shade300,
                width: (hasPicked || hasExisting) ? 2 : 1),
          ),
          child: hasPicked
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Image.file(File(_picked[key]!.path), width: double.infinity, fit: BoxFit.cover))
              : hasExisting
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: Image.network(_existing[key]!, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(Icons.image)),
                        ),
                        Positioned(
                          top: 6, right: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: Color(0xFF10713C), shape: BoxShape.circle),
                            child: const Icon(Icons.edit, size: 14, color: Colors.white),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_a_photo_outlined, color: Color(0xFF10713C), size: 32),
                        const SizedBox(height: 6),
                        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _avatarPicker(String key) {
    final hasPicked = _picked.containsKey(key);
    final hasExisting = _existing.containsKey(key);
    return GestureDetector(
      onTap: () => _pickImage(key),
      child: Stack(
        children: [
          CircleAvatar(
            radius: 64,
            backgroundColor: const Color(0xFF10713C).withValues(alpha: 0.1),
            backgroundImage: hasPicked
                ? FileImage(File(_picked[key]!.path)) as ImageProvider
                : (hasExisting ? NetworkImage(_existing[key]!) : null),
            child: (!hasPicked && !hasExisting)
                ? const Icon(Icons.person, size: 64, color: Color(0xFF10713C))
                : null,
          ),
          Positioned(
            bottom: 4, right: 4,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(color: Color(0xFF10713C), shape: BoxShape.circle),
              child: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
