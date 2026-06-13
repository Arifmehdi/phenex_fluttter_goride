import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:dio/dio.dart';
import '../services/api_service.dart';
import '../approval_helper.dart';
import 'home_page.dart';
import 'dashboard_page.dart';
import 'approval_pending_screen.dart';
import 'login_page.dart';

class RegisterScreen extends StatefulWidget {
  final String? selectedRole;
  const RegisterScreen({Key? key, this.selectedRole}) : super(key: key);

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _companyNameController = TextEditingController();
  final TextEditingController _vehicleTypeController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final ApiService _apiService = Get.find<ApiService>();
  String? _errorMessage;
  late String _selectedRole;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedRole = widget.selectedRole ?? 'solo';
  }

  Future<void> _register() async {
    setState(() {
      _errorMessage = null;
    });

    // Validate inputs
    if (_nameController.text.isEmpty) {
      setState(() => _errorMessage = 'Please enter your name');
      return;
    }

    if (_emailController.text.isEmpty) {
      setState(() => _errorMessage = 'Please enter your email');
      return;
    }

    if (_mobileController.text.isEmpty) {
      setState(() => _errorMessage = 'Please enter your mobile number');
      return;
    }

    if (_passwordController.text.isEmpty) {
      setState(() => _errorMessage = 'Please enter a password');
      return;
    }

    if (_passwordController.text.length < 8) {
      setState(() => _errorMessage = 'Password must be at least 8 characters');
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = 'Passwords do not match');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Build request data matching API expectations
    final data = <String, dynamic>{
      'name': _nameController.text,
      'email': _emailController.text,
      'mobile': _mobileController.text,
      'password': _passwordController.text,
      'password_confirmation': _confirmPasswordController.text,
      'role': _selectedRole,
    };

    if (_selectedRole == 'corporate') {
      data['company_name'] = _companyNameController.text;
    }

    if (_selectedRole == 'driver' || _selectedRole == 'owner') {
      data['vehicle_type'] = _vehicleTypeController.text;
    }

    try {
      final response = await _apiService.register(data);

      bool isSuccess = false;
      if (response.statusCode == 200 || response.statusCode == 201) {
        isSuccess = true;
      }

      if (isSuccess) {
        if (!mounted) return;

        final storedRole = GetStorage().read('role') as String?;
        final role = storedRole ?? _selectedRole;
        final isPending = isPendingApproval(response.data);

        if (role == 'admin' || role == 'driver' || role == 'corporate' || role == 'owner') {
          if (isPending) {
            Get.offAll(() => ApprovalPendingScreen(role: role));
          } else {
            Get.offAll(() => UnifiedDashboard(role: role));
          }
        } else {
          Get.offAll(() => const HomePage());
        }
      } else {
        setState(() {
          _errorMessage = response.data?['message'] ?? 'Registration failed. Please try again.';
        });
      }
    } on DioException catch (e) {
      String message = 'Connection error. Please try again.';
      if (e.response != null) {
        if (e.response!.data is Map) {
          message = e.response!.data?['message'] ??
              e.response!.data?['error'] ??
              'Registration failed';
        } else if (e.response!.statusCode == 422) {
          if (e.response!.data is Map && e.response!.data['errors'] != null) {
            final errors = e.response!.data['errors'] as Map;
            final firstError = errors.values.first;
            if (firstError is List && firstError.isNotEmpty) {
              message = firstError.first.toString();
            }
          } else {
            message = 'Validation failed. Please check your inputs.';
          }
        }
      }
      setState(() {
        _errorMessage = message;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'An error occurred. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCorporate = _selectedRole == 'corporate';
    final isDriverOrOwner = !isCorporate && _selectedRole != 'solo' && _selectedRole != 'user';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Back Button ──
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Color(0xFF10713C)),
                    onPressed: () => Get.back(),
                  ),
                ),

                // ── Header ──
                Image.asset(
                  'assets/go_ride_logo.png',
                  height: 64,
                  width: 64,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.directions_car_rounded, size: 48, color: Color(0xFF10713C)),
                ),
                const SizedBox(height: 12),
                const Text(
                  'GoRide',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF10713C),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Create your account',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
                const SizedBox(height: 32),

                // ── Role Selector (like login page) ──
                _buildRoleSelector(),
                const SizedBox(height: 24),

                // ── Name and Company fields ──
                if (isCorporate) ...[
                  _buildTextField(_companyNameController, 'Company Name', Icons.business),
                  const SizedBox(height: 16),
                  _buildTextField(_nameController, 'Contact Person', Icons.person),
                  const SizedBox(height: 16),
                ] else ...[
                  _buildTextField(_nameController, 'Full Name', Icons.person),
                  const SizedBox(height: 16),
                ],

                // ── Email field ──
                _buildTextField(_emailController, 'Email Address', Icons.email,
                    keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 16),

                // ── Mobile field ──
                _buildTextField(_mobileController, 'Mobile Number', Icons.phone,
                    keyboardType: TextInputType.phone),
                const SizedBox(height: 16),

                // ── Vehicle Type (for driver/owner) ──
                if (isDriverOrOwner) ...[
                  _buildTextField(_vehicleTypeController, 'Vehicle Type', Icons.directions_car),
                  const SizedBox(height: 16),
                ],

                // ── Password ──
                _buildPasswordField(_passwordController, 'Password', _obscurePassword,
                    (v) => setState(() => _obscurePassword = v)),
                const SizedBox(height: 16),

                // ── Confirm Password ──
                _buildPasswordField(_confirmPasswordController, 'Confirm Password',
                    _obscureConfirmPassword, (v) => setState(() => _obscureConfirmPassword = v)),

                const SizedBox(height: 20),

                // ── Error message (matching login page style) ──
                if (_errorMessage != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),

                // ── Register Button ──
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10713C),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF10713C).withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'Register Now',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Login Link ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Already have an account? ", style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                    GestureDetector(
                      onTap: () => Get.to(() => const LoginPage()),
                      child: const Text(
                        'Login',
                        style: TextStyle(
                          color: Color(0xFF10713C),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
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

  // Role selector matching login page style
  Widget _buildRoleSelector() {
    final List<Map<String, dynamic>> roles = [
      {'label': 'Passenger', 'value': 'user', 'icon': Icons.person_outline},
      {'label': 'Rider', 'value': 'driver', 'icon': Icons.directions_car_outlined},
      {'label': 'Corporate', 'value': 'corporate', 'icon': Icons.business_outlined},
    ];

    return Row(
      children: roles.map((role) {
        final bool isSelected = _selectedRole == role['value'];
        return Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedRole = role['value'] as String;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF10713C) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
              ),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                children: [
                  Icon(
                    role['icon'] as IconData,
                    size: 22,
                    color: isSelected ? Colors.white : const Color(0xFF6B7280),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    role['label'] as String,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : const Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF10713C), width: 1.5),
        ),
      ),
    );
  }

  Widget _buildPasswordField(
    TextEditingController controller,
    String label,
    bool obscure,
    Function(bool) onToggle,
  ) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline, size: 20),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 20,
          ),
          onPressed: () => onToggle(!obscure),
        ),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF10713C), width: 1.5),
        ),
      ),
    );
  }
}
