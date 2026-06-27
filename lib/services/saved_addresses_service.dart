import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import '../services/api_service.dart';

class SavedAddress {
  final int? id;
  final String label;
  final String title;
  final String address;
  final double? lat;
  final double? lng;
  final String iconName;
  final bool isDefault;

  const SavedAddress({
    this.id,
    required this.label,
    required this.title,
    required this.address,
    this.lat,
    this.lng,
    this.iconName = 'home',
    this.isDefault = false,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'label': label,
        'title': title,
        'address': address,
        'latitude': lat,
        'longitude': lng,
        'icon_name': iconName,
        'is_default': isDefault,
      };

  factory SavedAddress.fromJson(Map<String, dynamic> json) => SavedAddress(
        id: json['id'] as int?,
        label: json['label'] as String? ?? 'custom',
        title: json['title'] as String? ?? '',
        address: json['address'] as String? ?? '',
        lat: json['latitude'] != null
            ? (json['latitude'] as num).toDouble()
            : null,
        lng: json['longitude'] != null
            ? (json['longitude'] as num).toDouble()
            : null,
        iconName: json['icon_name'] as String? ?? 'home',
        isDefault: json['is_default'] as bool? ?? false,
      );

  SavedAddress copyWith({
    int? id,
    String? label,
    String? title,
    String? address,
    double? lat,
    double? lng,
    String? iconName,
    bool? isDefault,
  }) =>
      SavedAddress(
        id: id ?? this.id,
        label: label ?? this.label,
        title: title ?? this.title,
        address: address ?? this.address,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        iconName: iconName ?? this.iconName,
        isDefault: isDefault ?? this.isDefault,
      );
}

class SavedAddressesService extends GetxService {
  static const String _cacheKey = 'saved_addresses_cache';
  final GetStorage _storage = GetStorage();
  final ApiService _apiService = Get.find<ApiService>();

  final RxList<SavedAddress> addresses = <SavedAddress>[].obs;
  final RxBool isLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    _loadFromCache();
    fetchAddresses();
  }

  void _loadFromCache() {
    final raw = _storage.read<List<dynamic>>(_cacheKey);
    if (raw != null && raw.isNotEmpty) {
      addresses.value = raw
          .cast<Map<String, dynamic>>()
          .map((e) => SavedAddress.fromJson(e))
          .toList();
    }
  }

  void _saveToCache() {
    _storage.write(_cacheKey, addresses.map((e) => e.toJson()).toList());
  }

  Future<void> fetchAddresses() async {
    if (!_apiService.isLoggedIn()) return;
    isLoading.value = true;
    try {
      final response = await _apiService.getSavedAddresses();
      if (response.statusCode == 200) {
        final data = response.data;
        List<dynamic> items = [];
        if (data is Map && data['data'] is List) {
          items = data['data'] as List;
        } else if (data is List) {
          items = data;
        }
        addresses.value =
            items.map((e) => SavedAddress.fromJson(e as Map<String, dynamic>)).toList();
        _saveToCache();
      }
    } catch (_) {
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> addAddress(SavedAddress address) async {
    try {
      final response = await _apiService.createSavedAddress(address.toJson());
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data;
        Map<String, dynamic>? item;
        if (data is Map && data['data'] is Map) {
          item = data['data'] as Map<String, dynamic>;
        } else if (data is Map<String, dynamic>) {
          item = data;
        }
        if (item != null) {
          addresses.add(SavedAddress.fromJson(item));
          _saveToCache();
        }
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateAddress(int id, SavedAddress address) async {
    try {
      final response = await _apiService.updateSavedAddress(id, address.toJson());
      if (response.statusCode == 200) {
        final data = response.data;
        Map<String, dynamic>? item;
        if (data is Map && data['data'] is Map) {
          item = data['data'] as Map<String, dynamic>;
        }
        if (item != null) {
          final updated = SavedAddress.fromJson(item);
          final idx = addresses.indexWhere((a) => a.id == id);
          if (idx != -1) {
            addresses[idx] = updated;
            _saveToCache();
          }
        }
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteAddress(int id) async {
    try {
      final response = await _apiService.deleteSavedAddress(id);
      if (response.statusCode == 200) {
        addresses.removeWhere((a) => a.id == id);
        _saveToCache();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void clearCache() {
    addresses.clear();
    _storage.remove(_cacheKey);
  }
}
