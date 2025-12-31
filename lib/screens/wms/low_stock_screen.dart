// lib/screens/wms/low_stock_screen.dart

import 'package:flutter/material.dart';
// ignore: unnecessary_import
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';
import 'dart:io';
import '../../services/warehouse_service.dart';
import '../../utils/colors.dart';

class LowStockScreen extends StatefulWidget {
  final String userName;
  const LowStockScreen({super.key, required this.userName});

  @override
  State<LowStockScreen> createState() => _LowStockScreenState();
}

class _LowStockScreenState extends State<LowStockScreen> {
  List<Map<String, dynamic>> _lowStockItems = [];
  bool _isLoading = true;
  bool _isExporting = false;
  String? _errorMessage;

  // Controllers for editing
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _minStockController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLowStockItems();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _minStockController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _loadLowStockItems() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final allInventory = await WarehouseService.fetchInventory(limit: 2000);
      
      // Filter for low stock items (quantity > 0 but <= min_stock)
      final lowStock = allInventory.where((item) {
        final quantity = (item['quantity'] ?? 0) as int;
        final minStock = (item['min_stock'] ?? 10) as int;
        return quantity > 0 && quantity <= minStock;
      }).toList();

      // Sort by lowest quantity first
      lowStock.sort((a, b) {
        final aQty = (a['quantity'] ?? 0) as int;
        final bQty = (b['quantity'] ?? 0) as int;
        return aQty.compareTo(bQty);
      });

      if (mounted) {
        setState(() {
          _lowStockItems = lowStock;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
        _showErrorMessage('Failed to load low stock items: $e');
      }
    }
  }

  Future<void> _updateItem(Map<String, dynamic> item, Map<String, dynamic> updates) async {
    try {
      setState(() => _isLoading = true);
      
      final success = await WarehouseService.updateInventory(item['id'], updates);
      
      if (success) {
        _showSuccessMessage('Item updated successfully');
        await _loadLowStockItems(); // Reload to reflect changes
      } else {
        _showErrorMessage('Failed to update item');
      }
    } catch (e) {
      _showErrorMessage('Update error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    try {
      setState(() => _isLoading = true);
      
      final success = await WarehouseService.deleteInventory(item['id']);
      
      if (success) {
        _showSuccessMessage('Item deleted successfully');
        await _loadLowStockItems(); // Reload to reflect changes
      } else {
        _showErrorMessage('Failed to delete item');
      }
    } catch (e) {
      _showErrorMessage('Delete error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showUpdateDialog(Map<String, dynamic> item) {
    _quantityController.text = (item['quantity'] ?? 0).toString();
    _minStockController.text = (item['min_stock'] ?? 10).toString();
    _priceController.text = (item['unit_price'] ?? 0.0).toString();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.edit, color: Colors.orange, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Update ${item['name'] ?? 'Item'}',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning, color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'SKU: ${item['sku'] ?? 'N/A'}\nCurrent Stock: ${item['quantity'] ?? 0}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _quantityController,
                  decoration: InputDecoration(
                    labelText: 'New Quantity *',
                    prefixIcon: const Icon(Icons.numbers),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    helperText: 'Increase stock quantity',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _minStockController,
                  decoration: InputDecoration(
                    labelText: 'Minimum Stock Level *',
                    prefixIcon: const Icon(Icons.warning),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    helperText: 'Alert threshold',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _priceController,
                  decoration: InputDecoration(
                    labelText: 'Unit Price (₹)',
                    prefixIcon: const Icon(Icons.currency_rupee),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
            onPressed: () => _handleUpdate(item),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _handleUpdate(Map<String, dynamic> item) {
    // Validation
    final newQuantity = int.tryParse(_quantityController.text.trim());
    final newMinStock = int.tryParse(_minStockController.text.trim());
    final newPrice = double.tryParse(_priceController.text.trim());

    if (newQuantity == null || newQuantity < 0) {
      _showErrorMessage('Please enter a valid quantity');
      return;
    }

    if (newMinStock == null || newMinStock < 0) {
      _showErrorMessage('Please enter a valid minimum stock');
      return;
    }

    if (newPrice == null || newPrice < 0) {
      _showErrorMessage('Please enter a valid price');
      return;
    }

    Navigator.pop(context);

    final updates = {
      'quantity': newQuantity,
      'min_stock': newMinStock,
      'unit_price': newPrice,
    };

    _updateItem(item, updates);
  }

  void _showDeleteDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Text('Delete Item'),
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
                  const Icon(Icons.delete_forever, color: Colors.red, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Delete "${item['name'] ?? 'this item'}"?',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Current Stock: ${item['quantity'] ?? 0} units\nThis action cannot be undone.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteItem(item);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportLowStockReport() async {
    setState(() => _isExporting = true);
    try {
      List<List<dynamic>> csvData = [
        ['LOW STOCK ALERT REPORT'],
        ['Generated on:', DateTime.now().toString()],
        ['Generated by:', widget.userName],
        ['Total Low Stock Items:', _lowStockItems.length.toString()],
        [],
        [
          'Item Name',
          'SKU',
          'Barcode',
          'Current Quantity',
          'Minimum Stock',
          'Unit Price',
          'Total Value',
          'Category',
          'Location',
          'Stock Status',
          'Last Updated'
        ],
      ];

      for (var item in _lowStockItems) {
        final quantity = (item['quantity'] ?? 0) as int;
        final minStock = (item['min_stock'] ?? 10) as int;
        final unitPrice = (item['unit_price'] ?? 0.0) as double;
        final totalValue = quantity * unitPrice;
        
        String stockStatus = 'Critical';
        if (quantity <= minStock / 2) {
          stockStatus = 'Critical';
        } else {
          stockStatus = 'Low';
        }

        csvData.add([
          item['name'] ?? '',
          item['sku'] ?? '',
          item['barcode'] ?? '',
          quantity.toString(),
          minStock.toString(),
          unitPrice.toStringAsFixed(2),
          totalValue.toStringAsFixed(2),
          item['category'] ?? 'General',
          item['location'] ?? 'Storage',
          stockStatus,
          item['updated_at']?.toString().substring(0, 16) ?? '',
        ]);
      }

      String csvString = const ListToCsvConverter().convert(csvData);
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toString().replaceAll(':', '-').substring(0, 19);
      final file = File('${directory.path}/low_stock_report_$timestamp.csv');
      await file.writeAsString(csvString);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Low Stock Alert Report - ${_lowStockItems.length} items requiring attention',
      );

      _showSuccessMessage('Low stock report exported successfully!');
    } catch (e) {
      _showErrorMessage('Export failed: $e');
    } finally {
      setState(() => _isExporting = false);
    }
  }

  Widget _buildLowStockCard(Map<String, dynamic> item, int index) {
    final name = item['name'] ?? "Unnamed";
    final sku = item['sku'] ?? "N/A";
    final quantity = (item['quantity'] ?? 0) as int;
    final minStock = (item['min_stock'] ?? 10) as int;
    final unitPrice = (item['unit_price'] ?? 0.0) as double;
    final totalValue = quantity * unitPrice;
    final category = item['category'] ?? "General";
    final location = item['location'] ?? "Storage";

    // Determine criticality
    Color alertColor = Colors.orange;
    String alertLevel = 'Low Stock';
    IconData alertIcon = Icons.warning;
    
    if (quantity <= minStock / 2) {
      alertColor = Colors.red;
      alertLevel = 'Critical';
      alertIcon = Icons.error;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: alertColor.withOpacity(0.3), width: 2),
        ),
        child: ExpansionTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: alertColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(alertIcon, color: alertColor, size: 24),
          ),
          title: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SKU: $sku • $category'),
              Text('Stock: $quantity/$minStock • Location: $location'),
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: alertColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  alertLevel,
                  style: TextStyle(
                    color: alertColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          trailing: PopupMenuButton(
            onSelected: (value) {
              switch (value) {
                case 'update':
                  _showUpdateDialog(item);
                  break;
                case 'delete':
                  _showDeleteDialog(item);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'update',
                child: Row(
                  children: [
                    Icon(Icons.edit, size: 18, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Update Stock'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, size: 18, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Delete Item'),
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
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildDetailItem('Barcode', item['barcode'] ?? 'N/A'),
                      ),
                      Expanded(
                        child: _buildDetailItem('Unit Price', '₹${unitPrice.toStringAsFixed(2)}'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDetailItem('Total Value', '₹${totalValue.toStringAsFixed(2)}'),
                      ),
                      Expanded(
                        child: _buildDetailItem('Last Updated', 
                          item['updated_at']?.toString().substring(0, 16) ?? 'N/A'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _showUpdateDialog(item),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Restock'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showDeleteDialog(item),
                          icon: const Icon(Icons.delete, size: 18),
                          label: const Text('Delete'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚠️ Low Stock Items'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loadLowStockItems,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: _isExporting ? null : _exportLowStockReport,
            icon: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Icon(Icons.file_download),
            tooltip: 'Export Report',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.orange.withOpacity(0.1),
              Colors.white,
            ],
          ),
        ),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Colors.orange),
                ),
              )
            : _errorMessage != null
                ? _buildErrorState()
                : _lowStockItems.isEmpty
                    ? _buildEmptyState()
                    : _buildLowStockList(),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            const Text(
              'Failed to Load Data',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Unknown error occurred',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textLight,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadLowStockItems,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                size: 80,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'All Good! 🎉',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'No items are currently running low on stock',
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textLight,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _loadLowStockItems,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLowStockList() {
    return Column(
      children: [
        // Header Stats
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.warning, color: Colors.orange, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_lowStockItems.length} Items Need Attention',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                    const Text(
                      'Items running low on stock - restock recommended',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Items List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: _lowStockItems.length,
            itemBuilder: (context, index) {
              return _buildLowStockCard(_lowStockItems[index], index);
            },
          ),
        ),
      ],
    );
  }

  void _showSuccessMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  void _showErrorMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }
}


