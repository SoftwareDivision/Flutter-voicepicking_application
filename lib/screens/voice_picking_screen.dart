// lib/screens/voice_picking_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';

import '../controllers/voice_picking_controller.dart';
import '../utils/colors.dart';
import 'login_screen.dart';
import 'wms/wms_main_screen.dart';
import 'wms/storage_screen.dart';
import 'wms/inventory_management_screen.dart';
import 'wms/picklist_management_screen.dart';
import 'wms/loading_screen.dart';
import 'wms/packaging_screen.dart';
import 'wms/shipment_orders_screen.dart';

import 'profile_screen.dart';
import 'voice_settings_screen.dart';

class VoicePickingScreen extends StatefulWidget {
  final String userName;

  const VoicePickingScreen({
    super.key,
    required this.userName,
  });

  @override
  State<VoicePickingScreen> createState() => _VoicePickingScreenState();
}

class _VoicePickingScreenState extends State<VoicePickingScreen>
    with TickerProviderStateMixin {
  // ================================
  // CONTROLLER AND UI STATE
  // ================================
  late VoicePickingController _controller;
  bool _isRefreshing = false;

  // Drawer state for WMS
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Animation Controllers
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late AnimationController _statusController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<Color?> _statusColorAnimation;

  // EDA51 Scanner Components
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();

  // ================================
  // INITIALIZATION
  // ================================
  @override
  void initState() {
    super.initState();
    _controller = VoicePickingController(userName: widget.userName);
    _initializeAnimations();
    _setupEDA51Scanner();
    _controller.addListener(_onControllerUpdate);
  }

  void _initializeAnimations() {
    try {
      _pulseController = AnimationController(
        duration: const Duration(milliseconds: 1200),
        vsync: this,
      );

      _fadeController = AnimationController(
        duration: const Duration(milliseconds: 800),
        vsync: this,
      );

      _statusController = AnimationController(
        duration: const Duration(milliseconds: 500),
        vsync: this,
      );

      _pulseAnimation = Tween<double>(
        begin: 1.0,
        end: 1.15,
      ).animate(CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ));

      _fadeAnimation = Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(CurvedAnimation(
        parent: _fadeController,
        curve: Curves.easeInOut,
      ));

      _statusColorAnimation = ColorTween(
        begin: AppColors.success,
        end: AppColors.primaryPink,
      ).animate(CurvedAnimation(
        parent: _statusController,
        curve: Curves.easeInOut,
      ));

      _fadeController.forward();
      _statusController.repeat(reverse: true);

      debugPrint('✅ Animations initialized successfully');
    } catch (e) {
      debugPrint('❌ Animation initialization error: $e');
    }
  }

  void _setupEDA51Scanner() {
    try {
      debugPrint('🔧 Setting up EDA51 scanner text field integration...');
      _barcodeController.addListener(() {
        String text = _barcodeController.text;
        debugPrint('📱 EDA51 Text field changed: $text');
      });
      debugPrint('✅ EDA51 scanner text field integration ready');
    } catch (e) {
      debugPrint('❌ EDA51 scanner setup error: $e');
      _showWarningMessage('EDA51 scanner setup failed');
    }
  }

  void _onControllerUpdate() {
    if (mounted) {
      setState(() {
        if (_controller.isListening) {
          _pulseController.repeat(reverse: true);
        } else {
          _pulseController.stop();
        }

        if (_controller.isWaitingForScan) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && _controller.isWaitingForScan) {
              _barcodeFocusNode.requestFocus();
            }
          });
        } else {
          _barcodeFocusNode.unfocus();
        }
      });
    }
  }

  // ================================
  // ENHANCED REFRESH FUNCTIONALITY
  // ================================
  Future<void> _refreshData() async {
    try {
      setState(() => _isRefreshing = true);
      debugPrint('🔄 Refreshing voice picking data...');

      await _controller.refreshPicklistData();
      final itemCount = _controller.pickingItems.length;

      if (itemCount > 0) {
        _showSuccessMessage('Data refreshed! $itemCount items assigned and ready.');
      } else {
        _showWarningMessage('No picking tasks assigned.');
      }

      debugPrint('✅ Voice picking data refreshed - $itemCount items');
    } catch (e) {
      debugPrint('❌ Refresh error: $e');
      _showErrorMessage('Failed to refresh data: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  // ================================
  // EDA51 SCANNER METHODS
  // ================================
  void _handleBarcodeInput(String scannedBarcode) {
    try {
      if (!_controller.isWaitingForScan || scannedBarcode.trim().isEmpty) return;

      _barcodeController.clear();
      _controller.handleBarcodeInput(scannedBarcode);
    } catch (e) {
      debugPrint('❌ Handle barcode input error: $e');
      _showErrorMessage('Failed to process scanned barcode: ${e.toString()}');
    }
  }

  // ================================
  // HANDS-FREE START/STOP FUNCTIONALITY
  // ================================
  void _handleStartStop() {
    try {
      if (_controller.currentState.name == 'idle') {
        debugPrint('🎯 Starting hands-free picking session');
        _controller.startPickingSession();
        _showSuccessMessage('Hands-free mode activated! Say "READY" to begin.');
      } else {
        debugPrint('⏹️ Stopping picking session');
        _controller.resetSession();
      }
    } catch (e) {
      debugPrint('❌ Start/Stop error: $e');
      _showErrorMessage('Failed to start/stop session: ${e.toString()}');
    }
  }

  // ================================
  // HANDS-FREE MICROPHONE BUTTON
  // ================================
  void _handleMicrophoneButtonTap() {
    try {
      HapticFeedback.lightImpact();

      if (!_controller.speechEnabled) {
        debugPrint('⚠️ Speech not enabled');
        _showErrorMessage('Voice services unavailable. Please restart the app.');
        return;
      }

      if (_controller.currentState.name == 'idle') {
        debugPrint('🎤 Starting hands-free picking session...');
        _controller.startPickingSession();
        _showSuccessMessage('Hands-free mode activated! Say "READY" to begin.');
      } else if (_controller.isHandsFreeModeActive) {
        _showSuccessMessage('Hands-free mode is active. Just speak your commands.');
      } else {
        _showWarningMessage('Session is active. Use voice commands or reset to restart.');
      }
    } catch (e) {
      debugPrint('❌ Microphone button error: $e');
      _showErrorMessage('Microphone error: ${e.toString()}');
    }
  }

  // Open WMS Drawer
  void _openWMSDrawer() {
    _scaffoldKey.currentState?.openEndDrawer();
  }

  // ================================
  // NAVIGATION METHODS - FIXED
  // ================================
  void _navigateToWMSDashboard() async {
    try {
      HapticFeedback.lightImpact();
      Navigator.pop(context); // Close drawer
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => WMSMainScreen(userName: widget.userName),
        ),
      );
      if (mounted) {
        debugPrint('🔄 Returned from WMS Dashboard, refreshing data...');
        _refreshData();
      }
    } catch (e) {
      debugPrint('❌ WMS Dashboard navigation error: $e');
      _showErrorMessage('Failed to navigate to WMS Dashboard: ${e.toString()}');
    }
  }

  void _navigateToStorage() async {
    try {
      HapticFeedback.lightImpact();
      Navigator.pop(context); // Close drawer
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => StorageScreen(userName: widget.userName),
        ),
      );
      if (mounted) {
        debugPrint('🔄 Returned from Storage Screen, refreshing data...');
        _refreshData();
      }
    } catch (e) {
      debugPrint('❌ Storage Screen navigation error: $e');
      _showErrorMessage('Failed to navigate to Storage: ${e.toString()}');
    }
  }

  void _navigateToInventory() async {
    try {
      HapticFeedback.lightImpact();
      Navigator.pop(context); // Close drawer
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => InventoryManagementScreen(userName: widget.userName),
        ),
      );
      if (mounted) {
        debugPrint('🔄 Returned from Inventory Management, refreshing data...');
        _refreshData();
      }
    } catch (e) {
      debugPrint('❌ Inventory Management navigation error: $e');
      _showErrorMessage('Failed to navigate to Inventory: ${e.toString()}');
    }
  }

  void _navigateToPicklist() async {
    try {
      HapticFeedback.lightImpact();
      Navigator.pop(context); // Close drawer
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PicklistManagementScreen(userName: widget.userName),
        ),
      );
      if (mounted) {
        debugPrint('🔄 Returned from Picklist Management, refreshing data...');
        _refreshData();
      }
    } catch (e) {
      debugPrint('❌ Picklist Management navigation error: $e');
      _showErrorMessage('Failed to navigate to Picklist: ${e.toString()}');
    }
  }

  void _navigateToShipment() async {
    try {
      HapticFeedback.lightImpact();
      Navigator.pop(context); // Close drawer
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ShipmentOrdersScreen(userName: widget.userName),
        ),
      );
      if (mounted) {
        debugPrint('🔄 Returned from Shipment Orders, refreshing data...');
        _refreshData();
      }
    } catch (e) {
      debugPrint('❌ Shipment Orders navigation error: $e');
      _showErrorMessage('Failed to navigate to Shipment Orders: ${e.toString()}');
    }
  }

  void _navigateToLoading() async {
    try {
      HapticFeedback.lightImpact();
      Navigator.pop(context); // Close drawer
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => LoadingScreen(userName: widget.userName),
        ),
      );
      if (mounted) {
        debugPrint('🔄 Returned from Loading Screen, refreshing data...');
        _refreshData();
      }
    } catch (e) {
      debugPrint('❌ Loading Screen navigation error: $e');
      _showErrorMessage('Failed to navigate to Loading: ${e.toString()}');
    }
  }

  void _navigateToPackaging() async {
    try {
      HapticFeedback.lightImpact();
      Navigator.pop(context); // Close drawer
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PackagingScreen(userName: widget.userName),
        ),
      );
      if (mounted) {
        debugPrint('🔄 Returned from Packaging Screen, refreshing data...');
        _refreshData();
      }
    } catch (e) {
      debugPrint('❌ Packaging Screen navigation error: $e');
      _showErrorMessage('Failed to navigate to Packaging: ${e.toString()}');
    }
  }



  // ================================
  // UI BUILD METHODS
  // ================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      // Right-side drawer for WMS
      endDrawer: _buildWMSDrawer(),
      body: GestureDetector(
        // Swipe from right edge to open WMS
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity! < -500) {
            // Swipe left (from right edge)
            _openWMSDrawer();
          }
        },
        child: Container(
          decoration: const BoxDecoration(
            gradient: AppColors.backgroundGradient,
          ),
          child: SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          _buildSystemStatus(),
                          const SizedBox(height: 8),
                          _buildEDA51ScannerField(),
                          const SizedBox(height: 8),
                          _buildCurrentItemDisplay(),
                          const SizedBox(height: 8),
                          _buildVoiceControlCenter(),
                          const SizedBox(height: 16),
                          _buildQuickActions(),
                          const SizedBox(height: 20),
                        ],
                      ),
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

  // ================================
  // WMS RIGHT-SIDE DRAWER - FIXED NAVIGATION
  // ================================
  Widget _buildWMSDrawer() {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.75,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primaryPink.withOpacity(0.05),
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Drawer Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryPink.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.warehouse_rounded,
                            color: AppColors.primaryPink,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Warehouse Management',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                widget.userName,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // WMS Options - FIXED NAVIGATION
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildWMSMenuItem(
                      icon: Icons.dashboard_rounded,
                      title: 'WMS Dashboard',
                      subtitle: 'View warehouse overview',
                      onTap: _navigateToWMSDashboard,
                    ),
                    const SizedBox(height: 12),
                    _buildWMSMenuItem(
                      icon: Icons.storage_rounded,
                      title: 'Storage',
                      subtitle: 'Warehouse storage management',
                      onTap: _navigateToStorage,
                    ),
                    const SizedBox(height: 12),
                    _buildWMSMenuItem(
                      icon: Icons.inventory_2_rounded,
                      title: 'Inventory Management',
                      subtitle: 'Manage stock levels',
                      onTap: _navigateToInventory,
                    ),
                    const SizedBox(height: 12),
                    _buildWMSMenuItem(
                      icon: Icons.list_alt_rounded,
                      title: 'Picklist Management',
                      subtitle: 'View picking tasks',
                      onTap: _navigateToPicklist,
                    ),
                    const SizedBox(height: 12),
                    _buildWMSMenuItem(
                      icon: Icons.inventory_rounded,
                      title: 'Packaging',
                      subtitle: 'Package & prepare orders',
                      onTap: _navigateToPackaging,
                    ),
                    const SizedBox(height: 12),
                    _buildWMSMenuItem(
                      icon: Icons.description_rounded,
                      title: 'Shipment Orders',
                      subtitle: 'Manage shipment orders',
                      onTap: _navigateToShipment,
                    ),
                    const SizedBox(height: 12),
                    _buildWMSMenuItem(
                      icon: Icons.local_shipping_rounded,
                      title: 'Loading',
                      subtitle: 'Load cartons onto trucks',
                      onTap: _navigateToLoading,
                    ),
                  ],
                ),
              ),

              // Bottom info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.swipe, color: Colors.grey.shade600, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Swipe from right edge to open WMS',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
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

  Widget _buildWMSMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primaryPink.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: AppColors.primaryPink,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textLight,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================================
  // ENHANCED HEADER - FIXED OVERFLOW AT LINE 583
  // ================================
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icon Container
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.headset_mic_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          
          // FIXED: Expanded with proper constraints to prevent overflow
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title Row with HANDS-FREE badge - FIXED OVERFLOW
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Flexible(
                      child: Text(
                        'Voice Picking',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    if (_controller.isHandsFreeModeActive) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'HANDS-FREE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                // Subtitle with proper overflow handling
                Text(
                  'Welcome, ${widget.userName} • ${_controller.pickingItems.length} items',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textLight,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          
          const SizedBox(width: 8),
          
          // Action buttons with proper sizing
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Refresh Button
              _buildHeaderIconButton(
                icon: _isRefreshing ? null : Icons.refresh_rounded,
                onTap: _isRefreshing ? null : _refreshData,
                color: AppColors.primaryPink,
                isLoading: _isRefreshing,
              ),
              const SizedBox(width: 6),
              
              // WMS Access Button
              _buildHeaderIconButton(
                icon: Icons.warehouse_rounded,
                onTap: _openWMSDrawer,
                color: AppColors.primaryPink,
              ),
              const SizedBox(width: 6),
              
              // Logout Button
              _buildHeaderIconButton(
                icon: Icons.logout,
                onTap: _handleLogout,
                color: AppColors.error,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Helper method for header icon buttons
  Widget _buildHeaderIconButton({
    IconData? icon,
    required VoidCallback? onTap,
    required Color color,
    bool isLoading = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: color.withOpacity(0.3),
            ),
          ),
          child: isLoading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              : Icon(
                  icon,
                  color: color,
                  size: 16,
                ),
        ),
      ),
    );
  }

  Widget _buildSystemStatus() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              AnimatedBuilder(
                animation: _statusColorAnimation,
                builder: (context, child) {
                  return Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _statusColorAnimation.value ?? _getStatusColor(),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (_statusColorAnimation.value ?? _getStatusColor())
                              .withOpacity(0.5),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              const Text(
                'System Status',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textLight,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                _getStatusText(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _getStatusColor(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.lightPink.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: AppColors.primaryPink.withOpacity(0.2),
              ),
            ),
            child: Text(
              'Last: ${_controller.lastInstruction}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.primaryPink,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEDA51ScannerField() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _controller.isWaitingForScan
            ? AppColors.primaryPink.withOpacity(0.1)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _controller.isWaitingForScan
              ? AppColors.primaryPink
              : Colors.grey.shade300,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.qr_code_scanner,
                color: _controller.isWaitingForScan
                    ? AppColors.primaryPink
                    : Colors.grey.shade600,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _controller.isWaitingForScan
                      ? 'Press EDA51 side button to scan'
                      : 'EDA51 Scanner Ready',
                  style: TextStyle(
                    color: _controller.isWaitingForScan
                        ? AppColors.primaryPink
                        : Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _barcodeController,
            focusNode: _barcodeFocusNode,
            enabled: true,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              labelText: 'EDA51 Barcode Scanner',
              labelStyle: const TextStyle(fontSize: 12),
              hintText: _controller.isWaitingForScan
                  ? 'Press EDA51 side button...'
                  : 'Scan will appear here',
              hintStyle: const TextStyle(fontSize: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              prefixIcon: const Icon(Icons.qr_code, size: 18),
              suffixIcon: _barcodeController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => _barcodeController.clear(),
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              isDense: true,
            ),
            onChanged: (value) {
              debugPrint('📱 EDA51 Input changed: $value');
              if (value.contains('\n') || value.contains('\r')) {
                String cleanBarcode = value.trim();
                if (cleanBarcode.isNotEmpty && _controller.isWaitingForScan) {
                  _handleBarcodeInput(cleanBarcode);
                }
              }
            },
            onSubmitted: (value) {
              debugPrint('📱 EDA51 Input submitted: $value');
              if (value.isNotEmpty && _controller.isWaitingForScan) {
                _handleBarcodeInput(value);
              }
            },
          ),
          const SizedBox(height: 6),
          Text(
            _controller.isWaitingForScan
                ? '1. Press EDA51 side scan button\n2. Barcode will appear above automatically'
                : 'Scanner ready for next item',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade600,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentItemDisplay() {
    if (_controller.currentItemDetails == null ||
        _controller.currentState.name == 'idle') {
      return const SizedBox.shrink();
    }

    final currentItem = _controller.currentItemDetails!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.inventory_2,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Item ${_controller.currentItemIndex + 1} of ${_controller.pickingItems.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textLight,
                      ),
                    ),
                    Text(
                      currentItem['item_name'] ?? 'Unknown Item',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildItemInfoCard(
                'Location',
                currentItem['location'] ?? 'N/A',
                Icons.place_outlined,
                AppColors.primaryPink,
              ),
              const SizedBox(width: 8),
              _buildItemInfoCard(
                'Assigned',
                '${currentItem['quantity_requested'] ?? 0}',
                Icons.assignment_outlined,
                Colors.blue,
              ),
              const SizedBox(width: 8),
              _buildItemInfoCard(
                'SKU',
                currentItem['sku'] ?? 'N/A',
                Icons.qr_code_outlined,
                Colors.green,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemInfoCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: color.withOpacity(0.3),
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: color,
              size: 14,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                color: color.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ================================
  // HANDS-FREE VOICE CONTROL CENTER
  // ================================
  Widget _buildVoiceControlCenter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryPink.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Voice Control Center',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              if (_controller.isHandsFreeModeActive) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'HANDS-FREE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _handleMicrophoneButtonTap,
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _controller.isListening ? _pulseAnimation.value : 1.0,
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      gradient: _controller.isListening ||
                              _controller.currentState.name != 'idle'
                          ? AppColors.primaryGradient
                          : LinearGradient(
                              colors: [
                                AppColors.primaryPink.withOpacity(0.3),
                                AppColors.primaryPink.withOpacity(0.5),
                              ],
                            ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryPink.withOpacity(
                              _controller.isListening ? 0.5 : 0.2),
                          blurRadius: _controller.isListening ? 20 : 8,
                          spreadRadius: _controller.isListening ? 5 : 0,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          _getMicrophoneIcon(),
                          size: 36,
                          color: Colors.white,
                        ),
                        if (_controller.isHandsFreeModeActive)
                          Positioned(
                            top: 10,
                            right: 10,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: AppColors.success,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _getMicrophoneButtonText(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textLight,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (_controller.isListening) ...[
            const SizedBox(height: 10),
            Column(
              children: [
                Text(
                  'Listening... ${(_controller.soundLevel * 100).toInt()}%',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.primaryPink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: _controller.soundLevel.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_controller.userInput.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppColors.success.withOpacity(0.3),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'You said: "${_controller.userInput}"',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                  ),
                  if (_controller.originalVoiceInput.isNotEmpty &&
                      _controller.originalVoiceInput != _controller.userInput) ...[
                    const SizedBox(height: 3),
                    Text(
                      'Original: "${_controller.originalVoiceInput}"',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textLight,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ================================
  // BIGGER QUICK ACTIONS (2x2 GRID)
  // ================================
  Widget _buildQuickActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 16),
          // Row 1: Start + Reset (2 buttons)
          Row(
            children: [
              Expanded(
                child: _buildBigQuickActionButton(
                  icon: _controller.currentState.name == 'idle'
                      ? Icons.play_arrow_rounded
                      : Icons.stop_rounded,
                  label: _controller.currentState.name == 'idle'
                      ? 'Start Session'
                      : 'Stop Session',
                  onTap: _handleStartStop,
                  color: _controller.currentState.name == 'idle'
                      ? AppColors.success
                      : AppColors.error,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildBigQuickActionButton(
                  icon: Icons.refresh_rounded,
                  label: 'Reset Session',
                  onTap: _controller.currentState.name != 'idle'
                      ? _controller.resetSession
                      : null,
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Row 2: Settings + Profile (2 buttons)
          Row(
            children: [
              Expanded(
                child: _buildBigQuickActionButton(
                  icon: Icons.settings_rounded,
                  label: 'Voice Settings',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => VoiceSettingsScreen(
                          userName: widget.userName,
                          onSettingsChanged: () {
                            _controller.updateVoiceSettings();
                          },
                        ),
                      ),
                    );
                  },
                  color: AppColors.primaryPink,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildBigQuickActionButton(
                  icon: Icons.person_rounded,
                  label: 'My Profile',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProfileScreen(
                          userName: widget.userName,
                        ),
                      ),
                    );
                  },
                  color: Colors.blue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBigQuickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required Color color,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            gradient: onTap != null
                ? LinearGradient(
                    colors: [
                      color.withOpacity(0.15),
                      color.withOpacity(0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: onTap == null ? Colors.grey.shade100 : null,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: onTap != null ? color.withOpacity(0.4) : Colors.grey.shade300,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: onTap != null ? color.withOpacity(0.2) : Colors.grey.shade200,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: onTap != null ? color : Colors.grey.shade400,
                  size: 28,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: onTap != null ? color : Colors.grey.shade400,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================================
  // HELPER METHODS
  // ================================
  Color _getStatusColor() {
    switch (_controller.voiceStatus.name) {
      case 'listening':
        return AppColors.success;
      case 'processing':
      case 'retrying':
        return AppColors.warning;
      case 'error':
        return AppColors.error;
      default:
        return _controller.speechEnabled ? AppColors.primaryPink : AppColors.error;
    }
  }

  String _getStatusText() {
    if (!_controller.isDataLoaded) return 'LOADING';
    if (!_controller.speechEnabled) return 'ERROR';

    if (_controller.isHandsFreeModeActive) {
      switch (_controller.voiceStatus.name) {
        case 'listening':
          return 'HANDS-FREE LISTENING';
        case 'processing':
          return 'HANDS-FREE PROCESSING';
        default:
          return 'HANDS-FREE ACTIVE';
      }
    }

    switch (_controller.voiceStatus.name) {
      case 'initializing':
        return 'STARTING';
      case 'listening':
        return 'LISTENING';
      case 'processing':
        return 'PROCESSING';
      case 'retrying':
        return 'RETRYING';
      case 'error':
        return 'ERROR';
      default:
        switch (_controller.currentState.name) {
          case 'idle':
            return 'READY';
          case 'ready':
          case 'readyWait':
            return 'WAITING';
          case 'locationCheck':
            return 'LOCATION';
          case 'itemCheck':
            return 'ITEM CHECK';
          case 'barcodeScanning':
            return _controller.isWaitingForScan ? 'SCANNING' : 'SCANNED';
          case 'completed':
            return 'COMPLETED';
          default:
            return 'IDLE';
        }
    }
  }

  IconData _getMicrophoneIcon() {
    if (_controller.isListening) return Icons.mic;
    if (_controller.isProcessing) return Icons.psychology;
    return Icons.mic_none_rounded;
  }

  String _getMicrophoneButtonText() {
    if (!_controller.isSystemReady) return 'System Initializing...';
    if (!_controller.speechEnabled) return 'Voice Not Available';
    if (_controller.isWaitingForScan) return 'Waiting for EDA51 Scanner...';

    switch (_controller.voiceStatus.name) {
      case 'initializing':
        return 'Initializing Voice Services...';
      case 'listening':
        return _controller.isHandsFreeModeActive
            ? 'Hands-Free Mode Active...'
            : 'Listening for Your Command...';
      case 'processing':
        return 'Processing Your Command...';
      case 'retrying':
        return 'Retrying Voice Recognition...';
      case 'error':
        return 'Voice Error - Tap to Retry';
      default:
        if (_controller.currentState.name == 'idle') {
          return 'Tap Once to Start Hands-Free Mode';
        } else if (_controller.isHandsFreeModeActive) {
          return 'Hands-Free Mode Active';
        } else {
          return 'Tap for Voice Input';
        }
    }
  }

  // ================================
  // MESSAGE DISPLAY METHODS
  // ================================
  void _showSuccessMessage(String message) {
    if (mounted) {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  void _showWarningMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  void _showErrorMessage(String message) {
    if (mounted) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(fontSize: 14),
          ),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: Colors.white70,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
    }
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Row(
          children: [
            Icon(Icons.logout, color: AppColors.warning, size: 22),
            SizedBox(width: 10),
            Text('Logout', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to logout?',
              style: TextStyle(fontSize: 15),
            ),
            if (_controller.currentState.name != 'idle' &&
                _controller.currentState.name != 'completed') ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _controller.isHandsFreeModeActive
                      ? 'Warning: Active hands-free picking session will be lost!'
                      : 'Warning: Active picking session will be lost!',
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(fontSize: 14)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _performLogout();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout', style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }

  void _performLogout() {
    try {
      debugPrint('🚪 Performing logout...');
      _barcodeController.clear();
      _barcodeFocusNode.unfocus();

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
      debugPrint('✅ Logout completed successfully');
    } catch (e) {
      debugPrint('❌ Logout error: $e');
      _showErrorMessage('Logout failed: ${e.toString()}');
    }
  }

  // ================================
  // DISPOSE
  // ================================
  @override
  void dispose() {
    try {
      debugPrint('🧹 Disposing voice picking screen...');
      _pulseController.dispose();
      _fadeController.dispose();
      _statusController.dispose();
      _barcodeController.dispose();
      _barcodeFocusNode.dispose();
      _controller.dispose();
      debugPrint('✅ Voice picking screen disposed successfully');
    } catch (e) {
      debugPrint('❌ Dispose error: $e');
    }
    super.dispose();
  }
}
