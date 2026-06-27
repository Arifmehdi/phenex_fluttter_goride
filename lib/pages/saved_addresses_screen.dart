import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/saved_addresses_service.dart';

class SavedAddressesScreen extends StatefulWidget {
  const SavedAddressesScreen({super.key});

  @override
  State<SavedAddressesScreen> createState() => _SavedAddressesScreenState();
}

class _SavedAddressesScreenState extends State<SavedAddressesScreen> {
  final SavedAddressesService _service = Get.find<SavedAddressesService>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Saved Addresses'),
        backgroundColor: const Color(0xFF10713C),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Obx(() {
        if (_service.isLoading.value && _service.addresses.isEmpty) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF10713C)));
        }
        if (_service.addresses.isEmpty) {
          return _buildEmptyState();
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _service.addresses.length,
          itemBuilder: (context, index) {
            final addr = _service.addresses[index];
            return _buildAddressCard(addr);
          },
        );
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditDialog(),
        backgroundColor: const Color(0xFF10713C),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF10713C).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.bookmark_border, size: 40, color: Color(0xFF10713C)),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Saved Addresses',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 8),
            Text(
              'Save your home, work, or frequently visited locations for quick booking.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[600], height: 1.4),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showAddEditDialog(),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Add Address', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10713C),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressCard(SavedAddress addr) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: addr.isDefault ? const Color(0xFF10713C) : Colors.grey[200]!,
          width: addr.isDefault ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF10713C).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_getIconForLabel(addr.iconName), color: const Color(0xFF10713C)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(addr.label.toUpperCase(),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF10713C), letterSpacing: 0.5)),
                    if (addr.isDefault) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10713C).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('DEFAULT',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF10713C))),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(addr.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 2),
                Text(addr.address, style: TextStyle(color: Colors.grey[600], fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Colors.grey[400], size: 20),
            onSelected: (value) {
              if (value == 'edit') _showAddEditDialog(address: addr);
              if (value == 'delete') _confirmDelete(addr);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit')])),
              const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))])),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDelete(SavedAddress addr) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Address'),
        content: Text('Are you sure you want to delete "${addr.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (addr.id != null) {
                await _service.deleteAddress(addr.id!);
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAddEditDialog({SavedAddress? address}) {
    final isEdit = address != null;
    final labelCtrl = TextEditingController(text: address?.label ?? 'home');
    final titleCtrl = TextEditingController(text: address?.title ?? '');
    final addressCtrl = TextEditingController(text: address?.address ?? '');
    String selectedIcon = address?.iconName ?? 'home';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
                ),
                const SizedBox(height: 20),
                Text(isEdit ? 'Edit Address' : 'Add New Address',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                const Text('Label', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: labelCtrl.text,
                  decoration: _inputDecoration('Select label'),
                  items: const [
                    DropdownMenuItem(value: 'home', child: Text('Home')),
                    DropdownMenuItem(value: 'work', child: Text('Work')),
                    DropdownMenuItem(value: 'gym', child: Text('Gym')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      labelCtrl.text = v;
                      setModalState(() {
                        selectedIcon = v;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                const Text('Title', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 8),
                TextField(
                  controller: titleCtrl,
                  decoration: _inputDecoration('e.g. My Home, Office Tower'),
                ),
                const SizedBox(height: 16),
                const Text('Address', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 8),
                TextField(
                  controller: addressCtrl,
                  maxLines: 3,
                  decoration: _inputDecoration('Enter full address'),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (titleCtrl.text.trim().isEmpty || addressCtrl.text.trim().isEmpty) {
                        Get.snackbar('Error', 'Please fill in all required fields.', snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red[50], colorText: Colors.red[800]);
                        return;
                      }
                      final newAddr = SavedAddress(
                        id: address?.id,
                        label: labelCtrl.text.trim(),
                        title: titleCtrl.text.trim(),
                        address: addressCtrl.text.trim(),
                        lat: address?.lat,
                        lng: address?.lng,
                        iconName: selectedIcon,
                        isDefault: address?.isDefault ?? false,
                      );
                      bool success;
                      if (isEdit && address?.id != null) {
                        success = await _service.updateAddress(address!.id!, newAddr);
                      } else {
                        success = await _service.addAddress(newAddr);
                      }
                      if (success && ctx.mounted) {
                        Navigator.pop(ctx);
                      } else {
                        Get.snackbar('Error', 'Failed to save address. Please try again.', snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red[50], colorText: Colors.red[800]);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10713C),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(isEdit ? 'Update Address' : 'Save Address', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF10713C), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  IconData _getIconForLabel(String iconName) {
    switch (iconName) {
      case 'work':
      case 'business':
        return Icons.work;
      case 'gym':
      case 'fitness_center':
        return Icons.fitness_center;
      case 'star':
        return Icons.star;
      case 'location_on':
        return Icons.location_on;
      case 'home':
      default:
        return Icons.home;
    }
  }
}
