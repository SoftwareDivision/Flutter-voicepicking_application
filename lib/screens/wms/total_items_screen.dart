// lib/screens/wms/total_items_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';

import '../../utils/colors.dart';

class TotalItemsScreen extends StatefulWidget {
  final String userName;
  final List<Map<String, dynamic>> inventoryItems;

  const TotalItemsScreen({
    super.key,
    required this.userName,
    required this.inventoryItems,
  });

  @override
  State<TotalItemsScreen> createState() => _TotalItemsScreenState();
}

class _TotalItemsScreenState extends State<TotalItemsScreen>
    with TickerProviderStateMixin {
  
  // Search and Filter Controllers
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredItems = [];
  String _selectedCategory = 'All';
  String _sortBy = 'name'; // name, quantity, price, category
  bool _sortAscending = true;
  
  // Animation Controllers
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  
  @override
  void initState() {
    super.initState();
    _filteredItems = List.from(widget.inventoryItems);
    _initializeAnimations();
    _searchController.addListener(_filterAndSortItems);
    _sortItems();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _searchController.dispose();
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

  // ================================
  // CLEAN DATA PARSING (SAME AS INVENTORY SCREEN)
  // ================================

  String _getCleanProductName(Map<String, dynamic> item) {
    String name = item['name'] ?? 'Unknown Item';
    
    if (name.contains('Product Details:') || name.contains('Item ID:')) {
      String description = item['description']?.toString() ?? '';
      if (description.isNotEmpty && description != 'Item scanned via Storage Scanner') {
        String cleanDesc = description
            .replaceAll(RegExp(r'Product Details:.*?Item ID:.*?\n'), '')
            .replaceAll(RegExp(r'\| Barcode Check Digit:.*'), '')
            .split('(')[0]
            .trim();
        if (cleanDesc.isNotEmpty && cleanDesc.length > 3) {
          return cleanDesc.length > 50 ? cleanDesc.substring(0, 50) : cleanDesc;
        }
      }
      
      String sku = item['sku']?.toString() ?? '';
      String barcode = item['barcode']?.toString() ?? '';
      
      if (sku.isNotEmpty && !sku.startsWith('SKU_')) {
        return 'Product $sku';
      } else if (barcode.isNotEmpty && barcode.length >= 6) {
        return 'Item ${barcode.substring(max(0, barcode.length - 8))}';
      } else {
        return 'Scanned Product';
      }
    }
    
    return name.length > 50 ? name.substring(0, 50) : name;
  }

  String _getCleanDescription(Map<String, dynamic> item) {
    String description = item['description']?.toString() ?? '';
    
    if (description.isEmpty || description == 'Item scanned via Storage Scanner') {
      return 'No description available';
    }
    
    String cleaned = description
        .replaceAll(RegExp(r'Product Details:.*?-+'), '')
        .replaceAll(RegExp(r'Item ID:.*?\n'), '')
        .replaceAll(RegExp(r'\| Barcode Check Digit:.*'), '')
        .replaceAll(RegExp(r'Barcode Check Digit:.*'), '')
        .trim();
    
    if (cleaned.isEmpty) {
      return 'Scanned product - no description';
    }
    
    return cleaned.length > 200 ? '${cleaned.substring(0, 200)}...' : cleaned;
  }

  // ================================
  // FILTERING AND SORTING
  // ================================

  void _filterAndSortItems() {
    final searchTerm = _searchController.text.toLowerCase();
    
    setState(() {
      _filteredItems = widget.inventoryItems.where((item) {
        final matchesSearch = searchTerm.isEmpty ||
            (_getCleanProductName(item).toLowerCase().contains(searchTerm)) ||
            (item['sku']?.toString().toLowerCase().contains(searchTerm) ?? false) ||
            (item['barcode']?.toString().toLowerCase().contains(searchTerm) ?? false) ||
            (_getCleanDescription(item).toLowerCase().contains(searchTerm));
        
        final matchesCategory = _selectedCategory == 'All' ||
            item['category'] == _selectedCategory;
        
        return matchesSearch && matchesCategory;
      }).toList();
    });
    
    _sortItems();
  }

  void _sortItems() {
    setState(() {
      _filteredItems.sort((a, b) {
        dynamic aValue, bValue;
        
        switch (_sortBy) {
          case 'name':
            aValue = _getCleanProductName(a).toLowerCase();
            bValue = _getCleanProductName(b).toLowerCase();
            break;
          case 'quantity':
            aValue = a['quantity'] ?? 0;
            bValue = b['quantity'] ?? 0;
            break;
          case 'price':
            aValue = (a['unit_price'] ?? 0.0).toDouble();
            bValue = (b['unit_price'] ?? 0.0).toDouble();
            break;
          case 'category':
            aValue = (a['category'] ?? 'General').toLowerCase();
            bValue = (b['category'] ?? 'General').toLowerCase();
            break;
          default:
            aValue = _getCleanProductName(a).toLowerCase();
            bValue = _getCleanProductName(b).toLowerCase();
        }
        
        int comparison;
        if (aValue is String && bValue is String) {
          comparison = aValue.compareTo(bValue);
        } else if (aValue is num && bValue is num) {
          comparison = aValue.compareTo(bValue);
        } else {
          comparison = aValue.toString().compareTo(bValue.toString());
        }
        
        return _sortAscending ? comparison : -comparison;
      });
    });
  }

  Set<String> _getCategories() {
    Set<String> categories = {'All'};
    for (var item in widget.inventoryItems) {
      if (item['category'] != null) {
        categories.add(item['category']);
      }
    }
    return categories;
  }

  // ================================
  // PROFESSIONAL ITEM CARD
  // ================================

  Widget _buildProfessionalItemCard(Map<String, dynamic> item) {
    final cleanName = _getCleanProductName(item);
    final cleanDescription = _getCleanDescription(item);
    final sku = item['sku']?.toString() ?? "N/A";
    final quantity = (item['quantity'] ?? 0) as int;
    final minStock = (item['min_stock'] ?? 10) as int;
    final category = item['category'] ?? "General";
    final barcode = item['barcode']?.toString() ?? "N/A";
    final unitPrice = (item['unit_price'] ?? 0.0).toDouble();
    final totalValue = quantity * unitPrice;
    final location = item['location'] ?? "Storage";

    // Status determination
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
      margin: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: statusColor.withOpacity(0.3),
              width: 2,
            ),
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.all(16),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            leading: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                statusIcon,
                color: statusColor,
                size: 28,
              ),
            ),
            title: Text(
              cleanName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: AppColors.textDark,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  "SKU: $sku • Qty: $quantity",
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: statusColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, color: statusColor, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            status,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ],
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
            trailing: Icon(
              Icons.expand_more,
              color: statusColor,
            ),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Description Section
                    const Text(
                      'Description',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      cleanDescription,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textLight,
                        height: 1.4,
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    
                    // Detailed Information Grid
                    const Text(
                      'Product Details',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    Row(
                      children: [
                        _buildDetailInfoCard(
                          'Current Stock',
                          quantity.toString(),
                          Icons.inventory_2,
                          statusColor,
                        ),
                        const SizedBox(width: 8),
                        _buildDetailInfoCard(
                          'Min Stock',
                          minStock.toString(),
                          Icons.warning,
                          Colors.orange,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildDetailInfoCard(
                          'Unit Price',
                          '₹${unitPrice.toStringAsFixed(2)}',
                          Icons.currency_rupee,
                          Colors.green,
                        ),
                        const SizedBox(width: 8),
                        _buildDetailInfoCard(
                          'Total Value',
                          '₹${totalValue.toStringAsFixed(2)}',
                          Icons.calculate,
                          Colors.purple,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildDetailInfoCard(
                          'Location',
                          location,
                          Icons.place,
                          Colors.blue,
                        ),
                        const SizedBox(width: 8),
                        _buildDetailInfoCard(
                          'Category',
                          category,
                          Icons.category,
                          Colors.indigo,
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    
                    // Technical Information
                    const Text(
                      'Technical Details',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    _buildTechnicalDetailRow('SKU', sku),
                    _buildTechnicalDetailRow('Barcode', barcode),
                    _buildTechnicalDetailRow('Location Check Digit', 
                        item['location_check_digit']?.toString() ?? 'N/A'),
                    _buildTechnicalDetailRow('Barcode Check Digits', 
                        item['barcode_digits']?.toString() ?? 'N/A'),
                    _buildTechnicalDetailRow('Created By', 
                        item['created_by']?.toString() ?? 'System'),
                    _buildTechnicalDetailRow('Last Updated', 
                        _formatDate(item['updated_at']?.toString() ?? '')),
                    
                    const SizedBox(height: 16),
                    
                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _copyToClipboard(barcode),
                            icon: const Icon(Icons.copy, size: 16),
                            label: const Text('Copy Barcode'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryPink,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _copyToClipboard(sku),
                            icon: const Icon(Icons.content_copy, size: 16),
                            label: const Text('Copy SKU'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
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
      ),
    );
  }

  Widget _buildDetailInfoCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTechnicalDetailRow(String label, String value) {
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
                fontWeight: FontWeight.w600,
                color: AppColors.textLight,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
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
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateStr.length > 16 ? dateStr.substring(0, 16) : dateStr;
    }
  }

  void _copyToClipboard(String text) {
    try {
      Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$text copied to clipboard'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to copy to clipboard'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ================================
  // BUILD METHOD
  // ================================

  @override
  Widget build(BuildContext context) {
    final categories = _getCategories();
    
    return Scaffold(
      appBar: AppBar(
        title: Text('All Items (${_filteredItems.length})'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Sort Options
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            onSelected: (value) {
              setState(() {
                if (_sortBy == value) {
                  _sortAscending = !_sortAscending;
                } else {
                  _sortBy = value;
                  _sortAscending = true;
                }
              });
              _sortItems();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'name',
                child: Row(
                  children: [
                    Icon(Icons.sort_by_alpha, 
                         color: _sortBy == 'name' ? Colors.blue : null),
                    const SizedBox(width: 8),
                    Text('Sort by Name'),
                    if (_sortBy == 'name') ...[
                      const Spacer(),
                      Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                           size: 16, color: Colors.blue),
                    ],
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'quantity',
                child: Row(
                  children: [
                    Icon(Icons.numbers, 
                         color: _sortBy == 'quantity' ? Colors.blue : null),
                    const SizedBox(width: 8),
                    Text('Sort by Quantity'),
                    if (_sortBy == 'quantity') ...[
                      const Spacer(),
                      Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                           size: 16, color: Colors.blue),
                    ],
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'price',
                child: Row(
                  children: [
                    Icon(Icons.currency_rupee, 
                         color: _sortBy == 'price' ? Colors.blue : null),
                    const SizedBox(width: 8),
                    Text('Sort by Price'),
                    if (_sortBy == 'price') ...[
                      const Spacer(),
                      Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                           size: 16, color: Colors.blue),
                    ],
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'category',
                child: Row(
                  children: [
                    Icon(Icons.category, 
                         color: _sortBy == 'category' ? Colors.blue : null),
                    const SizedBox(width: 8),
                    Text('Sort by Category'),
                    if (_sortBy == 'category') ...[
                      const Spacer(),
                      Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                           size: 16, color: Colors.blue),
                    ],
                  ],
                ),
              ),
            ],
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
              // Search and Filter Section
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Search Bar
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search items by name, SKU, barcode, or description...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  _filterAndSortItems();
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Category Filter
                    DropdownButtonFormField<String>(
                      value: _selectedCategory,
                      decoration: InputDecoration(
                        labelText: 'Filter by Category',
                        prefixIcon: const Icon(Icons.filter_list),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: categories
                          .map((category) => DropdownMenuItem(
                                value: category,
                                child: Text(category),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedCategory = value ?? 'All';
                        });
                        _filterAndSortItems();
                      },
                    ),
                  ],
                ),
              ),
              
              // Results Summary
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.inventory_2, color: Colors.blue, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            '${_filteredItems.length} items found',
                            style: const TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Sorted by ${_sortBy} ${_sortAscending ? "↑" : "↓"}',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Items List
              Expanded(
                child: _filteredItems.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 64,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No items match your search',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Try adjusting your search or filters',
                              style: TextStyle(
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredItems.length,
                        itemBuilder: (context, index) {
                          return _buildProfessionalItemCard(_filteredItems[index]);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



