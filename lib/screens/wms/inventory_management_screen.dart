// lib/screens/wms/inventory_management_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_voice_picking/utils/currency.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';
import 'package:cross_file/cross_file.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'low_stock_screen.dart';
import 'out_of_stock_screen.dart';
import 'reports_analysis_screen.dart';
import 'total_items_screen.dart';
import '../../services/warehouse_service.dart';
import '../../utils/colors.dart';
import 'picklist_management_screen.dart';

class InventoryManagementScreen extends StatefulWidget {
  final String userName;

  const InventoryManagementScreen({
    super.key,
    required this.userName,
  });

  @override
  State<InventoryManagementScreen> createState() => _InventoryManagementScreenState();
}

class _InventoryManagementScreenState extends State<InventoryManagementScreen>
    with TickerProviderStateMixin {
  // 🏢 WAREHOUSE STATE VARIABLES
  String? _selectedWarehouseId;
  List<Map<String, dynamic>> _warehouses = [];
  bool _isLoadingWarehouses = false;
  String _currentWarehouseName = 'No Warehouse Selected';
  bool _showWarehouseError = false;

  // Core State Variables
  List<Map<String, dynamic>> _inventory = [];
  List<Map<String, dynamic>> _filteredInventory = [];
  bool _isLoading = true;
  bool _isExporting = false;
  String? _errorMessage;

  // Enhanced Error Handling Variables
  Timer? _processingTimer;
  Timer? _debounceTimer;
  bool _isProcessingScan = false;
  int _consecutiveErrors = 0;
  static const int _maxConsecutiveErrors = 3;
  static const int _maxDataLength = 10000;
  static const int _processingTimeout = 15;
  String? _lastProcessedData;

  // Search and Filter Controllers
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'All';
  Set<String> _categories = {'All'};

  // ❌ REMOVED: Picklist Controllers (No longer needed)
  // All _waveNumberController, _pickQuantityController, etc. REMOVED

  // Add/Edit Item Controllers
  final TextEditingController _addNameController = TextEditingController();
  final TextEditingController _addSkuController = TextEditingController();
  final TextEditingController _addBarcodeController = TextEditingController();
  final TextEditingController _addDescriptionController = TextEditingController();
  final TextEditingController _addQuantityController = TextEditingController();
  final TextEditingController _addMinStockController = TextEditingController();
  final TextEditingController _addUnitPriceController = TextEditingController();
  final TextEditingController _addLocationController = TextEditingController();
  String _addSelectedCategory = 'General';

  // Animation Controllers
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadWarehouses();
    _setupControllerListeners();
  }

  @override
  void dispose() {
    _processingTimer?.cancel();
    _debounceTimer?.cancel();
    _fadeController.dispose();
    _searchController.dispose();
    _addNameController.dispose();
    _addSkuController.dispose();
    _addBarcodeController.dispose();
    _addDescriptionController.dispose();
    _addQuantityController.dispose();
    _addMinStockController.dispose();
    _addUnitPriceController.dispose();
    _addLocationController.dispose();
    super.dispose();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _fadeController.forward();
  }

  // WAREHOUSE MANAGEMENT METHODS
  Future<void> _loadWarehouses() async {
    setState(() {
      _isLoadingWarehouses = true;
      _showWarehouseError = false;
    });

    try {
      final warehouses = await WarehouseService.getActiveWarehouses();
      if (mounted) {
        setState(() {
          _warehouses = warehouses;
          _isLoadingWarehouses = false;
          if (warehouses.isNotEmpty) {
            _selectedWarehouseId = warehouses[0]['warehouse_id'];
            _currentWarehouseName = warehouses[0]['name'];
            WarehouseService.setCurrentWarehouse(_selectedWarehouseId!);
          }
        });
        if (_selectedWarehouseId != null) {
          _loadInventory();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingWarehouses = false;
          _showWarehouseError = true;
          _currentWarehouseName = 'Error Loading Warehouses';
        });
      }
      _handleError('Failed to load warehouses', e, isRecoverable: true);
    }
  }

  void _switchWarehouse(String warehouseId, String warehouseName) {
    setState(() {
      _selectedWarehouseId = warehouseId;
      _currentWarehouseName = warehouseName;
      _inventory.clear();
      _filteredInventory.clear();
    });
    WarehouseService.setCurrentWarehouse(warehouseId);
    _showSuccessMessage('Switching to $warehouseName...');
    _loadInventory();
  }

  void _setupControllerListeners() {
    _searchController.addListener(() {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 500), () {
        _filterInventory();
      });
    });
  }

  bool _isValidInput(String input, {int maxLength = 255}) {
    if (input.trim().isEmpty) return false;
    if (input.length > maxLength) return false;
    return true;
  }

  void _handleError(String title, dynamic error, {bool isRecoverable = false}) {
    _consecutiveErrors++;
    String errorMessage = error.toString();
    if (errorMessage.length > 200) {
      errorMessage = '${errorMessage.substring(0, 200)}...';
    }

    debugPrint('❌ Error ($title): $errorMessage');
    setState(() => _isLoading = false);
    _showErrorMessage('$title: $errorMessage');

    if (isRecoverable) {
      if (_consecutiveErrors >= _maxConsecutiveErrors) {
        _showErrorRecoveryDialog();
      } else {
        Timer(const Duration(seconds: 3), () {
          if (mounted) {
            _resetProcessingState();
          }
        });
      }
    } else {
      _resetProcessingState();
    }
  }

  void _resetProcessingState() {
    _isProcessingScan = false;
    _processingTimer?.cancel();
    _lastProcessedData = null;
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _showErrorRecoveryDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('Multiple Errors Detected'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                children: [
                  Icon(Icons.warning, color: Colors.red, size: 48),
                  SizedBox(height: 12),
                  Text(
                    'Multiple operation errors detected. This may be due to:',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• Network connectivity issues\n'
                    '• Database problems\n'
                    '• Invalid data format',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _consecutiveErrors = 0;
              _resetProcessingState();
            },
            child: const Text('Reset'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _consecutiveErrors = 0;
              _loadInventory();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Restart'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadInventory() async {
    if (_selectedWarehouseId == null) {
      _showErrorMessage('Please select a warehouse first');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await WarehouseService.fetchInventory(
        limit: 1000,
        warehouseId: _selectedWarehouseId!,
      );

      final categorySet = {'All'};
      for (var item in data) {
        if (item['category'] != null) {
          categorySet.add(item['category']);
        }
      }

      if (mounted) {
        setState(() {
          _inventory = data;
          _filteredInventory = data;
          _categories = categorySet;
          _isLoading = false;
          _consecutiveErrors = 0;
        });
        _showSuccessMessage('Loaded ${data.length} items from $_currentWarehouseName');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
        _handleError('Failed to load inventory', e, isRecoverable: true);
      }
    }
  }

  void _filterInventory() {
    final searchTerm = _searchController.text.toLowerCase();
    setState(() {
      _filteredInventory = _inventory.where((item) {
        final matchesSearch = searchTerm.isEmpty ||
            (item['name']?.toString().toLowerCase().contains(searchTerm) ?? false) ||
            (item['sku']?.toString().toLowerCase().contains(searchTerm) ?? false) ||
            (item['barcode']?.toString().toLowerCase().contains(searchTerm) ?? false);

        final matchesCategory = _selectedCategory == 'All' ||
            item['category'] == _selectedCategory;

        return matchesSearch && matchesCategory;
      }).toList();
    });
  }

  void _navigateToTotalItemsScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TotalItemsScreen(
          userName: widget.userName,
          inventoryItems: _inventory,
        ),
      ),
    ).then((_) => _loadInventory());
  }

  void _showAddItemDialog() {
    if (_selectedWarehouseId == null) {
      _showErrorMessage('Please select a warehouse first');
      return;
    }

    _clearAddForm();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.add_box, color: Colors.green, size: 28),
            const SizedBox(width: 12),
            const Expanded(child: Text('Add New Item')),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTextField(_addNameController, 'Item Name *', Icons.inventory_2),
                const SizedBox(height: 16),
                _buildTextField(_addSkuController, 'SKU *', Icons.qr_code),
                const SizedBox(height: 16),
                _buildTextField(_addBarcodeController, 'Barcode *', Icons.qr_code_scanner),
                const SizedBox(height: 16),
                _buildTextField(_addDescriptionController, 'Description', Icons.description, maxLines: 2),
                const SizedBox(height: 16),
                _buildCategoryDropdown(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _buildNumberField(_addQuantityController, 'Quantity *', Icons.numbers)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildNumberField(_addMinStockController, 'Min Stock *', Icons.warning)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _buildPriceField(_addUnitPriceController, 'Unit Price *', Icons.currency_rupee)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildTextField(_addLocationController, 'Location', Icons.place)),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _handleAddItem,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Add Item'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAddItem() async {
    if (_isProcessingScan || _selectedWarehouseId == null) return;

    try {
      if (!_isValidInput(_addNameController.text) ||
          !_isValidInput(_addSkuController.text) ||
          !_isValidInput(_addBarcodeController.text) ||
          !_isValidInput(_addQuantityController.text) ||
          !_isValidInput(_addMinStockController.text) ||
          !_isValidInput(_addUnitPriceController.text)) {
        _showErrorMessage('Please fill in all required fields with valid data');
        return;
      }

      final quantity = int.tryParse(_addQuantityController.text.trim());
      final minStock = int.tryParse(_addMinStockController.text.trim());
      final unitPrice = double.tryParse(_addUnitPriceController.text.trim());

      if (quantity == null || quantity < 0) {
        _showErrorMessage('Please enter a valid quantity');
        return;
      }

      if (minStock == null || minStock < 0) {
        _showErrorMessage('Please enter a valid minimum stock');
        return;
      }

      if (unitPrice == null || unitPrice < 0) {
        _showErrorMessage('Please enter a valid unit price');
        return;
      }

      Navigator.pop(context);
      _isProcessingScan = true;
      setState(() => _isLoading = true);

      _processingTimer = Timer(Duration(seconds: _processingTimeout), () {
        if (_isProcessingScan) {
          _handleError('Add item timeout', 'Operation took too long', isRecoverable: true);
          _resetProcessingState();
        }
      });

      final itemData = {
        'name': _addNameController.text.trim(),
        'sku': _addSkuController.text.trim(),
        'barcode': _addBarcodeController.text.trim(),
        'description': _addDescriptionController.text.trim(),
        'category': _addSelectedCategory,
        'quantity': quantity,
        'min_stock': minStock,
        'unit_price': unitPrice,
        'location': _addLocationController.text.trim().isEmpty ? 'Storage' : _addLocationController.text.trim(),
        'created_by': widget.userName,
      };

      final success = await WarehouseService.insertInventory(itemData, warehouseId: _selectedWarehouseId);
      _processingTimer?.cancel();

      if (success) {
        _showSuccessMessage('Item added successfully to $_currentWarehouseName!');
        await _loadInventory();
        _consecutiveErrors = 0;
      } else {
        _handleError('Failed to add item', 'Database operation failed', isRecoverable: true);
      }
    } catch (e) {
      _processingTimer?.cancel();
      _handleError('Add item error', e, isRecoverable: true);
    } finally {
      _resetProcessingState();
    }
  }

  void _clearAddForm() {
    _addNameController.clear();
    _addSkuController.clear();
    _addBarcodeController.clear();
    _addDescriptionController.clear();
    _addQuantityController.text = '1';
    _addMinStockController.text = '10';
    _addUnitPriceController.text = '0.00';
    _addLocationController.text = 'Storage';
    _addSelectedCategory = 'General';
  }

  // ❌ REMOVED: _showAddToPicklistDialog() - ENTIRE FUNCTION DELETED
  // ❌ REMOVED: _handleAddToPicklist() - ENTIRE FUNCTION DELETED

  Widget _buildInventoryCard(Map<String, dynamic> item) {
    final name = item['name'] ?? "Unnamed";
    final sku = item['sku'] ?? "N/A";
    final quantity = (item['quantity'] ?? 0) as int;
    final minStock = (item['min_stock'] ?? 10) as int;
    final category = item['category'] ?? "General";
    final barcode = item['barcode'] ?? "N/A";
    final unitPrice = (item['unit_price'] ?? 0.0).toDouble();
    final totalValue = quantity * unitPrice;
    final description = item['description'] ?? "";
    final location = item['location'] ?? "Storage";

    Color statusColor = Colors.green;
    String status = 'In Stock';
    IconData statusIcon = Icons.check_circle;

    if (quantity == 0) {
      statusColor = Colors.red;
      status = 'Out of Stock';
      statusIcon = Icons.error;
    } else if (quantity <= minStock) {
      statusColor = Colors.orange;
      status = 'Low Stock';
      statusIcon = Icons.warning;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: statusColor.withOpacity(0.3),
              width: 2,
            ),
          ),
          child: ExpansionTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                statusIcon,
                color: statusColor,
                size: 24,
              ),
            ),
            title: Text(
              name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "SKU: $sku • Qty: $quantity",
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        category,
                        style: const TextStyle(
                          color: Colors.blue,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) => _handleItemAction(value, item),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit_quantity',
                  child: Row(
                    children: [
                      Icon(Icons.edit, color: Colors.blue, size: 18),
                      SizedBox(width: 8),
                      Text('Edit Quantity'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'update_item',
                  child: Row(
                    children: [
                      Icon(Icons.update, color: Colors.green, size: 18),
                      SizedBox(width: 8),
                      Text('Update Item'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.red, size: 18),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDetailRow('Warehouse', _currentWarehouseName),
                    const SizedBox(height: 4),
                    const Divider(),
                    if (description.isNotEmpty) _buildDetailRow('Description', description),
                    _buildDetailRow('SKU', sku),
                    _buildDetailRow('Barcode', barcode),
                    _buildDetailRow('Location', location),
                    _buildDetailRow('Category', category),
                    _buildDetailRow('Current Quantity', quantity.toString()),
                    _buildDetailRow('Minimum Stock', minStock.toString()),
                    _buildDetailRow('Unit Price', CurrencyHelper.display(unitPrice)),
                    _buildDetailRow('Total Value', CurrencyHelper.display(totalValue)),
                    const SizedBox(height: 8),
                    const Divider(),
                    _buildDetailRow('Created By', item['created_by']?.toString() ?? 'System'),
                    _buildDetailRow('Last Updated', _formatDate(item['updated_at']?.toString() ?? '')),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: item['is_active'] == true ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: item['is_active'] == true ? Colors.green : Colors.red,
                            ),
                          ),
                          child: Text(
                            item['is_active'] == true ? 'ACTIVE' : 'INACTIVE',
                            style: TextStyle(
                              color: item['is_active'] == true ? Colors.green : Colors.red,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // ❌ REMOVED: Voice Pick Button - Only Edit Qty button remains
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isProcessingScan ? null : () => _showEditQuantityDialog(item),
                            icon: const Icon(Icons.edit, size: 18),
                            label: const Text('Edit Qty'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _copyToClipboard(barcode),
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy Barcode'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: AppColors.textLight,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    if (dateStr.isEmpty) return "—";
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateStr.length > 19 ? dateStr.substring(0, 19) : dateStr;
    }
  }

  void _copyToClipboard(String text) {
    try {
      Clipboard.setData(ClipboardData(text: text));
      _showSuccessMessage('Barcode copied to clipboard');
    } catch (e) {
      _showErrorMessage('Failed to copy barcode');
    }
  }

  void _handleItemAction(String action, Map<String, dynamic> item) {
    if (_isProcessingScan) return;
    try {
      switch (action) {
        case 'edit_quantity':
          _showEditQuantityDialog(item);
          break;
        case 'update_item':
          _showUpdateItemDialog(item);
          break;
        case 'delete':
          _showDeleteConfirmation(item);
          break;
      }
    } catch (e) {
      _handleError('Error handling action', e, isRecoverable: true);
    }
  }

  void _showEditQuantityDialog(Map<String, dynamic> item) {
    final quantityController = TextEditingController(
      text: (item['quantity'] ?? 0).toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.edit, color: Colors.blue, size: 28),
            const SizedBox(width: 12),
            const Expanded(child: Text('Edit Quantity')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Item: ${item['name'] ?? 'Unknown'}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: quantityController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'New Quantity',
                prefixIcon: const Icon(Icons.numbers),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                helperText: 'Current: ${item['quantity'] ?? 0}',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _isProcessingScan ? null : () => _handleUpdateQuantity(item, quantityController.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: _isProcessingScan
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleUpdateQuantity(Map<String, dynamic> item, String quantityText) async {
    if (_isProcessingScan) return;

    try {
      if (!_isValidInput(quantityText)) {
        _showErrorMessage('Please enter a valid quantity');
        return;
      }

      final newQuantity = int.tryParse(quantityText);
      if (newQuantity == null || newQuantity < 0) {
        _showErrorMessage('Please enter a valid quantity (0 or greater)');
        return;
      }

      _isProcessingScan = true;
      setState(() => _isLoading = true);

      _processingTimer = Timer(Duration(seconds: _processingTimeout), () {
        if (_isProcessingScan) {
          _handleError('Update quantity timeout', 'Operation took too long', isRecoverable: true);
          _resetProcessingState();
        }
      });

      final success = await WarehouseService.updateInventory(
        item['id'],
        {'quantity': newQuantity},
      );

      _processingTimer?.cancel();

      if (success) {
        Navigator.of(context).pop();
        _showSuccessMessage('Quantity updated successfully');
        await _loadInventory();
        _consecutiveErrors = 0;
      } else {
        _handleError('Failed to update quantity', 'Database operation failed', isRecoverable: true);
      }
    } catch (e) {
      _processingTimer?.cancel();
      _handleError('Update quantity error', e, isRecoverable: true);
    } finally {
      _resetProcessingState();
    }
  }

  void _showUpdateItemDialog(Map<String, dynamic> item) {
    _addNameController.text = item['name'] ?? '';
    _addSkuController.text = item['sku'] ?? '';
    _addBarcodeController.text = item['barcode'] ?? '';
    _addDescriptionController.text = item['description'] ?? '';
    _addQuantityController.text = (item['quantity'] ?? 0).toString();
    _addMinStockController.text = (item['min_stock'] ?? 10).toString();
    _addUnitPriceController.text = (item['unit_price'] ?? 0.0).toString();
    _addLocationController.text = item['location'] ?? 'Storage';
    _addSelectedCategory = item['category'] ?? 'General';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.edit, color: Colors.blue, size: 28),
            const SizedBox(width: 12),
            const Expanded(child: Text('Update Item')),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTextField(_addNameController, 'Item Name *', Icons.inventory_2),
                const SizedBox(height: 16),
                _buildTextField(_addSkuController, 'SKU *', Icons.qr_code, enabled: false),
                const SizedBox(height: 16),
                _buildTextField(_addBarcodeController, 'Barcode *', Icons.qr_code_scanner),
                const SizedBox(height: 16),
                _buildTextField(_addDescriptionController, 'Description', Icons.description, maxLines: 2),
                const SizedBox(height: 16),
                _buildCategoryDropdown(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _buildNumberField(_addQuantityController, 'Quantity *', Icons.numbers)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildNumberField(_addMinStockController, 'Min Stock *', Icons.warning)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _buildPriceField(_addUnitPriceController, 'Unit Price *', Icons.currency_rupee)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildTextField(_addLocationController, 'Location', Icons.place)),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _isProcessingScan ? null : () => _handleUpdateItem(item['id']),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: _isProcessingScan
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleUpdateItem(String itemId) async {
    if (_isProcessingScan) return;

    try {
      if (!_isValidInput(_addNameController.text) ||
          !_isValidInput(_addBarcodeController.text) ||
          !_isValidInput(_addQuantityController.text) ||
          !_isValidInput(_addMinStockController.text) ||
          !_isValidInput(_addUnitPriceController.text)) {
        _showErrorMessage('Please fill in all required fields with valid data');
        return;
      }

      final quantity = int.tryParse(_addQuantityController.text.trim());
      final minStock = int.tryParse(_addMinStockController.text.trim());
      final unitPrice = double.tryParse(_addUnitPriceController.text.trim());

      if (quantity == null || quantity < 0) {
        _showErrorMessage('Please enter a valid quantity');
        return;
      }

      if (minStock == null || minStock < 0) {
        _showErrorMessage('Please enter a valid minimum stock');
        return;
      }

      if (unitPrice == null || unitPrice < 0) {
        _showErrorMessage('Please enter a valid unit price');
        return;
      }

      Navigator.pop(context);
      _isProcessingScan = true;
      setState(() => _isLoading = true);

      _processingTimer = Timer(Duration(seconds: _processingTimeout), () {
        if (_isProcessingScan) {
          _handleError('Update item timeout', 'Operation took too long', isRecoverable: true);
          _resetProcessingState();
        }
      });

      final updates = {
        'name': _addNameController.text.trim(),
        'barcode': _addBarcodeController.text.trim(),
        'description': _addDescriptionController.text.trim(),
        'category': _addSelectedCategory,
        'quantity': quantity,
        'min_stock': minStock,
        'unit_price': unitPrice,
        'location': _addLocationController.text.trim(),
      };

      final success = await WarehouseService.updateInventory(itemId, updates);
      _processingTimer?.cancel();

      if (success) {
        _showSuccessMessage('Item updated successfully!');
        await _loadInventory();
        _consecutiveErrors = 0;
      } else {
        _handleError('Failed to update item', 'Database operation failed', isRecoverable: true);
      }
    } catch (e) {
      _processingTimer?.cancel();
      _handleError('Update item error', e, isRecoverable: true);
    } finally {
      _resetProcessingState();
    }
  }

  void _showDeleteConfirmation(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red, size: 28),
            const SizedBox(width: 12),
            const Expanded(child: Text('Delete Item')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Icon(Icons.delete_forever, color: Colors.red, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Are you sure you want to delete "${item['name'] ?? 'this item'}"?',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This action cannot be undone.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _isProcessingScan ? null : () => _handleDeleteItem(item['id']),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: _isProcessingScan
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDeleteItem(String itemId) async {
    if (_isProcessingScan) return;

    try {
      _isProcessingScan = true;
      setState(() => _isLoading = true);

      _processingTimer = Timer(Duration(seconds: _processingTimeout), () {
        if (_isProcessingScan) {
          _handleError('Delete item timeout', 'Operation took too long', isRecoverable: true);
          _resetProcessingState();
        }
      });

      final success = await WarehouseService.deleteInventory(itemId);
      _processingTimer?.cancel();

      if (success) {
        Navigator.of(context).pop();
        _showSuccessMessage('Item deleted successfully');
        await _loadInventory();
        _consecutiveErrors = 0;
      } else {
        _handleError('Failed to delete item', 'Database operation failed', isRecoverable: true);
      }
    } catch (e) {
      _processingTimer?.cancel();
      _handleError('Delete item error', e, isRecoverable: true);
    } finally {
      _resetProcessingState();
    }
  }

  Future<void> _exportInventoryReport() async {
    if (_isExporting || _isProcessingScan) return;
    setState(() => _isExporting = true);

    try {
      _processingTimer = Timer(Duration(seconds: _processingTimeout * 2), () {
        if (_isExporting) {
          _handleError('Export timeout', 'Export operation took too long', isRecoverable: true);
          setState(() => _isExporting = false);
        }
      });

      final reportData = await WarehouseService.generateInventoryReport();

      if (reportData['error'] != null) {
        _processingTimer?.cancel();
        _showErrorMessage('Export failed: ${reportData['error']}');
        return;
      }

      List<List<dynamic>> csvData = [];

      csvData.addAll([
        ['COMPREHENSIVE INVENTORY REPORT'],
        ['Warehouse:', _currentWarehouseName],
        ['Generated on:', DateTime.now().toString()],
        ['Generated by:', widget.userName],
        ['Total Items:', reportData['total_items'].toString()],
        ['Low Stock Items:', reportData['low_stock_items'].toString()],
        ['Out of Stock Items:', reportData['out_of_stock_items'].toString()],
        ['Total Inventory Value:', CurrencyHelper.display(reportData['total_inventory_value'])],
        [],
      ]);

      csvData.add(['CATEGORY BREAKDOWN:']);
      final categoryBreakdown = reportData['category_breakdown'] as Map;
      categoryBreakdown.forEach((category, count) {
        csvData.add([category, count.toString()]);
      });
      csvData.add([]);

      csvData.add([
        'Warehouse', 'Item Name', 'SKU', 'Barcode', 'Description', 'Category',
        'Current Quantity', 'Minimum Stock', 'Unit Price', 'Total Value',
        'Stock Status', 'Location', 'Last Updated'
      ]);

      final inventoryData = reportData['inventory_data'] as List<Map<String, dynamic>>;
      for (var item in inventoryData) {
        final quantity = item['quantity'] ?? 0;
        final minStock = item['min_stock'] ?? 10;
        final unitPrice = (item['unit_price'] ?? 0.0).toDouble();
        final totalValue = quantity * unitPrice;

        String stockStatus = 'In Stock';
        if (quantity == 0) {
          stockStatus = 'Out of Stock';
        } else if (quantity <= minStock) {
          stockStatus = 'Low Stock';
        }

        csvData.add([
          _currentWarehouseName,
          item['name'] ?? '',
          item['sku'] ?? '',
          item['barcode'] ?? '',
          item['description'] ?? '',
          item['category'] ?? 'General',
          quantity.toString(),
          minStock.toString(),
          unitPrice.toStringAsFixed(2),
          totalValue.toStringAsFixed(2),
          stockStatus,
          item['location'] ?? 'Storage',
          item['updated_at']?.toString().substring(0, 16) ?? '',
        ]);
      }

      String csvString = const ListToCsvConverter().convert(csvData);
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toString().replaceAll(':', '-').substring(0, 19);
      final warehouseName = _currentWarehouseName.replaceAll(' ', '_').toLowerCase();
      final file = File('${directory.path}/${warehouseName}_inventory_report_$timestamp.csv');
      await file.writeAsString(csvString);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Inventory Report - $_currentWarehouseName: ${inventoryData.length} items, Total Value: ${CurrencyHelper.display(reportData['total_inventory_value'])}',
      );

      _processingTimer?.cancel();
      _showSuccessMessage('Inventory report exported successfully for $_currentWarehouseName!');
      _consecutiveErrors = 0;
    } catch (e) {
      _processingTimer?.cancel();
      _handleError('Export failed', e, isRecoverable: false);
    } finally {
      setState(() => _isExporting = false);
    }
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon,
      {int? maxLines, bool enabled = true, String? hint, int? maxLength}) {
    return TextField(
      controller: controller,
      maxLines: maxLines ?? 1,
      maxLength: maxLength,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        counterText: maxLength != null ? '' : null,
      ),
    );
  }

  Widget _buildNumberField(TextEditingController controller, String label, IconData icon, {String? hint}) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildPriceField(TextEditingController controller, String label, IconData icon) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildCategoryDropdown() {
    return DropdownButtonFormField<String>(
      value: _addSelectedCategory,
      decoration: InputDecoration(
        labelText: 'Category',
        prefixIcon: const Icon(Icons.category),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      items: ['General', 'Electronics', 'Clothing', 'Food', 'Books', 'Tools', 'Other']
          .map((category) => DropdownMenuItem(
                value: category,
                child: Text(category),
              ))
          .toList(),
      onChanged: (value) => setState(() => _addSelectedCategory = value ?? 'General'),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, {VoidCallback? onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Card(
          child: Container(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int _getLowStockCount() {
    return _filteredInventory.where((item) {
      final qty = item['quantity'] ?? 0;
      final minStock = item['min_stock'] ?? 10;
      return qty > 0 && qty <= minStock;
    }).length;
  }

  int _getOutOfStockCount() {
    return _filteredInventory.where((item) => (item['quantity'] ?? 0) == 0).length;
  }

  void _showSuccessMessage(String message) {
    if (mounted) {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  void _showErrorMessage(String message) {
    if (mounted) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(fontSize: 14)),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: Colors.white70,
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("📦 Enhanced Inventory Management", style: TextStyle(fontSize: 18)),
            if (!_isLoadingWarehouses)
              Text(
                _currentWarehouseName,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w300),
              )
            else
              const Text(
                'Loading warehouses...',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w300),
              ),
          ],
        ),
        backgroundColor: Colors.blue.withOpacity(0.9),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadInventory,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Inventory',
          ),
          IconButton(
            onPressed: _isExporting || _isLoading ? null : _exportInventoryReport,
            icon: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.file_download),
            tooltip: 'Export Comprehensive Report',
          ),
          if (!_isLoadingWarehouses && _warehouses.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: PopupMenuButton<String>(
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warehouse, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '${_warehouses.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                tooltip: 'Switch Warehouse',
                offset: const Offset(-100, 45),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (String warehouseId) {
                  final selectedWarehouse = _warehouses.firstWhere(
                    (w) => w['warehouse_id'] == warehouseId,
                  );
                  _switchWarehouse(warehouseId, selectedWarehouse['name']);
                },
                itemBuilder: (BuildContext context) {
                  return _warehouses.map((warehouse) {
                    final isSelected = warehouse['warehouse_id'] == _selectedWarehouseId;
                    return PopupMenuItem<String>(
                      value: warehouse['warehouse_id'],
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.blue.withOpacity(0.1) : null,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.blue.withOpacity(0.2)
                                    : Colors.grey.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                isSelected ? Icons.check_circle : Icons.warehouse,
                                color: isSelected ? Colors.blue : Colors.grey[600],
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    warehouse['name'],
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      color: isSelected ? Colors.blue : Colors.black87,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (warehouse['address'] != null)
                                    Text(
                                      warehouse['address'],
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey[600],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'ACTIVE',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList();
                },
              ),
            )
          else if (_isLoadingWarehouses)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
        ],
      ),
     
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.withOpacity(0.1),
              Colors.white,
            ],
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              if (_showWarehouseError)
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Failed to load warehouses. Please check connection.',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _loadWarehouses,
                        child: const Text('Retry', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                ),
              if (_selectedWarehouseId == null && !_isLoadingWarehouses && !_showWarehouseError)
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.warehouse, size: 48, color: Colors.orange),
                      const SizedBox(height: 12),
                      const Text(
                        'No Warehouse Selected',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Please select a warehouse to view inventory',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.orange),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _loadWarehouses,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Load Warehouses'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_selectedWarehouseId != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search by name, SKU, or barcode...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    _filterInventory();
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selectedCategory,
                              decoration: InputDecoration(
                                labelText: 'Category Filter',
                                prefixIcon: const Icon(Icons.category),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              items: _categories.map((category) {
                                return DropdownMenuItem(
                                  value: category,
                                  child: Text(category),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedCategory = value ?? 'All';
                                });
                                _filterInventory();
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (_selectedWarehouseId != null)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _buildStatCard(
                        'Total Items',
                        _filteredInventory.length.toString(),
                        Icons.inventory_2,
                        Colors.blue,
                        onTap: _navigateToTotalItemsScreen,
                      ),
                      const SizedBox(width: 12),
                      _buildStatCard(
                        'Low Stock',
                        _getLowStockCount().toString(),
                        Icons.warning,
                        Colors.orange,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => LowStockScreen(userName: widget.userName),
                            ),
                          ).then((_) => _loadInventory());
                        },
                      ),
                      const SizedBox(width: 12),
                      _buildStatCard(
                        'Out of Stock',
                        _getOutOfStockCount().toString(),
                        Icons.error,
                        Colors.red,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => OutOfStockScreen(userName: widget.userName),
                            ),
                          ).then((_) => _loadInventory());
                        },
                      ),
                    ],
                  ),
                ),
              if (_selectedWarehouseId != null) const SizedBox(height: 16),
              if (_consecutiveErrors > 0)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning, color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Errors detected: $_consecutiveErrors/$_maxConsecutiveErrors',
                          style: const TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                            ),
                            SizedBox(height: 16),
                            Text(
                              "Loading inventory...",
                              style: TextStyle(
                                fontSize: 16,
                                color: AppColors.textLight,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _errorMessage != null
                        ? SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  size: 64,
                                  color: Colors.red,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  "Error loading inventory",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.withOpacity(0.8),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppColors.textLight,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                ElevatedButton.icon(
                                  onPressed: _loadInventory,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Retry'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _filteredInventory.isEmpty
                            ? SingleChildScrollView(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.inventory_2_outlined,
                                      size: 64,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _selectedWarehouseId == null
                                          ? "Please select a warehouse"
                                          : "No inventory items found in $_currentWarehouseName",
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.textLight,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      "Add items using Storage Scanner or the + button",
                                      style: TextStyle(
                                        color: AppColors.textLight,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 20),
                                    if (_selectedWarehouseId != null)
                                      ElevatedButton.icon(
                                        onPressed: _isProcessingScan ? null : _showAddItemDialog,
                                        icon: const Icon(Icons.add),
                                        label: const Text('Add First Item'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blue,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                  ],
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _loadInventory,
                                child: ListView.builder(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: _filteredInventory.length,
                                  itemBuilder: (context, index) {
                                    final item = _filteredInventory[index];
                                    return _buildInventoryCard(item);
                                  },
                                ),
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
