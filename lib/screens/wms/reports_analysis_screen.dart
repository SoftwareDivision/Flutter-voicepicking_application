// lib/screens/wms/reports_analysis_screen.dart

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';
import 'dart:io';

import '../../services/warehouse_service.dart';
import '../../services/loading_service.dart';
import '../../utils/colors.dart';

class ReportsAnalysisScreen extends StatefulWidget {
  final String userName;

  const ReportsAnalysisScreen({super.key, required this.userName});

  @override
  State<ReportsAnalysisScreen> createState() => _ReportsAnalysisScreenState();
}

class _ReportsAnalysisScreenState extends State<ReportsAnalysisScreen>
    with TickerProviderStateMixin {
  // Core State Variables
  bool _isLoading = true;
  String? _errorMessage;

  // Report Data
  Map<String, dynamic> _dashboardStats = {};
  List<Map<String, dynamic>> _inventoryReports = [];
  List<Map<String, dynamic>> _picklistReports = [];
  List<Map<String, dynamic>> _loadingReports = [];
  List<Map<String, dynamic>> _movementReports = [];
  List<Map<String, dynamic>> _storageReports = [];

  // Export States
  bool _isExportingInventory = false;
  bool _isExportingPicklist = false;
  bool _isExportingLoading = false;
  bool _isExportingMovement = false;
  bool _isExportingStorage = false;
  bool _isExportingAnalytics = false;

  // Animation Controllers
  late TabController _tabController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _loadAllReports();
    _fadeController.forward();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  // ================================
  // DATA LOADING METHODS
  // ================================

  Future<void> _loadAllReports() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      debugPrint('🔄 Loading all reports...');

      // Load dashboard stats
      final dashboardResult = await WarehouseService.getDashboardStats();
      if (dashboardResult['success'] == true) {
        _dashboardStats = dashboardResult['data'] ?? {};
      }

      // Load inventory reports
      final inventoryResult = await WarehouseService.getInventoryReports();
      if (inventoryResult['success'] == true) {
        _inventoryReports = List<Map<String, dynamic>>.from(
          inventoryResult['data'] ?? [],
        );
      }

      // Load storage reports
      final storageResult = await WarehouseService.getStorageReports();
      if (storageResult['success'] == true) {
        _storageReports = List<Map<String, dynamic>>.from(
          storageResult['data'] ?? [],
        );
      }

      // Load picklist reports
      final picklistResult = await WarehouseService.getPicklistReports();
      if (picklistResult['success'] == true) {
        _picklistReports = List<Map<String, dynamic>>.from(
          picklistResult['data'] ?? [],
        );
      }

      // Load loading reports
      final loadingResult = await LoadingService.getLoadingReports();
      _loadingReports = List<Map<String, dynamic>>.from(loadingResult);

      // Load movement reports
      final movementResult = await WarehouseService.getInventoryMovementReports();
      if (movementResult['success'] == true) {
        _movementReports = List<Map<String, dynamic>>.from(
          movementResult['data'] ?? [],
        );
      }

      debugPrint('✅ All reports loaded successfully');
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading reports: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load reports: $e';
        });
      }
    }
  }

  // ================================
  // UTILITY METHODS
  // ================================

  /// Format large currency values for display - COMPACT
  String _formatCurrency(double amount) {
    if (amount >= 10000000) {
      return '₹${(amount / 10000000).toStringAsFixed(2)}Cr';
    } else if (amount >= 100000) {
      return '₹${(amount / 100000).toStringAsFixed(2)}L';
    } else if (amount >= 1000) {
      return '₹${(amount / 1000).toStringAsFixed(1)}K';
    } else {
      return '₹${amount.toStringAsFixed(0)}';
    }
  }

  /// Safe substring for IDs
  String _safeSubstring(String value, int start, int end) {
    if (value.isEmpty || value.length < end) {
      return value;
    }
    try {
      return value.substring(start, end);
    } catch (e) {
      return value;
    }
  }

  // ================================
  // EXPORT METHODS (CSV)
  // ================================

  Future<void> _exportInventoryReport() async {
    if (_inventoryReports.isEmpty) {
      _showSnackbar('No inventory data to export');
      return;
    }

    setState(() => _isExportingInventory = true);

    try {
      List<List<dynamic>> rows = [
        ['Name', 'SKU', 'Category', 'Quantity', 'Min Stock', 'Unit Price (₹)', 'Location', 'Status']
      ];

      for (var item in _inventoryReports) {
        rows.add([
          item['name'] ?? '',
          item['sku'] ?? '',
          item['category'] ?? '',
          item['quantity'] ?? 0,
          item['min_stock'] ?? 0,
          item['unit_price']?.toStringAsFixed(2) ?? '0.00',
          item['location'] ?? '',
          item['is_active'] == true ? 'Active' : 'Inactive',
        ]);
      }

      String csv = const ListToCsvConverter().convert(rows);
      await _saveAndShareFile(csv, 'inventory_report.csv');
      
      if (mounted) {
        _showSnackbar('Inventory report exported successfully');
      }
    } catch (e) {
      debugPrint('❌ Export error: $e');
      if (mounted) {
        _showSnackbar('Export failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingInventory = false);
      }
    }
  }

  Future<void> _exportStorageReport() async {
    if (_storageReports.isEmpty) {
      _showSnackbar('No storage data to export');
      return;
    }

    setState(() => _isExportingStorage = true);

    try {
      List<List<dynamic>> rows = [
        ['Item Name', 'Item No', 'Barcode', 'Quantity', 'Location', 'Unit Price (₹)', 'Scanned By', 'Date Added']
      ];

      for (var item in _storageReports) {
        rows.add([
          item['item_name'] ?? item['description'] ?? '',
          item['item_no'] ?? '',
          item['barcode'] ?? '',
          item['qty'] ?? 0,
          item['location'] ?? '',
          item['unit_price']?.toStringAsFixed(2) ?? '0.00',
          item['scanned_by'] ?? '',
          item['date_added'] ?? '',
        ]);
      }

      String csv = const ListToCsvConverter().convert(rows);
      await _saveAndShareFile(csv, 'storage_report.csv');
      
      if (mounted) {
        _showSnackbar('Storage report exported successfully');
      }
    } catch (e) {
      debugPrint('❌ Export error: $e');
      if (mounted) {
        _showSnackbar('Export failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingStorage = false);
      }
    }
  }

  Future<void> _exportPicklistReport() async {
    if (_picklistReports.isEmpty) {
      _showSnackbar('No picklist data to export');
      return;
    }

    setState(() => _isExportingPicklist = true);

    try {
      List<List<dynamic>> rows = [
        ['Picklist ID', 'Customer', 'Item', 'Quantity', 'Status', 'Picked By', 'Created At']
      ];

      for (var item in _picklistReports) {
        rows.add([
          item['picklist_id'] ?? '',
          item['customer_name'] ?? '',
          item['item_name'] ?? '',
          item['quantity'] ?? 0,
          item['status'] ?? '',
          item['picked_by'] ?? '',
          item['created_at'] ?? '',
        ]);
      }

      String csv = const ListToCsvConverter().convert(rows);
      await _saveAndShareFile(csv, 'picklist_report.csv');
      
      if (mounted) {
        _showSnackbar('Picklist report exported successfully');
      }
    } catch (e) {
      debugPrint('❌ Export error: $e');
      if (mounted) {
        _showSnackbar('Export failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingPicklist = false);
      }
    }
  }

  Future<void> _exportLoadingReport() async {
    if (_loadingReports.isEmpty) {
      _showSnackbar('No loading data to export');
      return;
    }

    setState(() => _isExportingLoading = true);

    try {
      List<List<dynamic>> rows = [
        ['Shipment ID', 'Truck Plate', 'Cartons Loaded', 'Status', 'Loaded By', 'Completion Time']
      ];

      for (var item in _loadingReports) {
        rows.add([
          item['shipment_id'] ?? '',
          item['truck_plate'] ?? '',
          item['cartons_loaded'] ?? 0,
          item['status'] ?? '',
          item['loaded_by'] ?? '',
          item['completion_time'] ?? '',
        ]);
      }

      String csv = const ListToCsvConverter().convert(rows);
      await _saveAndShareFile(csv, 'loading_report.csv');
      
      if (mounted) {
        _showSnackbar('Loading report exported successfully');
      }
    } catch (e) {
      debugPrint('❌ Export error: $e');
      if (mounted) {
        _showSnackbar('Export failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingLoading = false);
      }
    }
  }

  Future<void> _exportMovementReport() async {
    if (_movementReports.isEmpty) {
      _showSnackbar('No movement data to export');
      return;
    }

    setState(() => _isExportingMovement = true);

    try {
      List<List<dynamic>> rows = [
        ['Item Name', 'Movement Type', 'Quantity Changed', 'Previous Qty', 'New Qty', 'Created By', 'Date']
      ];

      for (var item in _movementReports) {
        rows.add([
          item['item_name'] ?? '',
          item['movement_type'] ?? '',
          item['quantity_changed'] ?? 0,
          item['previous_quantity'] ?? 0,
          item['new_quantity'] ?? 0,
          item['created_by'] ?? '',
          item['created_at'] ?? '',
        ]);
      }

      String csv = const ListToCsvConverter().convert(rows);
      await _saveAndShareFile(csv, 'movement_report.csv');
      
      if (mounted) {
        _showSnackbar('Movement report exported successfully');
      }
    } catch (e) {
      debugPrint('❌ Export error: $e');
      if (mounted) {
        _showSnackbar('Export failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingMovement = false);
      }
    }
  }

  Future<void> _exportComprehensiveAnalytics() async {
    setState(() => _isExportingAnalytics = true);

    try {
      // Calculate total value
      double totalValue = 0.0;
      for (var item in _inventoryReports) {
        final qty = item['quantity'] ?? 0;
        final price = item['unit_price'] ?? 0.0;
        totalValue += (qty * price);
      }

      List<List<dynamic>> rows = [
        ['📊 COMPREHENSIVE WAREHOUSE ANALYTICS REPORT'],
        ['Generated on: ${DateTime.now()}'],
        ['Generated by: ${widget.userName}'],
        [],
        ['=== DASHBOARD STATISTICS ==='],
        ['Total Products', _dashboardStats['totalProducts'] ?? 0],
        ['Active Waves', _dashboardStats['activeWaves'] ?? 0],
        ['Pending Orders', _dashboardStats['pendingOrders'] ?? 0],
        ['Low Stock Alerts', _dashboardStats['lowStockAlerts'] ?? 0],
        ['System Efficiency', '${(_dashboardStats['systemEfficiency'] ?? 0).toStringAsFixed(2)}%'],
        ['Total Inventory Value', '₹${totalValue.toStringAsFixed(2)}'],
        [],
        ['=== MODULE SUMMARY ==='],
        ['Total Items', _inventoryReports.length],
        ['Total Storage Entries', _storageReports.length],
        ['Total Picklist Items', _picklistReports.length],
        ['Total Loading Records', _loadingReports.length],
        ['Total Movements', _movementReports.length],
        [],
      ];

      String csv = const ListToCsvConverter().convert(rows);
      await _saveAndShareFile(csv, 'comprehensive_analytics.csv');
      
      if (mounted) {
        _showSnackbar('Comprehensive analytics exported successfully');
      }
    } catch (e) {
      debugPrint('❌ Export error: $e');
      if (mounted) {
        _showSnackbar('Export failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingAnalytics = false);
      }
    }
  }

  Future<void> _saveAndShareFile(String csvData, String fileName) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);
      await file.writeAsString(csvData);

      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'Warehouse Report: $fileName',
      );
    } catch (e) {
      debugPrint('❌ Error saving/sharing file: $e');
      rethrow;
    }
  }

  void _showSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ================================
  // UI BUILD METHODS
  // ================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📊 Reports & Analytics'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loadAllReports,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Reports',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          isScrollable: true,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Inventory'),
            Tab(text: 'Storage'),
            Tab(text: 'Picklist'),
            Tab(text: 'Loading'),
            Tab(text: 'Movement'),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.teal.withOpacity(0.1),
              Colors.white,
            ],
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: _isLoading
              ? _buildLoadingScreen()
              : _errorMessage != null
                  ? _buildErrorScreen()
                  : _buildTabContent(),
        ),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(Colors.teal),
          ),
          SizedBox(height: 20),
          Text(
            'Loading Reports...',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.error,
            ),
            const SizedBox(height: 20),
            const Text(
              'Failed to Load Reports',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 12),
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
              onPressed: _loadAllReports,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildOverviewTab(),
        _buildInventoryTab(),
        _buildStorageTab(),
        _buildPicklistTab(),
        _buildLoadingTab(),
        _buildMovementTab(),
      ],
    );
  }

  // ================================
  // OVERVIEW TAB
  // ================================

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOverviewCard(),
          const SizedBox(height: 20),
          _buildStatisticsGrid(),
          const SizedBox(height: 20),
          _buildQuickActions(),
        ],
      ),
    );
  }

  Widget _buildOverviewCard() {
    final totalProducts = _dashboardStats['totalProducts'] ?? 0;
    final activeWaves = _dashboardStats['activeWaves'] ?? 0;
    final pendingOrders = _dashboardStats['pendingOrders'] ?? 0;
    final systemEfficiency = _dashboardStats['systemEfficiency'] ?? 0.0;

    // Calculate total value from inventory
    double totalValue = 0.0;
    for (var item in _inventoryReports) {
      final qty = item['quantity'] ?? 0;
      final price = item['unit_price'] ?? 0.0;
      totalValue += (qty * price);
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.teal.withOpacity(0.8),
              Colors.teal.withOpacity(0.6),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.analytics, color: Colors.white, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Warehouse Overview',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildOverviewStat('Products', '$totalProducts', Icons.inventory_2),
                _buildOverviewStat('Waves', '$activeWaves', Icons.waves),
                _buildOverviewStat('Orders', '$pendingOrders', Icons.shopping_cart),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Total Inventory Value',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatCurrency(totalValue),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'System Efficiency',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                  ),
                ),
                Text(
                  '${systemEfficiency.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewStat(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white70,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Module Statistics',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.8, // 🔥 FIX: Increased from 1.6 to 1.8 - NO OVERFLOW!
          children: [
            _buildStatCard('Inventory', '${_inventoryReports.length}', 
                Icons.inventory_2, Colors.blue),
            _buildStatCard('Storage', '${_storageReports.length}', 
                Icons.storage, AppColors.primaryPink),
            _buildStatCard('Picklist', '${_picklistReports.length}', 
                Icons.assignment, Colors.green),
            _buildStatCard('Loading', '${_loadingReports.length}', 
                Icons.local_shipping, Colors.orange),
            _buildStatCard('Movements', '${_movementReports.length}', 
                Icons.swap_horiz, Colors.purple),
            _buildStatCard('Low Stock', '${_dashboardStats['lowStockAlerts'] ?? 0}', 
                Icons.warning, Colors.red),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), // 🔥 FIX: Reduced padding
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withOpacity(0.8),
              color.withOpacity(0.6),
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min, // 🔥 FIX: Important!
          children: [
            Icon(icon, color: Colors.white, size: 24), // 🔥 FIX: Reduced from 28
            const SizedBox(height: 4), // 🔥 FIX: Reduced from 6
            Flexible( // 🔥 FIX: Wrapped in Flexible
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 20, // 🔥 FIX: Reduced from 24
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(height: 2), // 🔥 FIX: Reduced from 4
            Flexible( // 🔥 FIX: Wrapped in Flexible
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10, // 🔥 FIX: Reduced from 11
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Export Actions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _isExportingAnalytics ? null : _exportComprehensiveAnalytics,
          icon: _isExportingAnalytics
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : const Icon(Icons.analytics, size: 20),
          label: const Text('Export Comprehensive Analytics'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }

  // ================================
  // INVENTORY TAB
  // ================================

  Widget _buildInventoryTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '${_inventoryReports.length} Items',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isExportingInventory ? null : _exportInventoryReport,
                icon: _isExportingInventory
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download, size: 16),
                label: const Text('Export'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _inventoryReports.isEmpty
              ? _buildEmptyState('No inventory data available')
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _inventoryReports.length,
                  itemBuilder: (context, index) {
                    final item = _inventoryReports[index];
                    return _buildInventoryItem(item);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildInventoryItem(Map<String, dynamic> item) {
    final name = item['name'] ?? 'Unknown';
    final sku = item['sku'] ?? '';
    final category = item['category'] ?? '';
    final quantity = item['quantity'] ?? 0;
    final minStock = item['min_stock'] ?? 0;
    final unitPrice = item['unit_price'] ?? 0.0;
    final location = item['location'] ?? '';
    final isActive = item['is_active'] ?? true;
    final isLowStock = quantity <= minStock;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.inventory_2,
                    color: Colors.teal,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'SKU: $sku',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textLight,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isLowStock
                            ? Colors.red.withOpacity(0.1)
                            : Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Qty: $quantity',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isLowStock ? Colors.red : Colors.green,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (!isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Inactive',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (category.isNotEmpty)
                  _buildInfoChip(Icons.category, category),
                if (location.isNotEmpty)
                  _buildInfoChip(Icons.location_on, location),
                _buildInfoChip(Icons.currency_rupee, '₹${unitPrice.toStringAsFixed(2)}'),
                if (isLowStock)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning, size: 14, color: Colors.red),
                        SizedBox(width: 4),
                        Text(
                          'Low Stock',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textLight),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textLight,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ================================
  // STORAGE TAB
  // ================================

  Widget _buildStorageTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '${_storageReports.length} Entries',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isExportingStorage ? null : _exportStorageReport,
                icon: _isExportingStorage
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download, size: 16),
                label: const Text('Export'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _storageReports.isEmpty
              ? _buildEmptyState('No storage data available')
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _storageReports.length,
                  itemBuilder: (context, index) {
                    final item = _storageReports[index];
                    return _buildStorageItem(item);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStorageItem(Map<String, dynamic> item) {
    final itemName = item['item_name'] ?? item['description'] ?? 'Unknown';
    final itemNo = item['item_no'] ?? '';
    final barcode = item['barcode'] ?? '';
    final quantity = item['qty'] ?? 0;
    final location = item['location'] ?? '';
    final scannedBy = item['scanned_by'] ?? '';
    final dateAdded = item['date_added'] ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryPink.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.storage,
                    color: AppColors.primaryPink,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        itemName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (itemNo.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Item No: $itemNo',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textLight,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Qty: $quantity',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (barcode.isNotEmpty)
                  _buildInfoChip(Icons.qr_code, barcode),
                if (location.isNotEmpty)
                  _buildInfoChip(Icons.location_on, location),
                if (scannedBy.isNotEmpty)
                  _buildInfoChip(Icons.person, scannedBy),
                if (dateAdded.isNotEmpty && dateAdded.length >= 10)
                  _buildInfoChip(Icons.calendar_today, dateAdded.substring(0, 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ================================
  // PICKLIST TAB
  // ================================

  Widget _buildPicklistTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '${_picklistReports.length} Items',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isExportingPicklist ? null : _exportPicklistReport,
                icon: _isExportingPicklist
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download, size: 16),
                label: const Text('Export'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _picklistReports.isEmpty
              ? _buildEmptyState('No picklist data available')
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _picklistReports.length,
                  itemBuilder: (context, index) {
                    final item = _picklistReports[index];
                    return _buildPicklistItem(item);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPicklistItem(Map<String, dynamic> item) {
    final picklistId = item['picklist_id'] ?? '';
    final customerName = item['customer_name'] ?? 'Unknown';
    final itemName = item['item_name'] ?? 'Unknown';
    final quantity = item['quantity'] ?? 0;
    final status = item['status'] ?? '';
    final pickedBy = item['picked_by'] ?? '';

    Color statusColor = Colors.grey;
    if (status == 'completed') statusColor = Colors.green;
    if (status == 'pending') statusColor = Colors.orange;
    if (status == 'in_progress') statusColor = Colors.blue;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.assignment,
                    color: Colors.green,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customerName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        itemName,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textLight,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (picklistId.isNotEmpty)
                  _buildInfoChip(Icons.qr_code, _safeSubstring(picklistId, 0, 8)),
                _buildInfoChip(Icons.inventory_2, 'Qty: $quantity'),
                if (pickedBy.isNotEmpty)
                  _buildInfoChip(Icons.person, pickedBy),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ================================
  // LOADING TAB
  // ================================

  Widget _buildLoadingTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '${_loadingReports.length} Records',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isExportingLoading ? null : _exportLoadingReport,
                icon: _isExportingLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download, size: 16),
                label: const Text('Export'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingReports.isEmpty
              ? _buildEmptyState('No loading data available')
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _loadingReports.length,
                  itemBuilder: (context, index) {
                    final item = _loadingReports[index];
                    return _buildLoadingItem(item);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildLoadingItem(Map<String, dynamic> item) {
    final shipmentId = item['shipment_id'] ?? '';
    final truckPlate = item['truck_plate'] ?? 'Unknown';
    final cartonsLoaded = item['cartons_loaded'] ?? 0;
    final status = item['status'] ?? '';
    final loadedBy = item['loaded_by'] ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.local_shipping,
                    color: Colors.orange,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Truck: $truckPlate',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (shipmentId.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Shipment: ${_safeSubstring(shipmentId, 0, 8)}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textLight,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$cartonsLoaded Cartons',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (loadedBy.isNotEmpty)
                  _buildInfoChip(Icons.person, loadedBy),
                if (status.isNotEmpty)
                  _buildInfoChip(Icons.check_circle, status),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ================================
  // MOVEMENT TAB
  // ================================

  Widget _buildMovementTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '${_movementReports.length} Records',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isExportingMovement ? null : _exportMovementReport,
                icon: _isExportingMovement
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download, size: 16),
                label: const Text('Export'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _movementReports.isEmpty
              ? _buildEmptyState('No movement data available')
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _movementReports.length,
                  itemBuilder: (context, index) {
                    final item = _movementReports[index];
                    return _buildMovementItem(item);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMovementItem(Map<String, dynamic> item) {
    final itemName = item['item_name'] ?? 'Unknown';
    final movementType = item['movement_type'] ?? '';
    final quantityChanged = item['quantity_changed'] ?? 0;
    final previousQty = item['previous_quantity'] ?? 0;
    final newQty = item['new_quantity'] ?? 0;
    final createdBy = item['created_by'] ?? '';

    Color typeColor = Colors.grey;
    IconData typeIcon = Icons.swap_horiz;
    if (movementType == 'STORAGE_IN' || movementType == 'INITIAL_STOCK') {
      typeColor = Colors.green;
      typeIcon = Icons.add_circle;
    } else if (movementType == 'PICK') {
      typeColor = Colors.orange;
      typeIcon = Icons.remove_circle;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    typeIcon,
                    color: typeColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        itemName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        movementType.replaceAll('_', ' '),
                        style: TextStyle(
                          fontSize: 13,
                          color: typeColor,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    quantityChanged > 0 ? '+$quantityChanged' : '$quantityChanged',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: typeColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text(
                        'Previous',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textLight,
                        ),
                      ),
                      Text(
                        '$previousQty',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                    ],
                  ),
                  const Icon(Icons.arrow_forward, size: 16, color: AppColors.textLight),
                  Column(
                    children: [
                      const Text(
                        'New',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textLight,
                        ),
                      ),
                      Text(
                        '$newQty',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: typeColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (createdBy.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildInfoChip(Icons.person, createdBy),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ================================
  // EMPTY STATE
  // ================================

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 80,
            color: Colors.grey.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.textLight,
            ),
          ),
        ],
      ),
    );
  }
}
