import 'package:flutter/material.dart';
import 'dhaka_map_screen.dart';

class LocationSelectionScreen extends StatefulWidget {
  final String? initialRideType;
  const LocationSelectionScreen({super.key, this.initialRideType});

  @override
  State<LocationSelectionScreen> createState() => _LocationSelectionScreenState();
}

class _LocationSelectionScreenState extends State<LocationSelectionScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _pickupController = TextEditingController(text: 'My Current Location');
  final TextEditingController _destinationController = TextEditingController();

  final List<Map<String, String>> _recentSearches = [
    {'title': 'Jamuna Future Park', 'address': 'Progoti Sarani, Dhaka'},
    {'title': 'Gulshan 2 Circle', 'address': 'Gulshan Ave, Dhaka'},
    {'title': 'Banani 11', 'address': 'Road 11, Banani, Dhaka'},
    {'title': 'Dhaka Airport', 'address': 'Terminal 1, Hazrat Shahjalal International'},
  ];

  final List<Map<String, dynamic>> _faqs = [
    {
      'question': 'How to pay for my ride?',
      'answer': 'You can pay using Cash, Credit/Debit cards, or our Pay Later service.'
    },
    {
      'question': 'Can I schedule a ride?',
      'answer': 'Yes, you can schedule a ride up to 7 days in advance from the booking menu.'
    },
    {
      'question': 'How to cancel a ride?',
      'answer': 'You can cancel your ride for free within 2 minutes of booking.'
    },
  ];

  final List<String> _dhakaAreas = [
    'Uttara, Dhaka',
    'Mirpur, Dhaka',
    'Gulshan, Dhaka',
    'Banani, Dhaka',
    'Dhanmondi, Dhaka',
    'Mohammadpur, Dhaka',
    'Badda, Dhaka',
    'Bashundhara R/A, Dhaka',
    'Baridhara, Dhaka',
    'Nikunja, Dhaka',
    'Khilgaon, Dhaka',
    'Malibagh, Dhaka',
    'Moghbazar, Dhaka',
    'Tejgaon, Dhaka',
    'Farmgate, Dhaka',
    'Kawran Bazar, Dhaka',
    'Shahbagh, Dhaka',
    'New Market, Dhaka',
    'Azimpur, Dhaka',
    'Lalbagh, Dhaka',
    'Puran Dhaka, Dhaka',
    'Jatrabari, Dhaka',
    'Demra, Dhaka',
    'Keraniganj, Dhaka',
    'Savar, Dhaka',
    'Gazipur, Dhaka',
    'Narayanganj, Dhaka',
    'Tongi, Dhaka',
    'Purbachal, Dhaka',
    'Ashulia, Dhaka',
  ];

  List<String> _filteredAreas = [];
  bool _showSuggestions = false;
  final FocusNode _pickupFocus = FocusNode();
  final FocusNode _destinationFocus = FocusNode();
  bool _isPickupFocused = false;

  void _onPickupChanged() {
    final text = _pickupController.text;
    if (text.isEmpty || text == 'My Current Location') {
      setState(() {
        _filteredAreas = [];
        _showSuggestions = false;
      });
    } else {
      setState(() {
        _filteredAreas = _dhakaAreas
            .where((area) => area.toLowerCase().contains(text.toLowerCase()))
            .toList();
        _showSuggestions = true;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _destinationController.addListener(_onDestinationChanged);
    _pickupController.addListener(_onPickupChanged);
    
    _pickupFocus.addListener(() {
      if (_pickupFocus.hasFocus) {
        setState(() => _isPickupFocused = true);
      }
    });
    _destinationFocus.addListener(() {
      if (_destinationFocus.hasFocus) {
        setState(() => _isPickupFocused = false);
      }
    });
  }

  void _onDestinationChanged() {
    final text = _destinationController.text;
    if (text.isEmpty) {
      setState(() {
        _filteredAreas = [];
        _showSuggestions = false;
      });
    } else {
      setState(() {
        _filteredAreas = _dhakaAreas
            .where((area) => area.toLowerCase().contains(text.toLowerCase()))
            .toList();
        _showSuggestions = true;
      });
    }
  }

  @override
  void dispose() {
    _destinationController.removeListener(_onDestinationChanged);
    _pickupController.removeListener(_onPickupChanged);
    _pickupFocus.dispose();
    _destinationFocus.dispose();
    _tabController.dispose();
    _pickupController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  void _navigateToMap() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => 
            DhakaMapScreen(
              initialRideType: widget.initialRideType,
              pickupAddress: _pickupController.text,
              destinationAddress: _destinationController.text,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeInOutQuart;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            _buildPopupHeader(),
            _buildSearchHeader(),
            const Divider(height: 1, thickness: 1),
            if (_showSuggestions && _filteredAreas.isNotEmpty)
              Expanded(
                child: _buildSuggestionsList(),
              )
            else ...[
              _buildTabs(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildRecentTab(),
                    _buildSavedTab(),
                  ],
                ),
              ),
            ],
            if (!_showSuggestions) _buildHelpSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildPopupHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Select ${widget.initialRideType ?? 'Ride'}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionsList() {
    return ListView.builder(
      itemCount: _filteredAreas.length,
      itemBuilder: (context, index) {
        final area = _filteredAreas[index];
        return ListTile(
          leading: const Icon(Icons.location_on, color: Colors.grey),
          title: Text(area),
          onTap: () {
            if (_isPickupFocused) {
              _pickupController.text = area;
              _destinationFocus.requestFocus();
            } else {
              _destinationController.text = area;
              setState(() => _showSuggestions = false);
              _navigateToMap();
            }
          },
        );
      },
    );
  }

  Widget _buildSearchHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Row(
        children: [
          Column(
            children: [
              const Icon(Icons.my_location, color: Color(0xFF10713C), size: 20),
              Container(width: 1, height: 30, color: Colors.grey[300]),
              const Icon(Icons.location_on, color: Color(0xFFED1C24), size: 20),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              children: [
                TextField(
                  controller: _pickupController,
                  focusNode: _pickupFocus,
                  decoration: InputDecoration(
                    hintText: 'Pickup Location',
                    filled: true,
                    fillColor: Colors.grey[100],
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _destinationController,
                  focusNode: _destinationFocus,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Where to?',
                    filled: true,
                    fillColor: Colors.grey[100],
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (val) {
                    if (val.isNotEmpty) {
                      _navigateToMap();
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return TabBar(
      controller: _tabController,
      labelColor: const Color(0xFF10713C),
      unselectedLabelColor: Colors.grey,
      indicatorColor: const Color(0xFF10713C),
      indicatorWeight: 3,
      tabs: const [
        Tab(text: 'RECENT'),
        Tab(text: 'SAVED'),
      ],
    );
  }

  Widget _buildRecentTab() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _recentSearches.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final item = _recentSearches[index];
        return ListTile(
          leading: const Icon(Icons.history, color: Colors.grey),
          title: Text(item['title']!, style: const TextStyle(fontWeight: FontWeight.w500)),
          subtitle: Text(item['address']!, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          onTap: () {
            _destinationController.text = item['title']!;
            _navigateToMap();
          },
        );
      },
    );
  }

  Widget _buildSavedTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSavedItem(Icons.home, 'Add Home', 'Set your home address'),
        _buildSavedItem(Icons.work, 'Add Work', 'Set your office address'),
        _buildSavedItem(Icons.add, 'Add New', 'Save a new location'),
        _buildSavedItem(Icons.location_searching, 'Add Missing Place', 'Help us find more locations'),
      ],
    );
  }

  Widget _buildSavedItem(IconData icon, String title, String subtitle) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF10713C).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: const Color(0xFF10713C), size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
      onTap: () {},
    );
  }

  Widget _buildHelpSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.help_outline, color: Color(0xFF10713C), size: 20),
              SizedBox(width: 8),
              Text(
                'Need Help?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._faqs.map((faq) => _buildFaqItem(faq['question']!, faq['answer']!)),
        ],
      ),
    );
  }

  Widget _buildFaqItem(String question, String answer) {
    return ExpansionTile(
      title: Text(question, style: const TextStyle(fontSize: 14, color: Colors.black87)),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        Text(answer, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
      ],
    );
  }
}
