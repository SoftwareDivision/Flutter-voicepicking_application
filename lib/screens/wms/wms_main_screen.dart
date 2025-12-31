// lib/screens/wms/wms_main_screen.dart

import 'package:flutter/material.dart';
import '../../utils/colors.dart';
import '../../widgets/gradient_button.dart';
import '../../services/warehouse_service.dart';
import 'inventory_management_screen.dart';
import 'picklist_management_screen.dart';
import 'storage_screen.dart';
import 'loading_screen.dart';

import 'packaging_screen.dart';
import 'shipment_orders_screen.dart'; // ✅ ADD THIS IMPORT

class WMSMainScreen extends StatefulWidget {
  final String userName;
  final String? warehouseName;

  const WMSMainScreen({
    super.key,
    required this.userName,
    this.warehouseName = 'Main Warehouse',
  });

  @override
  State<WMSMainScreen> createState() => _WMSMainScreenState();
}

class _WMSMainScreenState extends State<WMSMainScreen>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  Map<String, dynamic> _dashboardData = {};

  // Animation Controllers
  late AnimationController _fadeController;
  late AnimationController _staggerController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _staggerAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeWarehouse();
    _fetchDashboardStats();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _staggerController.dispose();
    super.dispose();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _staggerController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _staggerAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _staggerController, curve: Curves.easeOutBack),
    );
    _fadeController.forward();
    _staggerController.forward();
  }

  Future<void> _initializeWarehouse() async {
    try {
      debugPrint('🔄 [WMS] Initializing warehouse...');
      final warehouseId = await WarehouseService.ensureWarehouseIsSet();
      if (warehouseId != null) {
        debugPrint('✅ [WMS] Warehouse initialized: $warehouseId');
      } else {
        debugPrint('⚠️ [WMS] No active warehouse available');
        if (mounted) {
          setState(() {
            _errorMessage = 'No warehouse configured. Some features may not work.';
          });
        }
      }
    } catch (e) {
      debugPrint('❌ [WMS] Warehouse initialization failed: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Warehouse initialization warning: $e';
        });
      }
    }
  }

  Future<void> _fetchDashboardStats() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      final result = await WarehouseService.getDashboardStats();
      if (mounted) {
        if ((result['success'] ?? false) && result['data'] != null) {
          setState(() {
            _dashboardData = result['data'] as Map<String, dynamic>;
            _isLoading = false;
          });
        } else {
          setState(() {
            _dashboardData = result['data'] ?? {};
            _isLoading = false;
            _hasError = true;
            _errorMessage = result['error'] ?? 'Failed to load dashboard data';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = 'Failed to load dashboard: $e';
        });
      }
    }
  }

  void _navigateToModule(Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
    _fetchDashboardStats();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.backgroundGradient,
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: _isLoading
                ? _buildLoadingScreen()
                : _hasError
                    ? _buildErrorScreen()
                    : _buildMainContent(),
          ),
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
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryPink),
          ),
          SizedBox(height: 20),
          Text(
            'Loading WMS Dashboard...',
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
              'WMS Loading Failed',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textLight,
              ),
            ),
            const SizedBox(height: 24),
            GradientButton(
              text: 'Retry',
              icon: Icons.refresh,
              onPressed: _fetchDashboardStats,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to Voice Picking'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return Column(
      children: [
        _buildCompactHeader(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWelcomeSection(),
                const SizedBox(height: 16),
                _buildSystemStats(),
                const SizedBox(height: 20),
                _buildNavigationGrid(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.warehouse_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Warehouse Management',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${widget.warehouseName} • ${widget.userName}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textLight,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(right: 4),
                child: Material(
                  color: AppColors.primaryPink.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: _fetchDashboardStats,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      child: const Icon(
                        Icons.refresh,
                        color: AppColors.primaryPink,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
              Material(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    child: const Icon(
                      Icons.mic,
                      color: Colors.green,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeSection() {
    final lowStockAlerts = _dashboardData['lowStockAlerts'] ?? 0;
    return AnimatedBuilder(
      animation: _staggerAnimation,
      builder: (context, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome to WMS',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                foreground: Paint()
                  ..shader = AppColors.primaryGradient.createShader(
                    const Rect.fromLTWH(0.0, 0.0, 200.0, 70.0),
                  ),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            const Text(
              'Manage your warehouse operations efficiently',
              style: TextStyle(
                fontSize: 15,
                color: AppColors.textLight,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (lowStockAlerts > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.warning.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_outlined,
                      color: AppColors.warning,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$lowStockAlerts items have low stock',
                        style: const TextStyle(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildSystemStats() {
    final totalProducts = _dashboardData['totalProducts'] ?? 0;
    final activeWaves = _dashboardData['activeWaves'] ?? 0;
    final pendingOrders = _dashboardData['pendingOrders'] ?? 0;
    final systemEfficiency = _dashboardData['systemEfficiency'] ?? 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildStatItem(
            icon: Icons.inventory_2_outlined,
            label: 'Products',
            value: '$totalProducts',
            color: AppColors.primaryPink,
          ),
          _buildStatItem(
            icon: Icons.assignment_outlined,
            label: 'Waves',
            value: '$activeWaves',
            color: Colors.green,
          ),
          _buildStatItem(
            icon: Icons.shopping_cart_outlined,
            label: 'Orders',
            value: '$pendingOrders',
            color: Colors.orange,
          ),
          _buildStatItem(
            icon: Icons.speed_outlined,
            label: 'Efficiency',
            value: '${systemEfficiency.toStringAsFixed(1)}%',
            color: Colors.blue,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textLight,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationGrid() {
    final modules = [
      {
        'id': 'storage',
        'title': 'Storage',
        'subtitle': 'Warehouse Storage Management',
        'icon': Icons.storage_outlined,
        'color': AppColors.primaryPink,
        'screen': StorageScreen(userName: widget.userName),
      },
      {
        'id': 'inventory',
        'title': 'Inventory',
        'subtitle': 'Stock Management & Control',
        'icon': Icons.inventory_2_outlined,
        'color': Colors.blue,
        'screen': InventoryManagementScreen(userName: widget.userName),
      },
      {
        'id': 'picklist',
        'title': 'Picklist',
        'subtitle': 'Wave & Order Management',
        'icon': Icons.assignment_outlined,
        'color': Colors.green,
        'screen': PicklistManagementScreen(userName: widget.userName),
      },
      {
        'id': 'packaging',
        'title': 'Packaging',
        'subtitle': 'Pack & Label Operations',
        'icon': Icons.inventory_2,
        'color': Colors.purple,
        'screen': PackagingScreen(userName: widget.userName),
      },
      // ✅ ADD SHIPMENT ORDERS MODULE HERE
      {
        'id': 'shipments',
        'title': 'Shipments',
        'subtitle': 'Shipment Order Management',
        'icon': Icons.local_shipping,
        'color': Colors.deepOrange,
        'screen': ShipmentOrdersScreen(userName: widget.userName),
      },
      {
        'id': 'loading',
        'title': 'Loading',
        'subtitle': 'Loading Dock Operations',
        'icon': Icons.local_shipping_outlined,
        'color': Colors.orange,
        'screen': LoadingScreen(userName: widget.userName),
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'WMS Modules',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.25,
          ),
          itemCount: modules.length,
          itemBuilder: (context, index) {
            final module = modules[index];
            return _buildWMSCard(module: module);
          },
        ),
      ],
    );
  }

  Widget _buildWMSCard({required Map<String, dynamic> module}) {
    return GestureDetector(
      onTap: () => _navigateToModule(module['screen'] as Widget),
      child: Container(
        decoration: BoxDecoration(
          color: module['color'] as Color,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: (module['color'] as Color).withOpacity(0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _navigateToModule(module['screen'] as Widget),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Icon(
                          module['icon'] as IconData,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white70,
                        size: 13,
                      ),
                    ],
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          module['title'] as String,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          module['subtitle'] as String,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white70,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
