#!/usr/bin/env python3
"""Edit main.dart to add Firebase init and new service registrations."""
import re

with open('lib/main.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add imports after 'services/api_service.dart'
old_import = "import 'services/api_service.dart';"
new_imports = """import 'services/api_service.dart';
import 'services/firebase_service.dart';
import 'services/location_service.dart';
import 'services/ride_service.dart';
import 'services/routing_service.dart';"""

if old_import in content:
    content = content.replace(old_import, new_imports, 1)
    print("✓ Imports added")
else:
    print("✗ Import line not found")

# 2. Replace the main() function
old_main = """void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();
  Get.put(ApiService());
  Get.put(LocaleController());
  runApp(const GoRideApp());
}"""

new_main = """void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();

  // Initialize core services
  Get.put(ApiService());
  Get.put(LocaleController());

  // Initialize Firebase for real-time features
  final firebaseService = Get.put(FirebaseService());
  try {
    await firebaseService.init();
    debugPrint('Firebase initialized in main()');
  } catch (e) {
    debugPrint('Firebase initialization skipped (offline/not configured): $e');
  }

  // Initialize location & ride services (depends on Firebase)
  final locationService = Get.put(LocationService());
  if (firebaseService.isInitialized) {
    locationService.initFirebase(firebaseService);
  }
  Get.put(RideService());
  Get.put(RoutingService());

  runApp(const GoRideApp());
}"""

if old_main in content:
    content = content.replace(old_main, new_main, 1)
    print("✓ main() function updated")
else:
    print("✗ main() function not found - checking for different format...")

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print("✓ File saved")
