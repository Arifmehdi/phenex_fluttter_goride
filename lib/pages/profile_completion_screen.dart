import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import '../services/api_service.dart';
import 'dashboard_page.dart';

class ProfileCompletionScreen extends StatefulWidget {
  final String role;
  const ProfileCompletionScreen({Key? key, required this.role}) : super(key: key);

  @override
  State<ProfileCompletionScreen> createState() => _ProfileCompletionScreenState();
}

class _ProfileCompletionScreenState extends State<ProfileCompletionScreen> {
  final ApiService _apiService = Get.find<ApiService>();
  bool _isLoading = true;
  bool _isSubmitting = false;
  int _completionPercentage = 0;
  List<Map<String, dynamic>> _missingFields = [];
  List<Map<String, dynamic>> _filledFields = [];
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _selectValues = {};
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _loadProfileCompletion();
  }

  Future<void> _loadProfileCompletion() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _apiService.getProfileCompletion();
      if (response.statusCode == 200 && response.data['success'] == true) {
        final completion = response.data['profile_completion'];
        setState(() {
          _completionPercentage = completion['percentage'] ?? 0;
          _missingFields = List<Map<String, dynamic>>.from(completion['missing_fields'] ?? []);
          _filledFields = List<Map<String, dynamic>>.from(completion['filled_fields'] ?? []);
          _isLoading = false;
        });

        // Initialize controllers for missing fields
        for (final field in _missingFields) {
          final key = field['key'] as String;
          if (!_controllers.containsKey(key)) {
            _controllers[key] = TextEditingController();
          }
          if (field['type'] == 'select' && field['options'] != null) {
            _selectValues[key] = (field['options'] as List).first as String;
          }
        }
      } else {
        setState(() {
          _errorMessage = 'Failed to load profile data';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection error. Please try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _submitProfile() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final Map<String, dynamic> data = {};
    for (final field in _missingFields) {
      final key = field['key'] as String;
      if (field['type'] == 'select') {
        if (_selectValues.containsKey(key)) {
          data[key] = _selectValues[key];
        }
      } else {
        if (_controllers.containsKey(key) && _controllers[key]!.text.isNotEmpty) {
          data[key] = _controllers[key]!.text;
        }
      }
    }

    if (data.isEmpty) {
      setState(() {
        _errorMessage = 'Please fill in at least one field';
        _isSubmitting = false;
      });
      return;
    }

    try {
      final response = await _apiService.completeProfile(data);
      if (response.statusCode == 200 && response.data['success'] == true) {
        final completion = response.data['profile_completion'];
        setState(() {
          _completionPercentage = completion['percentage'] ?? 0;
          _successMessage = response.data['message'] ?? 'Profile updated successfully!';
          _isSubmitting = false;
        });
        
        // Reload to refresh the missing fields list
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          _loadProfileCompletion();
        }
      } else {
        final msg = response.data?['message'] ?? 'Failed to update profile';
        // Handle validation errors
        if (response.data?['errors'] != null) {
          final errors = response.data['errors'] as Map;
          final firstError = errors.values.first;
          String errorMsg = msg;
          if (firstError is List && firstError.isNotEmpty) {
            errorMsg = firstError.first.toString();
          }
          setState(() => _errorMessage = errorMsg);
        } else {
          setState(() => _errorMessage = msg);
        }
        _isSubmitting = false;
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'An error occurred. Please try again.';
        _isSubmitting = false;
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Your Profile'),
        backgroundColor: const Color(0xFF10713C),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header with completion circle ──
                  _buildCompletionHeader(),
                  const SizedBox(height: 28),

                  // ── Error/Success Messages ──
                  if (_errorMessage != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_errorMessage!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13)),
                          ),
                        ],
                      ),
                    ),

                  if (_successMessage != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_successMessage!, style: const TextStyle(color: Color(0xFF16A34A), fontSize: 13)),
                          ),
                        ],
                      ),
                    ),

                  // ── Missing Fields Section ──
                  if (_missingFields.isEmpty)
                    _buildAllCompleteSection()
                  else ...[
                    Text(
                      'Complete your profile to get approved',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_missingFields.length} field${_missingFields.length > 1 ? 's' : ''} remaining',
                      style: const TextStyle(fontSize: 12, color: Color(0xFFED1C24), fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 20),

                    // ── Group fields by section ──
                    ..._buildSections(),
                  ],

                  const SizedBox(height: 20),

                  // ── Filled fields summary ──
                  if (_filledFields.isNotEmpty) ...[
                    const Text(
                      'Completed Information',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF10713C)),
                    ),
                    const SizedBox(height: 12),
                    ...(_filledFields.map((field) => _buildFilledFieldTile(field))),
                  ],

                  const SizedBox(height: 24),

                  // ── Submit Button ──
                  if (_missingFields.isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10713C),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFF10713C).withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: _isSubmitting
                            ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                            : const Text('Save & Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildCompletionHeader() {
    final color = _completionPercentage >= 70
        ? const Color(0xFF16A34A)
        : (_completionPercentage >= 40 ? const Color(0xFFF59E0B) : const Color(0xFFED1C24));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF10713C).withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF10713C).withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          // Circular progress indicator
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: _completionPercentage / 100,
                  strokeWidth: 6,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
                Center(
                  child: Text(
                    '$_completionPercentage%',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Profile Completion',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  _completionPercentage >= 100
                      ? 'All set! Your profile is complete.'
                      : 'Complete all fields to get approved',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          // Check icon if complete
          if (_completionPercentage >= 100)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 28),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildSections() {
    final sections = <String, List<Map<String, dynamic>>>{};
    for (final field in _missingFields) {
      final section = field['section'] as String? ?? 'other';
      sections.putIfAbsent(section, () => []);
      sections[section]!.add(field);
    }

    final sectionLabels = {
      'personal': {'icon': Icons.person_outline, 'label': 'Personal Information'},
      'driver': {'icon': Icons.drive_eta, 'label': 'Rider Information'},
      'company': {'icon': Icons.business, 'label': 'Company Information'},
      'documents': {'icon': Icons.description, 'label': 'Documents'},
    };

    final widgets = <Widget>[];
    for (final entry in sections.entries) {
      final sectionInfo = sectionLabels[entry.key] ?? {'icon': Icons.info, 'label': entry.key};
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(sectionInfo['icon'] as IconData, size: 20, color: const Color(0xFF10713C)),
                const SizedBox(width: 8),
                Text(
                  sectionInfo['label'] as String,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF10713C)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...entry.value.map((field) => _buildFieldWidget(field)),
          ],
        ),
      ));
    }
    return widgets;
  }

  Widget _buildFieldWidget(Map<String, dynamic> field) {
    final key = field['key'] as String;
    final label = field['label'] as String? ?? key;
    final type = field['type'] as String? ?? 'text';
    final placeholder = field['placeholder'] as String? ?? '';
    final options = field['options'] as List?;
    final required = field['required'] as bool? ?? true;

    if (type == 'select' && options != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          value: _selectValues.containsKey(key) ? _selectValues[key] : options.first.toString(),
          decoration: InputDecoration(
            labelText: '$label${required ? ' *' : ''}',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          items: options.map((opt) => DropdownMenuItem<String>(
            value: opt.toString(),
            child: Text(opt.toString()),
          )).toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() => _selectValues[key] = v);
            }
          },
        ),
      );
    }

    if (type == 'textarea') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: _controllers[key] ?? TextEditingController(),
          maxLines: 3,
          decoration: InputDecoration(
            labelText: '$label${required ? ' *' : ''}',
            hintText: placeholder,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      );
    }

    if (type == 'date') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: _controllers[key] ?? TextEditingController(),
          readOnly: true,
          decoration: InputDecoration(
            labelText: '$label${required ? ' *' : ''}',
            hintText: placeholder,
            suffixIcon: const Icon(Icons.calendar_today, size: 18, color: Color(0xFF10713C)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          onTap: () => _selectDate(context, key, label),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _controllers[key] ?? TextEditingController(),
        decoration: InputDecoration(
          labelText: '$label${required ? ' *' : ''}',
          hintText: placeholder,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context, String key, String label) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      final formatted = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      _controllers[key]?.text = formatted;
    }
  }

  Widget _buildFilledFieldTile(Map<String, dynamic> field) {
    final label = field['label'] as String? ?? field['key'];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 18),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          const Spacer(),
          if (field['value'] != null)
            Flexible(
              child: Text(
                field['value'].toString(),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAllCompleteSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 48),
          ),
          const SizedBox(height: 20),
          const Text(
            'Profile Complete!',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
          ),
          const SizedBox(height: 8),
          Text(
            'All required fields are filled. Your account is pending admin approval.',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10713C),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Go to Dashboard', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
