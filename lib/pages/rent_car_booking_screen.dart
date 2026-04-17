import 'package:flutter/material.dart';

class RentCarBookingScreen extends StatefulWidget {
  const RentCarBookingScreen({super.key});

  @override
  State<RentCarBookingScreen> createState() => _RentCarBookingScreenState();
}

class _RentCarBookingScreenState extends State<RentCarBookingScreen> {
  bool _isWithReturn = false;
  DateTime _pickupDate = DateTime.now();
  TimeOfDay _pickupTime = TimeOfDay.now();
  DateTime _returnDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _returnTime = TimeOfDay.now();

  String? _selectedDistrict;
  String? _selectedThana;
  String? _pickupDistrict;
  String? _pickupThana;

  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _pickupLocationController =
      TextEditingController();
  final List<TextEditingController> _additionalStopsControllers = [];

  final List<String> _districts = [
    'All',
    'Dhaka',
    'Gazipur',
    'Narayanganj',
    'Munshiganj',
    'Manikganj',
    'Tangail',
    'Mymensingh',
    'Jamalput',
    'Netrokona',
    'Kishoreganj',
  ];

  final Map<String, List<String>> _districtThanas = {
    'All': ['All'],
    'Dhaka': [
      'Gulshan',
      'Banani',
      'Uttara',
      'Dhanmondi',
      'Mirpur',
      'Mohammadpur',
      'Lalbagh',
      'Hazaribagh',
      'Paltan',
      'Ramna',
      'Sabujbagh',
      'Badda',
      'Baridhara',
      'Bashundhara',
      'Cantonment',
    ],
    'Gazipur': [
      'Gazipur Sadar',
      'Kaliakair',
      'Kapasia',
      'Sreepur',
      'Tarakanda',
    ],
    'Narayanganj': [
      'Narayanganj Sadar',
      'Bandar',
      'Fatullah',
      'Siddhirganj',
      'Sonargaon',
    ],
    'Munshiganj': [
      'Munshiganj Sadar',
      'Gazaria',
      'Lohajong',
      'Serchip',
      'Tongibari',
    ],
    'Manikganj': [
      'Manikganj Sadar',
      'Daulatpur',
      'Ghior',
      'Harirampur',
      'Shibalaya',
    ],
    'Tangail': [
      'Tangail Sadar',
      'Basail',
      'Bhuapur',
      'Delduar',
      'Gopalpur',
      'Kalihati',
    ],
    'Mymensingh': [
      'Mymensingh Sadar',
      'Bhaluka',
      'Fulpur',
      'Gouripur',
      'Ishwarganj',
    ],
    'Jamalpur': [
      'Jamalpur Sadar',
      'Bokshiganj',
      'Dewanganj',
      'Madarganj',
      'Mithabginj',
    ],
    'Netrokona': [
      'Netrokona Sadar',
      'Atpara',
      'Barhatta',
      'Durgapur',
      'Khalajabganj',
    ],
    'Kishoreganj': [
      'Kishoreganj Sadar',
      'Bajitpur',
      'Hossainpur',
      'Itna',
      'Katiadi',
    ],
  };

  void _addStop() {
    setState(() {
      _additionalStopsControllers.add(TextEditingController());
    });
  }

  void _removeStop(int index) {
    setState(() {
      _additionalStopsControllers[index].dispose();
      _additionalStopsControllers.removeAt(index);
    });
  }

  void _showDatePicker({bool isReturn = false}) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isReturn ? _returnDate : _pickupDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF10713C),
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isReturn) {
          _returnDate = picked;
        } else {
          _pickupDate = picked;
        }
      });
    }
  }

  void _showTimePicker({bool isReturn = false}) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isReturn ? _returnTime : _pickupTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF10713C),
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isReturn) {
          _returnTime = picked;
        } else {
          _pickupTime = picked;
        }
      });
    }
  }

  void _showDistrictPicker({bool isPickup = false}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.35,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isPickup ? 'Select Pickup District' : 'Select District',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _districts.length,
                itemBuilder: (context, index) {
                  final isSelected = isPickup
                      ? (_pickupDistrict == _districts[index])
                      : (_selectedDistrict == _districts[index]);
                  return ListTile(
                    dense: true,
                    title: Text(_districts[index]),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: Color(0xFF10713C))
                        : null,
                    onTap: () {
                      setState(() {
                        if (isPickup) {
                          _pickupDistrict = _districts[index];
                          if (_pickupDistrict == 'All') {
                            _pickupThana = 'All';
                          } else {
                            _pickupThana =
                                _districtThanas[_pickupDistrict]?.first ??
                                'All';
                          }
                        } else {
                          _selectedDistrict = _districts[index];
                          if (_selectedDistrict == 'All') {
                            _selectedThana = 'All';
                          } else {
                            _selectedThana =
                                (_districtThanas[_selectedDistrict] ?? ['All'])
                                    .first;
                          }
                        }
                      });
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showThanaPicker({bool isPickup = false}) {
    final district = isPickup ? _pickupDistrict : _selectedDistrict;
    final List<String> thanas;
    if (district == null || district == 'All') {
      thanas = _districtThanas['All']!;
    } else {
      thanas = _districtThanas[district] ?? ['All'];
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.35,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                district != null && district != 'All'
                    ? 'Select Thana ($district)'
                    : 'Select Thana',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: thanas.length,
                  itemBuilder: (context, index) {
                    final isSelected = isPickup
                        ? (_pickupThana == thanas[index])
                        : (_selectedThana == thanas[index]);
                    return ListTile(
                      dense: true,
                      title: Text(thanas[index]),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: Color(0xFF10713C))
                          : null,
                      onTap: () {
                        setState(() {
                          if (isPickup) {
                            _pickupThana = thanas[index];
                          } else {
                            _selectedThana = thanas[index];
                          }
                        });
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rent Car'),
        backgroundColor: const Color(0xFF10713C),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Trip Type',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isWithReturn = false),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 44,
                            decoration: BoxDecoration(
                              color: !_isWithReturn
                                  ? const Color(0xFF10713C)
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: !_isWithReturn
                                    ? const Color(0xFF10713C)
                                    : Colors.grey.shade300,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.arrow_forward,
                                  color: !_isWithReturn
                                      ? Colors.white
                                      : Colors.grey[600],
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Without Return',
                                  style: TextStyle(
                                    color: !_isWithReturn
                                        ? Colors.white
                                        : Colors.grey[700],
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isWithReturn = true),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 44,
                            decoration: BoxDecoration(
                              color: _isWithReturn
                                  ? const Color(0xFF10713C)
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _isWithReturn
                                    ? const Color(0xFF10713C)
                                    : Colors.grey.shade300,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.replay,
                                  color: _isWithReturn
                                      ? Colors.white
                                      : Colors.grey[600],
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'With Return',
                                  style: TextStyle(
                                    color: _isWithReturn
                                        ? Colors.white
                                        : Colors.grey[700],
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isWithReturn
                        ? 'Pickup & Return Details'
                        : 'Pickup Date & Time',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Pickup:',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showDatePicker(isReturn: false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.calendar_today,
                                  size: 18,
                                  color: Color(0xFF10713C),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${_pickupDate.day}/${_pickupDate.month}/${_pickupDate.year}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showTimePicker(isReturn: false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.access_time,
                                  size: 18,
                                  color: Color(0xFF10713C),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _pickupTime.format(context),
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_isWithReturn) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Stay / Return:',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _showDatePicker(isReturn: true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.event_available,
                                    size: 18,
                                    color: Color(0xFFED1C24),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${_returnDate.day}/${_returnDate.month}/${_returnDate.year}',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _showTimePicker(isReturn: true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.access_time,
                                    size: 18,
                                    color: Color(0xFFED1C24),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _returnTime.format(context),
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pickup Location',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showDistrictPicker(isPickup: true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.map,
                                  size: 18,
                                  color: Color(0xFF10713C),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _pickupDistrict ?? 'District',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: _pickupDistrict != null
                                          ? Colors.black
                                          : Colors.grey[600],
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_drop_down,
                                  size: 20,
                                  color: Colors.grey[600],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showThanaPicker(isPickup: true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.location_city,
                                  size: 18,
                                  color: Color(0xFF10713C),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _pickupThana ?? 'Thana',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: _pickupThana != null
                                          ? Colors.black
                                          : Colors.grey[600],
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_drop_down,
                                  size: 20,
                                  color: Colors.grey[600],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _pickupLocationController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Enter full address',
                      filled: true,
                      fillColor: Colors.grey[100],
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(bottom: 50),
                        child: Icon(
                          Icons.home,
                          color: Color(0xFF10713C),
                          size: 18,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Destination Location',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showDistrictPicker(isPickup: false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.map,
                                  size: 18,
                                  color: Color(0xFF10713C),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _selectedDistrict ?? 'District',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: _selectedDistrict != null
                                          ? Colors.black
                                          : Colors.grey[600],
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_drop_down,
                                  size: 20,
                                  color: Colors.grey[600],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showThanaPicker(isPickup: false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.location_city,
                                  size: 18,
                                  color: Color(0xFF10713C),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _selectedThana ?? 'Thana',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: _selectedThana != null
                                          ? Colors.black
                                          : Colors.grey[600],
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_drop_down,
                                  size: 20,
                                  color: Colors.grey[600],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _addressController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Enter destination address',
                      filled: true,
                      fillColor: Colors.grey[100],
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(bottom: 50),
                        child: Icon(
                          Icons.flag,
                          color: Color(0xFF10713C),
                          size: 18,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),

                  if (_isWithReturn) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Multiple Stops / Where to go',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...List.generate(
                      _additionalStopsControllers.length,
                      (index) => Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _additionalStopsControllers[index],
                                decoration: InputDecoration(
                                  hintText: 'Stop ${index + 1}',
                                  filled: true,
                                  fillColor: Colors.grey[100],
                                  prefixIcon: const Icon(
                                    Icons.add_location,
                                    color: Color(0xFF10713C),
                                    size: 18,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.remove_circle,
                                color: Colors.red,
                              ),
                              onPressed: () => _removeStop(index),
                            ),
                          ],
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _addStop,
                      icon: const Icon(
                        Icons.add_circle_outline,
                        color: Color(0xFF10713C),
                      ),
                      label: const Text(
                        'Add Another Place',
                        style: TextStyle(color: Color(0xFF10713C)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10713C),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Search Cars',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _addressController.dispose();
    _pickupLocationController.dispose();
    for (var controller in _additionalStopsControllers) {
      controller.dispose();
    }
    super.dispose();
  }
}
