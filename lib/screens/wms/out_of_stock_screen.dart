// lib/screens/wms/out_of_stock_screen.dart

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';
import 'dart:io';
import '../../services/warehouse_service.dart';
import '../../utils/colors.dart';

class OutOfStockScreen extends StatefulWidget {
  final String userName;
  const OutOfStockScreen({super.key, required this.userName});

  @override
  State<OutOfStockScreen> createState() => _OutOfStockScreenState();
}

class _OutOfStockScreenState extends State<OutOfStockScreen> {
  List<Map<String, dynamic>> _outOfStockItems = [];
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
    _loadOutOfStockItems();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _minStockController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _loadOutOfStockItems() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final allInventory = await WarehouseService.fetchInventory(limit: 2000);
      
      // Filter for out of stock items (quantity = 0)
      final outOfStock = allInventory.where((item) {
        final quantity = (item['quantity'] ?? 0) as int;
        return quantity == 0;
      }).toList();

      // Sort by name
      outOfStock.sort((a, b) {
        final aName = (a['name'] ?? '').toString().toLowerCase();
        final bName = (b['name'] ?? '').toString().toLowerCase();
        return aName.compareTo(bName);
      });

      if (mounted) {
        setState(() {
          _outOfStockItems = outOfStock;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
        _showErrorMessage('Failed to load out of stock items: $e');
      }
    }
  }

  Future<void> _restockItem(Map<String, dynamic> item, Map<String, dynamic> updates) async {
    try {
      setState(() => _isLoading = true);
      
      final success = await WarehouseService.updateInventory(item['id'], updates);
      
      if (success) {
        _showSuccessMessage('Item restocked successfully');
        await _loadOutOfStockItems(); // Reload to reflect changes
      } else {
        _showErrorMessage('Failed to restock item');
      }
    } catch (e) {
      _showErrorMessage('Restock error: $e');
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
        await _loadOutOfStockItems(); // Reload to reflect changes
      } else {
        _showErrorMessage('Failed to delete item');
      }
    } catch (e) {
      _showErrorMessage('Delete error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showRestockDialog(Map<String, dynamic> item) {
    _quantityController.text = '10'; // Default restock amount
    _minStockController.text = (item['min_stock'] ?? 10).toString();
    _priceController.text = (item['unit_price'] ?? 0.0).toString();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.add_box, color: Colors.green, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Restock ${item['name'] ?? 'Item'}',
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
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'OUT OF STOCK\nSKU: ${item['sku'] ?? 'N/A'}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.red,
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
                    labelText: 'Restock Quantity *',
                    prefixIcon: const Icon(Icons.add),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    helperText: 'How many units to add?',
                  ),
                  keyboardType: TextInputType.number,
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _minStockController,
                  decoration: InputDecoration(
                    labelText: 'Minimum Stock Level *',
                    prefixIcon: const Icon(Icons.warning),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    helperText: 'Future alert threshold',
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
            onPressed: () => _handleRestock(item),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Restock'),
          ),
        ],
      ),
    );
  }

  void _handleRestock(Map<String, dynamic> item) {
    // Validation
    final restockQuantity = int.tryParse(_quantityController.text.trim());
    final newMinStock = int.tryParse(_minStockController.text.trim());
    final newPrice = double.tryParse(_priceController.text.trim());

    if (restockQuantity == null || restockQuantity <= 0) {
      _showErrorMessage('Please enter a valid restock quantity');
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
      'quantity': restockQuantity,
      'min_stock': newMinStock,
      'unit_price': newPrice,
    };

    _restockItem(item, updates);
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
                    'This item is out of stock.\nThis action cannot be undone.',
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

  Future<void> _exportOutOfStockReport() async {
    setState(() => _isExporting = true);
    try {
      List<List<dynamic>> csvData = [
        ['OUT OF STOCK REPORT'],
        ['Generated on:', DateTime.now().toString()],
        ['Generated by:', widget.userName],
        ['Total Out of Stock Items:', _outOfStockItems.length.toString()],
        [],
        [
          'Item Name',
          'SKU',
          'Barcode',
          'Minimum Stock',
          'Unit Price',
          'Category',
          'Location',
          'Days Out of Stock',
          'Last Updated'
        ],
      ];

      for (var item in _outOfStockItems) {
        final minStock = (item['min_stock'] ?? 10) as int;
        final unitPrice = (item['unit_price'] ?? 0.0) as double;
        
        // Calculate days out of stock (rough estimate)
        int daysOutOfStock = 0;
        if (item['updated_at'] != null) {
          try {
            final lastUpdate = DateTime.parse(item['updated_at']);
            daysOutOfStock = DateTime.now().difference(lastUpdate).inDays;
          } catch (e) {
            daysOutOfStock = 0;
          }
        }

        csvData.add([
          item['name'] ?? '',
          item['sku'] ?? '',
          item['barcode'] ?? '',
          minStock.toString(),
          unitPrice.toStringAsFixed(2),
          item['category'] ?? 'General',
          item['location'] ?? 'Storage',
          daysOutOfStock.toString(),
          item['updated_at']?.toString().substring(0, 16) ?? '',
        ]);
      }

      String csvString = const ListToCsvConverter().convert(csvData);
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toString().replaceAll(':', '-').substring(0, 19);
      final file = File('${directory.path}/out_of_stock_report_$timestamp.csv');
      await file.writeAsString(csvString);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Out of Stock Report - ${_outOfStockItems.length} items need immediate restocking',
      );

      _showSuccessMessage('Out of stock report exported successfully!');
    } catch (e) {
      _showErrorMessage('Export failed: $e');
    } finally {
      setState(() => _isExporting = false);
    }
  }

  Widget _buildOutOfStockCard(Map<String, dynamic> item, int index) {
    final name = item['name'] ?? "Unnamed";
    final sku = item['sku'] ?? "N/A";
    final minStock = (item['min_stock'] ?? 10) as int;
    final unitPrice = (item['unit_price'] ?? 0.0) as double;
    final category = item['category'] ?? "General";
    final location = item['location'] ?? "Storage";

    // Calculate days out of stock
    int daysOutOfStock = 0;
    if (item['updated_at'] != null) {
      try {
        final lastUpdate = DateTime.parse(item['updated_at']);
        daysOutOfStock = DateTime.now().difference(lastUpdate).inDays;
      } catch (e) {
        daysOutOfStock = 0;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withOpacity(0.3), width: 2),
        ),
        child: ExpansionTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.error, color: Colors.red, size: 24),
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
              Text('Min Stock: $minStock • Location: $location'),
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  daysOutOfStock > 0 ? '$daysOutOfStock days out of stock' : 'OUT OF STOCK',
                  style: const TextStyle(
                    color: Colors.red,
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
                case 'restock':
                  _showRestockDialog(item);
                  break;
                case 'delete':
                  _showDeleteDialog(item);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'restock',
                child: Row(
                  children: [
                    Icon(Icons.add_box, size: 18, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Restock'),
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
                        child: _buildDetailItem('Description', item['description'] ?? 'No description'),
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
                          onPressed: () => _showRestockDialog(item),
                          icon: const Icon(Icons.add_box, size: 18),
                          label: const Text('Restock Now'),
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
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🚫 Out of Stock Items'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loadOutOfStockItems,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: _isExporting ? null : _exportOutOfStockReport,
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
              Colors.red.withOpacity(0.1),
              Colors.white,
            ],
          ),
        ),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Colors.red),
                ),
              )
            : _errorMessage != null
                ? _buildErrorState()
                : _outOfStockItems.isEmpty
                    ? _buildEmptyState()
                    : _buildOutOfStockList(),
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
              onPressed: _loadOutOfStockItems,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
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
              'Great! 🎉',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'No items are currently out of stock',
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textLight,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _loadOutOfStockItems,
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

  Widget _buildOutOfStockList() {
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
              const Icon(Icons.error, color: Colors.red, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_outOfStockItems.length} Items Out of Stock',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    const Text(
                      'Critical - immediate restocking required',
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
            itemCount: _outOfStockItems.length,
            itemBuilder: (context, index) {
              return _buildOutOfStockCard(_outOfStockItems[index], index);
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

