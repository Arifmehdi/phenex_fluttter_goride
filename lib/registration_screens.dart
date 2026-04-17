import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'locale_controller.dart';
import 'package:image_picker/image_picker.dart';

class OwnerProfileScreen extends StatefulWidget {
  final String selectedRole;
  const OwnerProfileScreen({Key? key, this.selectedRole = 'driver'}) : super(key: key);

  @override
  State<OwnerProfileScreen> createState() => _OwnerProfileScreenState();
}

class _OwnerProfileScreenState extends State<OwnerProfileScreen> {
  int _currentStep = 0;
  final TextEditingController _fatherNameController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _whatsappController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _nidController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _emergencyContactController = TextEditingController();

  final TextEditingController _licenseController = TextEditingController();
  final TextEditingController _licenseExpiryController = TextEditingController();
  final TextEditingController _experienceController = TextEditingController();

  final TextEditingController _carModelController = TextEditingController();
  final TextEditingController _carBrandController = TextEditingController();
  final TextEditingController _carCategoryController = TextEditingController();
  final TextEditingController _registrationController = TextEditingController();
  final TextEditingController _seatCapacityController = TextEditingController();
  final TextEditingController _carColorController = TextEditingController();
  final TextEditingController _carLocationController = TextEditingController();
  final TextEditingController _rateController = TextEditingController();
  String _fuelType = 'Petrol';
  bool _isAc = true;

  final Map<String, String?> _uploadedFiles = {};
  final Map<String, XFile?> _uploadedXFiles = {};
  final ImagePicker _imagePicker = ImagePicker();

  bool get _isDriver => widget.selectedRole == 'driver' || widget.selectedRole == 'both';
  bool get _isOwner => widget.selectedRole == 'corporate' || widget.selectedRole == 'both';

  Future<void> _selectDate(BuildContext context, TextEditingController controller) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        controller.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  void _showUploadOptions(String key, String label) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFF10713C), child: Icon(Icons.camera_alt, color: Colors.white)),
              title: const Text('Take Photo'),
              onTap: () async {
                Navigator.pop(context);
                final XFile? image = await _imagePicker.pickImage(source: ImageSource.camera, imageQuality: 80);
                if (image != null) {
                  setState(() {
                    _uploadedXFiles[key] = image;
                    _uploadedFiles[key] = 'captured';
                  });
                }
              },
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFF10713C), child: Icon(Icons.photo_library, color: Colors.white)),
              title: const Text('Choose from Gallery'),
              onTap: () async {
                Navigator.pop(context);
                final XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 80);
                if (image != null) {
                  setState(() {
                    _uploadedXFiles[key] = image;
                    _uploadedFiles[key] = 'gallery';
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _removeFile(String key) {
    setState(() {
      _uploadedFiles.remove(key);
      _uploadedXFiles.remove(key);
    });
  }

  void _saveAndContinue() {
    if (_currentStep < 2) {
      setState(() => _currentStep++);
    } else {
      _showSubmitDialog();
    }
  }

  void _skipToDashboard() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DriverDashboardScreen()),
    );
  }

  void _showSubmitDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Profile Saved'),
        content: const Text('Your profile has been saved. You can complete it later.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const DriverDashboardScreen()),
              );
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Profile'),
        backgroundColor: const Color(0xFF10713C),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: _skipToDashboard,
        ),
        actions: [
          TextButton(
            onPressed: _skipToDashboard,
            child: const Text('Skip', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: StepIndicator(number: 1, title: 'Personal', isActive: _currentStep >= 0, isCompleted: _currentStep > 0)),
                Expanded(child: StepIndicator(number: 2, title: _isDriver ? 'Driver' : 'Vehicle', isActive: _currentStep >= 1, isCompleted: _currentStep > 1)),
                Expanded(child: StepIndicator(number: 3, title: 'Documents', isActive: _currentStep >= 2, isCompleted: _currentStep > 2)),
              ],
            ),
            const SizedBox(height: 12),
            IndexedStack(
              index: _currentStep,
              children: [_buildPersonalStep(), _buildDriverCarStep(), _buildDocumentStep()],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (_currentStep > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _currentStep--),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                      child: const Text('Back'),
                    ),
                  ),
                if (_currentStep > 0) const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _saveAndContinue,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10713C), padding: const EdgeInsets.symmetric(vertical: 12)),
                    child: Text(_currentStep == 2 ? 'Submit' : 'Save & Continue', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonalStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Personal Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _buildTextField(_dobController, 'Date of Birth *', Icons.calendar_today, isDate: true),
        _buildTextField(_nidController, 'NID Number *', Icons.badge),
        _buildTextField(_addressController, 'Address *', Icons.location_on),
        _buildTextField(_emergencyContactController, 'Emergency Contact *', Icons.emergency),
        _buildTextField(_fatherNameController, 'Father Name (Optional)', Icons.family_restroom),
        _buildTextField(_whatsappController, 'WhatsApp Number (Optional)', Icons.chat),
        _buildTextField(_emailController, 'Email (Optional)', Icons.email),
      ],
    );
  }

  Widget _buildDriverCarStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isDriver) ...[
          const Text('Driver Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _buildTextField(_licenseController, 'License Number', Icons.drive_eta),
          _buildTextField(_licenseExpiryController, 'License Expiry Date', Icons.event, isDate: true),
          _buildTextField(_experienceController, 'Experience (Years)', Icons.timeline),
          const SizedBox(height: 12),
        ],
        if (_isOwner) ...[
          const Text('Vehicle Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _buildTextField(_carBrandController, 'Car Brand', Icons.business),
          _buildTextField(_carModelController, 'Car Model', Icons.directions_car),
          _buildTextField(_carCategoryController, 'Category', Icons.category),
          _buildTextField(_registrationController, 'Registration Number', Icons.numbers),
          _buildTextField(_seatCapacityController, 'Seat Capacity', Icons.airline_seat_recline_normal),
          _buildTextField(_carColorController, 'Color', Icons.palette),
          _buildTextField(_carLocationController, 'Location', Icons.location_city),
          _buildTextField(_rateController, 'Rate (৳/km)', Icons.attach_money),
          const SizedBox(height: 8),
          Row(children: [const Text('AC: '), Switch(value: _isAc, onChanged: (v) => setState(() => _isAc = v), activeColor: const Color(0xFF10713C))]),
          const Text('Fuel Type:', style: TextStyle(fontSize: 14)),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(label: const Text('Petrol'), selected: _fuelType == 'Petrol', selectedColor: const Color(0xFF10713C), onSelected: (s) => setState(() => _fuelType = 'Petrol')),
              ChoiceChip(label: const Text('Diesel'), selected: _fuelType == 'Diesel', selectedColor: const Color(0xFF10713C), onSelected: (s) => setState(() => _fuelType = 'Diesel')),
              ChoiceChip(label: const Text('CNG'), selected: _fuelType == 'CNG', selectedColor: const Color(0xFF10713C), onSelected: (s) => setState(() => _fuelType = 'CNG')),
              ChoiceChip(label: const Text('Electric'), selected: _fuelType == 'Electric', selectedColor: const Color(0xFF10713C), onSelected: (s) => setState(() => _fuelType = 'Electric')),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildDocumentStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Document Uploads', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        if (_isDriver) ...[
          _buildUploadButton('Driver Photo', Icons.person),
          _buildUploadButton('NID Upload', Icons.badge),
          _buildUploadButton('License Upload', Icons.credit_card),
        ],
        if (_isOwner) ...[
          _buildUploadButton('Car Photo - Front', Icons.directions_car),
          _buildUploadButton('Car Photo - Side', Icons.directions_car),
          _buildUploadButton('Car Photo - Rear', Icons.directions_car),
          _buildUploadButton('Car Photo - Interior', Icons.airline_seat_recline_normal),
          const SizedBox(height: 12),
          const Text('Vehicle Documents', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          _buildUploadButton('Registration Paper', Icons.description),
          _buildUploadButton('Tax Token', Icons.receipt),
          _buildUploadButton('Fitness Certificate', Icons.verified),
          _buildUploadButton('Insurance', Icons.security),
        ],
      ],
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool isDate = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TextField(
        controller: controller,
        readOnly: isDate,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          suffixIcon: isDate ? Icon(Icons.calendar_today, size: 18, color: const Color(0xFF10713C)) : null,
        ),
        onTap: isDate ? () => _selectDate(context, controller) : null,
      ),
    );
  }

  Widget _buildUploadButton(String label, IconData icon) {
    final key = label;
    final isUploaded = _uploadedFiles.containsKey(key);
    final uploadedFile = _uploadedXFiles[key];

    if (isUploaded && uploadedFile != null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF10713C), width: 2),
          borderRadius: BorderRadius.circular(10),
          color: const Color(0xFF10713C).withValues(alpha: 0.1),
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.check_circle, color: Color(0xFF10713C), size: 30),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    uploadedFile.name.length > 20 ? '${uploadedFile.name.substring(0, 20)}...' : uploadedFile.name,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF10713C)),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.red, size: 20),
              onPressed: () => _removeFile(key),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        onTap: () => _showUploadOptions(key, label),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: const Color(0xFF10713C)),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
              const Icon(Icons.add_photo_alternate, size: 20, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class StepIndicator extends StatelessWidget {
  final int number;
  final String title;
  final bool isActive;
  final bool isCompleted;
  const StepIndicator({super.key, required this.number, required this.title, required this.isActive, required this.isCompleted});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: isCompleted ? const Color(0xFF10713C) : (isActive ? const Color(0xFF10713C) : Colors.grey.shade300), shape: BoxShape.circle),
          child: Center(child: isCompleted ? const Icon(Icons.check, color: Colors.white, size: 18) : Text('$number', style: TextStyle(color: isActive ? Colors.white : Colors.grey.shade600, fontWeight: FontWeight.bold))),
        ),
        const SizedBox(height: 4),
        Text(title, style: TextStyle(fontSize: 12, color: isActive ? const Color(0xFF10713C) : Colors.grey)),
      ],
    );
  }
}

class DriverDashboardScreen extends StatefulWidget {
  final String userRole;
  const DriverDashboardScreen({super.key, this.userRole = 'driver'});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  final LocaleController localeController = Get.find<LocaleController>();
  bool _isOnline = false;
  
  // Simulation of profile completeness
  final double _progress = 0.4; // 40% after Phase 1

  @override
  Widget build(BuildContext context) {
    final isCorporate = widget.userRole == 'corporate';
    
    return Scaffold(
      appBar: AppBar(
        title: Text(isCorporate ? localeController.get('Corporate Dashboard', 'কর্পোরেট ড্যাশবোর্ড') : localeController.get('Driver Dashboard', 'ড্রাইভার ড্যাশবোর্ড')),
        backgroundColor: const Color(0xFF10713C),
        actions: [
          if (!isCorporate)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(_isOnline ? 'Online' : 'Offline', style: const TextStyle(fontSize: 12)),
                  Switch(
                    value: _isOnline,
                    onChanged: (v) => setState(() => _isOnline = v),
                    activeColor: Colors.white,
                    activeTrackColor: Colors.lightGreenAccent,
                  ),
                ],
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileSummary(isCorporate),
            const SizedBox(height: 20),
            _buildProgressSection(),
            const SizedBox(height: 24),
            _buildWalletCard(),
            const SizedBox(height: 24),
            _buildStatsGrid(),
            const SizedBox(height: 24),
            _buildRecentActivity(),
            const SizedBox(height: 24),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSummary(bool isCorporate) {
    return Row(
      children: [
        CircleAvatar(
          radius: 35,
          backgroundColor: const Color(0xFF10713C),
          child: Icon(isCorporate ? Icons.business : Icons.person, size: 35, color: Colors.white),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isCorporate ? 'TechCorp Ltd.' : 'Karim Ahmed',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              isCorporate ? localeController.get('Verified Account', 'ভেরিফাইড অ্যাকাউন্ট') : localeController.get('Level 1 Driver', 'লেভেল ১ ড্রাইভার'),
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
        const Spacer(),
        IconButton(icon: const Icon(Icons.settings_outlined, color: Colors.grey), onPressed: () {}),
      ],
    );
  }

  Widget _buildProgressSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10713C).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF10713C).withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(localeController.get('Profile Completion', 'প্রোফাইল সম্পন্ন'), style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('${(_progress * 100).toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10713C))),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 10,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10713C)),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OwnerProfileScreen(selectedRole: widget.userRole))),
            child: Row(
              children: [
                Text(
                  localeController.get('Complete Phase 2 & 3 now', 'ফেজ ২ এবং ৩ সম্পন্ন করুন'),
                  style: const TextStyle(fontSize: 13, color: Color(0xFF10713C), fontWeight: FontWeight.bold),
                ),
                const Icon(Icons.arrow_forward_ios, size: 12, color: Color(0xFF10713C)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF10713C), Color(0xFF0D5A30)]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: const Color(0xFF10713C).withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(localeController.get('Available Balance', 'বর্তমান ব্যালেন্স'), style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          const Text('৳ 1,250.00', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Row(
            children: [
              _buildWalletAction(Icons.account_balance_wallet, localeController.get('Withdraw', 'উত্তোলন')),
              const SizedBox(width: 20),
              _buildWalletAction(Icons.history, localeController.get('History', 'ইতিহাস')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWalletAction(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildStatsGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        _buildStatItem(localeController.get('Total Trips', 'মোট ট্রিপ'), '45', Icons.directions_car, Colors.blue),
        _buildStatItem(localeController.get('Rating', 'রেটিং'), '4.8', Icons.star, Colors.orange),
        _buildStatItem(localeController.get('Acceptance', 'গ্রহণযোগ্যতা'), '92%', Icons.check_circle, Colors.green),
        _buildStatItem(localeController.get('Cancelled', 'বাতিল'), '2', Icons.cancel, Colors.red),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 5)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildRecentActivity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(localeController.get('Pending Requests', 'অপেক্ষমান অনুরোধ'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: CircleAvatar(backgroundColor: Colors.orange.shade50, child: const Icon(Icons.local_offer, color: Colors.orange)),
            title: const Text('Trip to Dhaka Airport', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('15 km • ৳ 450 Base Fare'),
            trailing: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10713C)),
              child: const Text('Bid Now', style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        _buildMenuButton(Icons.directions_car, localeController.get('My Fleet', 'আমার বহর')),
        _buildMenuButton(Icons.description, localeController.get('Documents', 'নথি')),
        _buildMenuButton(Icons.support_agent, localeController.get('Support', 'সহায়তা')),
      ],
    );
  }

  Widget _buildMenuButton(IconData icon, String title) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF10713C)),
      title: Text(title),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
      onTap: () {},
    );
  }
}

class OtpSuccessScreen extends StatelessWidget {
  final String selectedRole;
  const OtpSuccessScreen({Key? key, this.selectedRole = 'driver'}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10713C),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(100)),
                child: const Icon(Icons.check_circle, size: 80, color: Colors.white),
              ),
              const SizedBox(height: 32),
              const Text('Verification Successful!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 12),
              const Text('Your account has been created successfully', style: TextStyle(fontSize: 16, color: Colors.white70), textAlign: TextAlign.center),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const DriverDashboardScreen())),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Text('Go to Dashboard', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF10713C))),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OwnerProfileScreen(selectedRole: selectedRole))),
                child: const Text('Complete Profile Later', style: TextStyle(fontSize: 14, color: Colors.white70)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
