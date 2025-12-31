// lib/screens/wms/shipment_orders_screen.dart
// ✅ PRODUCTION READY v4.0 - ALL FIXES APPLIED
// Fixed: Delete (real), MSO (no route check), Edit, Refresh, PDF download (real), Loading navigation

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../utils/colors.dart';
import '../../services/shipment_service.dart';
import '../../utils/shipment_validation.dart';
import '../../utils/shipment_slip_generator.dart';
import 'loading_screen.dart'; // ✅ ADDED: Import loading screen
import 'dart:developer';

class ShipmentOrdersScreen extends StatefulWidget {
  final String userName;

  const ShipmentOrdersScreen({
    super.key,
    required this.userName,
  });

  @override
  State<ShipmentOrdersScreen> createState() => _ShipmentOrdersScreenState();
}

class _ShipmentOrdersScreenState extends State<ShipmentOrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  List<ShipmentOrder> _draftShipments = [];
  List<ShipmentOrder> _pendingShipments = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ✅ FIXED: Always force refresh from server
  Future<void> _loadAllData({bool forceRefresh = true}) async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    try {
      log('🔄 Loading all shipment data (force: $forceRefresh)...');
      
      final results = await Future.wait([
        ShipmentService.getDraftShipments(forceRefresh: forceRefresh),
        ShipmentService.getPendingDispatchShipments(forceRefresh: forceRefresh),
      ]);
      
      if (mounted) {
        setState(() {
          _draftShipments = results[0];
          _pendingShipments = results[1];
          _isLoading = false;
        });
        
        log('✅ Loaded: ${_draftShipments.length} drafts, ${_pendingShipments.length} pending');
      }
    } catch (e) {
      log('❌ Error loading shipments: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        _showSafeSnackBar('Failed to load shipments: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundGrey,
      appBar: AppBar(
        title: const Text(
          'Shipment Orders',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // ✅ ADDED: Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _loadAllData(forceRefresh: true);
              if (mounted) {
                _showSafeSnackBar('✅ Refreshed successfully!');
              }
            },
            tooltip: 'Refresh All',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(
              text: 'Draft (${_draftShipments.length})',
              icon: const Icon(Icons.drafts, size: 20),
            ),
            Tab(
              text: 'Completed (${_pendingShipments.length})',
              icon: const Icon(Icons.schedule, size: 20),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildDraftTab(),
                _buildPendingTab(),
              ],
            ),
    );
  }

  // ================================
  // DRAFT TAB
  // ================================

  Widget _buildDraftTab() {
    if (_draftShipments.isEmpty) {
      return _buildEmptyState(
        icon: Icons.inventory_2_outlined,
        message: 'No Draft Shipments',
        subtitle: 'Packaging completion will automatically create draft shipment orders here',
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadAllData(forceRefresh: true),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _draftShipments.length,
        itemBuilder: (context, index) {
          final shipment = _draftShipments[index];
          return _buildDraftCard(shipment);
        },
      ),
    );
  }

  Widget _buildDraftCard(ShipmentOrder shipment) {
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shipment.customerName ?? 'Unknown Customer',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        shipment.orderNumber ?? shipment.shipmentId,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit, size: 16, color: Colors.orange.shade700),
                      const SizedBox(width: 4),
                      Text(
                        'DRAFT',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _buildInfoChip(
                  Icons.inventory_2,
                  '${shipment.totalCartons} Cartons',
                  Colors.blue,
                ),
                _buildInfoChip(
                  Icons.place,
                  shipment.destination?.split(',').first ?? 'N/A',
                  Colors.green,
                ),
                _buildInfoChip(
                  Icons.access_time,
                  _formatTime(shipment.createdAt),
                  Colors.grey,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // ✅ ADDED: View Items button
                IconButton(
                  onPressed: () => _showShipmentItemsDialog(shipment),
                  icon: const Icon(Icons.list_alt, size: 20),
                  tooltip: 'View Cartons',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.blue.shade50,
                    foregroundColor: Colors.blue.shade700,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showShipmentTypeSelectionDialog(shipment),
                    icon: const Icon(Icons.settings, size: 18),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Configure'),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _confirmDeleteShipment(shipment),
                  icon: const Icon(Icons.delete, size: 18),
                  label: const Text('Delete'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ================================
  // ✅ FIXED: DELETE WITH REAL DATABASE DELETE
  // ================================

  void _confirmDeleteShipment(ShipmentOrder shipment) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning, color: Colors.red),
            const SizedBox(width: 12),
            const Text('Delete Shipment?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete:\n'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Shipment: ${shipment.shipmentId}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('Customer: ${shipment.customerName}'),
                  Text('Cartons: ${shipment.totalCartons}'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '⚠️ This action cannot be undone!',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _performDelete(shipment);
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

  Future<void> _performDelete(ShipmentOrder shipment) async {
    if (!mounted) return;
    
    // ✅ Show loading
    _showLoadingDialog('Deleting shipment...');
    
    try {
      log('🗑️ Attempting to delete: ${shipment.id}');
      
      // ✅ REAL DELETE from database
      final result = await ShipmentService.deleteDraftShipment(
        shipmentOrderId: shipment.id,
      );
      
      if (mounted) {
        Navigator.pop(context); // Close loading
      }
      
      if (result['success']) {
        // ✅ Force refresh to get updated list
        await _loadAllData(forceRefresh: true);
        
        if (mounted) {
          _showSafeSnackBar('✅ Shipment deleted successfully!');
        }
        
        log('✅ Delete successful');
      } else {
        if (mounted) {
          _showSafeDialog(
            title: 'Delete Failed',
            message: result['message'] ?? 'Unknown error occurred',
            isError: true,
          );
        }
        log('❌ Delete failed: ${result['message']}');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading
        _showSafeDialog(
          title: 'Error',
          message: 'Failed to delete: ${e.toString()}',
          isError: true,
        );
      }
      log('❌ Delete error: $e');
    }
  }

  // ================================
  // SO/MSO SELECTION
  // ================================

  void _showShipmentTypeSelectionDialog(ShipmentOrder shipment) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.help_outline, color: Colors.deepOrange),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Choose Shipment Type',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Current: ${shipment.customerName}\n${shipment.totalCartons} cartons',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildShipmentTypeOption(
              icon: Icons.person,
              title: 'Single Customer (SO)',
              subtitle: 'One customer, direct delivery',
              color: Colors.green,
              onTap: () {
                Navigator.pop(dialogContext);
                if (mounted) {
                  _showConfigureDialog(shipment, isSingleCustomer: true);
                }
              },
            ),
            const SizedBox(height: 16),
            _buildShipmentTypeOption(
              icon: Icons.group,
              title: 'Multi-Customer (MSO)',
              subtitle: 'Consolidate multiple orders',
              color: Colors.purple,
              onTap: () {
                Navigator.pop(dialogContext);
                if (mounted) {
                  _showCompatibleShipmentsDialog(shipment);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildShipmentTypeOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 20),
          ],
        ),
      ),
    );
  }

  // ================================
  // ✅ FIXED: MSO - NO ROUTE OPTIMIZATION CHECK
  // ================================

  void _showCompatibleShipmentsDialog(ShipmentOrder primaryShipment) {
    if (!mounted) return;

    // ✅ FIX: Show ALL other draft shipments (NO route/destination check)
    final availableShipments = _draftShipments
        .where((s) => s.id != primaryShipment.id) // Exclude primary only
        .toList();

    if (availableShipments.isEmpty) {
      _showSafeDialog(
        title: 'No Other Shipments',
        message: 'No other draft shipments available to consolidate.',
        isError: true,
      );
      return;
    }

    final selected = <String>{};

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.merge_type, color: Colors.purple),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Select Shipments to Consolidate',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Primary Shipment Info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.purple.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.purple.shade700, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '📌 Primary: ${primaryShipment.customerName} (${primaryShipment.totalCartons} cartons)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.purple.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Select additional shipments (${availableShipments.length} available)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  // ✅ FIX: Show ALL available shipments
                  Expanded(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: availableShipments.length,
                      itemBuilder: (context, index) {
                        final shipment = availableShipments[index];
                        final isSelected = selected.contains(shipment.id);
                        
                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: (value) {
                            setDialogState(() {
                              if (value == true) {
                                selected.add(shipment.id);
                              } else {
                                selected.remove(shipment.id);
                              }
                            });
                          },
                          title: Text(
                            shipment.customerName ?? 'Unknown',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          subtitle: Text(
                            '${shipment.shipmentId} • ${shipment.totalCartons} cartons\n📍 ${shipment.destination ?? "N/A"}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          activeColor: Colors.purple,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Selected:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${selected.length + 1} shipments', // +1 for primary
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepOrange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: selected.isEmpty
                    ? null
                    : () {
                        Navigator.pop(dialogContext);
                        if (mounted) {
                          final allSelectedIds = [primaryShipment.id, ...selected];
                          _createMultiCustomerShipment(allSelectedIds);
                        }
                      },
                icon: const Icon(Icons.check),
                label: const Text('Continue'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createMultiCustomerShipment(List<String> shipmentIds) async {
    if (!mounted) return;
    _showLoadingDialog('Creating Multi-Customer Shipment...');

    try {
      log('🔄 Creating MSO with ${shipmentIds.length} shipments');
      
      // Note: Update this based on your service implementation
      final result = await ShipmentService.createMultiCustomerShipment(
        packagingSessionIds: shipmentIds, // Adjust if needed
        userName: widget.userName,
      );

      if (mounted) {
        Navigator.pop(context); // Close loading
      }

      if (result['success']) {
        await _loadAllData(forceRefresh: true);
        
        if (mounted) {
          _showSafeDialog(
            title: 'MSO Created!',
            message: 'Multi-Customer Shipment ${result['shipment_id']} created successfully!\n\n'
                '• ${result['customer_count']} customers\n'
                '• ${result['total_cartons']} total cartons',
            isError: false,
          );
        }
      } else {
        if (mounted) {
          _showSafeDialog(
            title: 'Creation Failed',
            message: result['message'],
            isError: true,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showSafeDialog(
          title: 'Error',
          message: e.toString(),
          isError: true,
        );
      }
    }
  }

  // ================================
  // CONFIGURE DIALOG
  // ================================

  void _showConfigureDialog(ShipmentOrder shipment, {required bool isSingleCustomer}) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ConfigureShipmentDialog(
        shipment: shipment,
        userName: widget.userName,
        isSingleCustomer: isSingleCustomer,
        onConfigured: () async {
          if (mounted) {
            await _loadAllData(forceRefresh: true);
            _showSafeSnackBar('✅ Shipment configured successfully!');
          }
        },
      ),
    );
  }

  // ================================
  // PENDING TAB
  // ================================

  Widget _buildPendingTab() {
    if (_pendingShipments.isEmpty) {
      return _buildEmptyState(
        icon: Icons.local_shipping_outlined,
        message: 'No Pending Shipments',
        subtitle: 'Configured shipments ready for dispatch will appear here',
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadAllData(forceRefresh: true),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _pendingShipments.length,
        itemBuilder: (context, index) {
          final shipment = _pendingShipments[index];
          return _buildPendingCard(shipment);
        },
      ),
    );
  }

  Widget _buildPendingCard(ShipmentOrder shipment) {
    final truckNumber = shipment.truckDetails?['truckNumber'] ?? 'N/A';
    final loadingStrategy = _getLoadingStrategyDisplay(shipment.loadingStrategy);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Section with Gradient - COMPACT
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: shipment.orderType == 'multi'
                    ? [Colors.purple.shade400, Colors.purple.shade600]
                    : [Colors.blue.shade400, Colors.blue.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (shipment.orderType == 'multi')
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white, width: 1),
                              ),
                              child: const Text(
                                'MSO',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          Expanded(
                            child: Text(
                              shipment.customerName ?? 'Unknown Customer',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          shipment.shipmentId,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _getShipmentTypeIcon(shipment.shipmentType!),
              ],
            ),
          ),
          
          // Details Section - COMPACT
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Destination
                _buildModernDetailRow(
                  icon: Icons.location_on,
                  iconColor: Colors.red.shade400,
                  label: 'Destination',
                  value: shipment.destination ?? 'Not specified',
                ),
                const SizedBox(height: 8),
                
                // Truck/Courier Info
                if (shipment.shipmentType == ShipmentType.truck) ...[
                  _buildModernDetailRow(
                    icon: Icons.local_shipping,
                    iconColor: Colors.blue.shade400,
                    label: 'Truck Number',
                    value: truckNumber,
                  ),
                  const SizedBox(height: 8),
                  _buildModernDetailRow(
                    icon: Icons.swap_vert,
                    iconColor: Colors.orange.shade400,
                    label: 'Loading Strategy',
                    value: loadingStrategy,
                  ),
                ] else if (shipment.shipmentType == ShipmentType.courier) ...[
                  _buildModernDetailRow(
                    icon: Icons.flight,
                    iconColor: Colors.purple.shade400,
                    label: 'Courier',
                    value: shipment.courierDetails?['courierName'] ?? 'N/A',
                  ),
                ],
                const SizedBox(height: 8),
                
                // Cartons Count
                _buildModernDetailRow(
                  icon: Icons.inventory_2,
                  iconColor: Colors.green.shade400,
                  label: 'Total Cartons',
                  value: '${shipment.totalCartons}',
                ),
                
                const SizedBox(height: 12),
                
                // Action Buttons - COMPACT
                Row(
                  children: [
                    // Delete Icon Button
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: IconButton(
                        onPressed: () => _confirmDeleteCompletedShipment(shipment),
                        icon: Icon(Icons.delete_outline, color: Colors.red.shade700, size: 20),
                        tooltip: 'Delete',
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    
                    // Edit Button
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showConfigureDialog(
                          shipment,
                          isSingleCustomer: shipment.orderType != 'multi',
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit', style: TextStyle(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue.shade700,
                          side: BorderSide(color: Colors.blue.shade300, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    
                    // Get Slip Button
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _downloadAndShareSlip(shipment),
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                        label: const Text('Slip', style: TextStyle(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.deepOrange.shade700,
                          side: BorderSide(color: Colors.deepOrange.shade300, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                
                // Start Loading Button (Full Width) - COMPACT
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _startLoading(shipment),
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text(
                      'Start Loading',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      elevation: 2,
                      shadowColor: Colors.green.shade200,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // Modern detail row with better styling - COMPACT
  Widget _buildModernDetailRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 16, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  
  // ================================
  // ✅ FIXED: REAL PDF DOWNLOAD WITH VIEW OPTION
  // ================================

  Future<void> _downloadAndShareSlip(ShipmentOrder shipment) async {
    if (!mounted) return;
    
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Generating shipment slip PDF...'),
            ],
          ),
        ),
      ),
    );

    try {
      log('📄 [PDF] Generating for: ${shipment.shipmentId}');
      
      // ✅ Step 1: Generate or get QR data
      final qrResult = await ShipmentService.generateShipmentQR(
        shipmentOrderId: shipment.id,
      );

      if (!qrResult['success']) {
        throw Exception(qrResult['message'] ?? 'Failed to generate QR code');
      }

      log('✅ [PDF] QR generated');

      // ✅ Step 2: Get cartons
      final cartons = await ShipmentService.getShipmentCartons(
        shipmentOrderId: shipment.id,
      );
      
      if (cartons.isEmpty) {
        throw Exception('No cartons found for this shipment');
      }

      final cartonBarcodes = cartons.map((c) => c.cartonBarcode).toList();
      log('📦 [PDF] Found ${cartonBarcodes.length} cartons');

      // ✅ Step 3: Generate PDF
      final pdfBytes = await ShipmentSlipGenerator.generateShipmentSlip(
        shipment: shipment,
        qrData: qrResult['qrdata'],
        cartonBarcodes: cartonBarcodes,
      );

      log('✅ [PDF] PDF generated (${pdfBytes.length} bytes)');

      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      // ✅ Step 4: Display PDF using printing package (works on all platforms including web)
      await Printing.layoutPdf(
        onLayout: (format) async => pdfBytes,
        name: 'Shipment_${shipment.shipmentId}.pdf',
      );

      log('✅ [PDF] Displayed successfully');

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Shipment slip generated successfully!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } catch (e, stackTrace) {
      log('❌ [PDF] Error: $e\n$stackTrace');
      if (mounted) {
        // Close loading dialog if still open
        Navigator.of(context).pop();
        
        // Small delay before showing error
        await Future.delayed(const Duration(milliseconds: 200));
        
        if (mounted) {
          showDialog(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 24),
                  const SizedBox(width: 12),
                  const Text('PDF Generation Failed'),
                ],
              ),
              content: Text(
                'Failed to generate shipment slip.\n\nError: ${e.toString()}\n\nPlease try again or contact support.',
                style: const TextStyle(fontSize: 13),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    }
  }

  Widget _buildPDFInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  String _getShipmentTypeLabel(ShipmentType type) {
    switch (type) {
      case ShipmentType.truck:
        return 'Truck Delivery';
      case ShipmentType.courier:
        return 'Courier Service';
      case ShipmentType.inPerson:
        return 'In-Person Pickup';
    }
  }

  // ================================
  // ✅ UPDATED: LOADING SCREEN NAVIGATION WITH PRE-LOADED DATA
  // ================================

  Future<void> _startLoading(ShipmentOrder shipment) async {
    if (!mounted) return;
    
    log('🚛 Starting loading for: ${shipment.shipmentId}');
    
    // Show loading dialog while fetching cartons
    _showLoadingDialog('Preparing loading session...');
    
    try {
      // Fetch cartons for this shipment
      final cartons = await ShipmentService.getShipmentCartons(
        shipmentOrderId: shipment.id,
      );
      
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
      }
      
      if (cartons.isEmpty) {
        if (mounted) {
          _showSafeDialog(
            title: 'No Cartons Found',
            message: 'This shipment has no cartons to load. Please check the shipment configuration.',
            isError: true,
          );
        }
        return;
      }
      
      // Extract carton barcodes
      final cartonList = cartons.map((c) => c.cartonBarcode.toUpperCase()).toList();
      
      // Get loading strategy
      String loadingStrategy = 'NON_LIFO';
      if (shipment.loadingStrategy != null) {
        loadingStrategy = shipment.loadingStrategy!.name.toUpperCase();
      }
      
      // Get truck number
      String? truckNumber;
      if (shipment.shipmentType == ShipmentType.truck) {
        truckNumber = shipment.truckDetails?['truckNumber']?.toString();
      }
      
      if (truckNumber == null || truckNumber.isEmpty) {
        if (mounted) {
          _showSafeDialog(
            title: 'Truck Not Assigned',
            message: 'Please configure truck details before starting loading.',
            isError: true,
          );
        }
        return;
      }
      
      log('✅ Prepared loading session:');
      log('   - Shipment: ${shipment.shipmentId}');
      log('   - Customer: ${shipment.customerName}');
      log('   - Truck: $truckNumber');
      log('   - Strategy: $loadingStrategy');
      log('   - Cartons: ${cartonList.length}');
      
      if (!mounted) return;
      
      // ✅ Navigate to loading screen with pre-loaded data
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LoadingScreen(
            userName: widget.userName,
            shipmentOrderId: shipment.id,
            preloadedShipmentId: shipment.shipmentId,
            preloadedTruckNumber: truckNumber,
            preloadedCustomerName: shipment.customerName,
            preloadedLoadingStrategy: loadingStrategy,
            preloadedCartonList: cartonList,
            preloadedTotalCartons: cartonList.length,
          ),
        ),
      ).then((_) {
        // Refresh when returning from loading screen
        if (mounted) {
          _loadAllData(forceRefresh: true);
        }
      });
      
    } catch (e) {
      log('❌ Error preparing loading session: $e');
      if (mounted) {
        Navigator.pop(context); // Close loading dialog if still open
        _showSafeDialog(
          title: 'Error',
          message: 'Failed to prepare loading session: ${e.toString()}',
          isError: true,
        );
      }
    }
  }

  // ================================
  // HELPER WIDGETS
  // ================================

  /// Get display text for loading strategy
  String _getLoadingStrategyDisplay(LoadingStrategy? strategy) {
    if (strategy == null) return 'NON-LIFO'; // Default
    
    switch (strategy) {
      case LoadingStrategy.lifo:
        return 'LIFO';
      case LoadingStrategy.nonLifo:
        return 'NON-LIFO';
    }
  }

  Widget _buildInfoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String message,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _getShipmentTypeIcon(ShipmentType type) {
    switch (type) {
      case ShipmentType.truck:
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.local_shipping, color: Colors.blue.shade700, size: 24),
        );
      case ShipmentType.courier:
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.purple.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.flight, color: Colors.purple.shade700, size: 24),
        );
      case ShipmentType.inPerson:
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.person, color: Colors.green.shade700, size: 24),
        );
    }
  }

  // ================================
  // DIALOG HELPERS
  // ================================

  void _showLoadingDialog(String message) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  void _showSafeDialog({
    required String title,
    required String message,
    required bool isError,
  }) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isError ? Icons.error : Icons.check_circle,
              color: isError ? Colors.red : Colors.green,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: ElevatedButton.styleFrom(
              backgroundColor: isError ? Colors.red : Colors.green,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSafeSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error : Icons.check_circle,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ================================
  // ✅ NEW: VIEW SHIPMENT ITEMS DIALOG
  // ================================

  Future<void> _showShipmentItemsDialog(ShipmentOrder shipment) async {
    if (!mounted) return;
    
    _showLoadingDialog('Loading cartons...');
    
    try {
      final cartons = await ShipmentService.getShipmentCartons(
        shipmentOrderId: shipment.id,
      );
      
      if (mounted) {
        Navigator.pop(context); // Close loading
      }
      
      if (!mounted) return;
      
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.inventory_2, color: Colors.deepOrange, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shipment.shipmentId,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      shipment.customerName ?? 'Unknown Customer',
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.deepOrange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.deepOrange.shade200),
                ),
                child: Text(
                  '${cartons.length}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepOrange.shade700,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: cartons.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox, size: 60, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(
                          'No cartons found',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: cartons.length,
                    itemBuilder: (context, index) {
                      final carton = cartons[index];
                      final isLoaded = carton.isLoaded;
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isLoaded ? Colors.green.shade200 : Colors.orange.shade200,
                            width: 1,
                          ),
                        ),
                        color: isLoaded ? Colors.green.shade50 : Colors.white,
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isLoaded ? Colors.green.shade100 : Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              isLoaded ? Icons.check_circle : Icons.inventory_2,
                              color: isLoaded ? Colors.green.shade700 : Colors.orange.shade700,
                              size: 22,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  carton.cartonBarcode,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                    letterSpacing: 0.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              carton.customerName,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isLoaded ? Colors.green : Colors.orange,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isLoaded ? 'Loaded' : 'Pending',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          children: [
                            FutureBuilder<Map<String, dynamic>>(
                              future: ShipmentService.getCartonItemsWithQuantity(
                                cartonBarcode: carton.cartonBarcode,
                              ),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState == ConnectionState.waiting) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }

                                if (snapshot.hasError) {
                                  return Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Text(
                                      'Error loading items',
                                      style: TextStyle(color: Colors.red.shade700, fontSize: 11),
                                    ),
                                  );
                                }

                                final data = snapshot.data ?? {};
                                final items = data['items'] as List? ?? [];
                                final totalItems = data['totalItems'] ?? 0;

                                if (items.isEmpty) {
                                  return Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Text(
                                      'No items in this carton',
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                                    ),
                                  );
                                }

                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    border: Border(
                                      top: BorderSide(color: Colors.grey.shade200),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Items in Carton',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.shade100,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'Total: $totalItems items',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blue.shade700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      ...items.map((item) {
                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 6),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 32,
                                                height: 32,
                                                decoration: BoxDecoration(
                                                  color: Colors.blue.shade50,
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    '${item['quantity']}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.blue.shade700,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      item['product_name'] ?? 'Unknown',
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    Text(
                                                      'SKU: ${item['sku']}',
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        color: Colors.grey.shade600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading
        _showSafeDialog(
          title: 'Error',
          message: 'Failed to load cartons: ${e.toString()}',
          isError: true,
        );
      }
    }
  }

  // ================================
  // ✅ NEW: DELETE COMPLETED SHIPMENT
  // ================================

  void _confirmDeleteCompletedShipment(ShipmentOrder shipment) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning, color: Colors.red, size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Permanent Delete?',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200, width: 2),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade700, size: 24),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '⚠️ This will PERMANENTLY delete the shipment!',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Shipment Details:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDeleteInfoRow('Shipment ID', shipment.shipmentId),
                  const Divider(height: 16),
                  _buildDeleteInfoRow('Customer', shipment.customerName ?? 'N/A'),
                  const Divider(height: 16),
                  _buildDeleteInfoRow('Cartons', '${shipment.totalCartons}'),
                  const Divider(height: 16),
                  _buildDeleteInfoRow('Status', shipment.statusString.toUpperCase()),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amber.shade700, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'This action cannot be undone. All related data will be removed.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _performPermanentDelete(shipment);
            },
            icon: const Icon(Icons.delete_forever, size: 18),
            label: const Text('Delete Permanently'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeleteInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Future<void> _performPermanentDelete(ShipmentOrder shipment) async {
    if (!mounted) return;
    
    // Show loading
    _showLoadingDialog('Permanently deleting shipment...');
    
    try {
      log('🗑️ Permanently deleting: ${shipment.id}');
      
      // ✅ Call permanent delete method
      final result = await ShipmentService.deleteShipmentPermanently(
        shipmentOrderId: shipment.id,
      );
      
      if (mounted) {
        Navigator.pop(context); // Close loading
      }
      
      if (result['success']) {
        // Force refresh to get updated list
        await _loadAllData(forceRefresh: true);
        
        if (mounted) {
          _showSafeSnackBar('✅ Shipment permanently deleted!');
        }
        
        log('✅ Permanent delete successful');
      } else {
        if (mounted) {
          _showSafeDialog(
            title: 'Delete Failed',
            message: result['message'] ?? 'Unknown error occurred',
            isError: true,
          );
        }
        log('❌ Permanent delete failed: ${result['message']}');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading
        _showSafeDialog(
          title: 'Error',
          message: 'Failed to delete: ${e.toString()}',
          isError: true,
        );
      }
      log('❌ Permanent delete error: $e');
    }
  }

  // ================================
  // FORMATTING HELPERS
  // ================================

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}

// ================================
// CONFIGURE DIALOG (EXISTING CODE MAINTAINED)
// ================================

class ConfigureShipmentDialog extends StatefulWidget {
  final ShipmentOrder shipment;
  final String userName;
  final bool isSingleCustomer;
  final VoidCallback onConfigured;

  const ConfigureShipmentDialog({
    super.key,
    required this.shipment,
    required this.userName,
    required this.isSingleCustomer,
    required this.onConfigured,
  });

  @override
  State<ConfigureShipmentDialog> createState() => _ConfigureShipmentDialogState();
}

class _ConfigureShipmentDialogState extends State<ConfigureShipmentDialog> {
  final _formKey = GlobalKey<FormState>();
  ShipmentType _selectedType = ShipmentType.truck;
  LoadingStrategy _loadingStrategy = LoadingStrategy.nonLifo; // ✅ Changed from fifo to nonLifo

  // Controllers
  final _truckNumberController = TextEditingController();
  final _driverNameController = TextEditingController();
  final _driverPhoneController = TextEditingController();
  final _awbController = TextEditingController();
  final _contactPersonController = TextEditingController();
  final _idProofController = TextEditingController();
  final _pickupPhoneController = TextEditingController();
  final _destinationController = TextEditingController();
  final _specialInstructionsController = TextEditingController();

  String _selectedCourier = 'Blue Dart';
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _destinationController.text = widget.shipment.destination ?? '';
    
    // ✅ ADDED: Load existing data if editing
    if (widget.shipment.shipmentType != null) {
      _selectedType = widget.shipment.shipmentType!;
      
      if (_selectedType == ShipmentType.truck && widget.shipment.truckDetails != null) {
        _truckNumberController.text = widget.shipment.truckDetails!['truckNumber'] ?? '';
        _driverNameController.text = widget.shipment.truckDetails!['driverName'] ?? '';
        _driverPhoneController.text = widget.shipment.truckDetails!['driverPhone'] ?? '';
        _loadingStrategy = widget.shipment.loadingStrategy ?? LoadingStrategy.nonLifo; // ✅ Changed from fifo to nonLifo
      } else if (_selectedType == ShipmentType.courier && widget.shipment.courierDetails != null) {
        _selectedCourier = widget.shipment.courierDetails!['courierName'] ?? 'Blue Dart';
        _awbController.text = widget.shipment.courierDetails!['awbNumber'] ?? '';
      } else if (_selectedType == ShipmentType.inPerson && widget.shipment.inPersonDetails != null) {
        _contactPersonController.text = widget.shipment.inPersonDetails!['contactPerson'] ?? '';
        _pickupPhoneController.text = widget.shipment.inPersonDetails!['phoneNumber'] ?? '';
        _idProofController.text = widget.shipment.inPersonDetails!['idProof'] ?? '';
      }
      
      _specialInstructionsController.text = widget.shipment.specialInstructions ?? '';
    }
  }

  @override
  void dispose() {
    _truckNumberController.dispose();
    _driverNameController.dispose();
    _driverPhoneController.dispose();
    _awbController.dispose();
    _contactPersonController.dispose();
    _idProofController.dispose();
    _pickupPhoneController.dispose();
    _destinationController.dispose();
    _specialInstructionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Icon(Icons.settings, color: Colors.deepOrange, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.isSingleCustomer ? 'Configure SO' : 'Configure MSO',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            widget.shipment.shipmentId,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Info Banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: widget.isSingleCustomer ? Colors.green.shade50 : Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: widget.isSingleCustomer ? Colors.green.shade200 : Colors.purple.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        widget.isSingleCustomer ? Icons.person : Icons.group,
                        color: widget.isSingleCustomer ? Colors.green.shade700 : Colors.purple.shade700,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.isSingleCustomer ? 'Single Customer' : 'Multi-Customer',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${widget.shipment.customerName} • ${widget.shipment.totalCartons} Cartons',
                              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Type Selection
                const Text(
                  'Select Delivery Method',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildTypeSelector(),
                const SizedBox(height: 24),

                // Destination
                TextFormField(
                  controller: _destinationController,
                  decoration: const InputDecoration(
                    labelText: 'Destination Address *',
                    prefixIcon: Icon(Icons.place),
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                  validator: ShipmentValidation.validateDestination,
                ),
                const SizedBox(height: 16),

                // Type-Specific Fields
                if (_selectedType == ShipmentType.truck) ..._buildTruckFields(),
                if (_selectedType == ShipmentType.courier) ..._buildCourierFields(),
                if (_selectedType == ShipmentType.inPerson) ..._buildInPersonFields(),

                // Special Instructions
                const SizedBox(height: 16),
                TextFormField(
                  controller: _specialInstructionsController,
                  decoration: const InputDecoration(
                    labelText: 'Special Instructions (Optional)',
                    prefixIcon: Icon(Icons.note),
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 24),

                // Buttons
                if (_isProcessing)
                  const Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Configuring...'),
                      ],
                    ),
                  )
                else
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _handleGenerate,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepOrange,
                          ),
                          icon: const Icon(Icons.check_circle),
                          label: const Text('Save & Generate'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeSelector() {
    return Row(
      children: [
        Expanded(child: _buildTypeOption(ShipmentType.truck, Icons.local_shipping, 'Truck', Colors.blue)),
        const SizedBox(width: 8),
        Expanded(child: _buildTypeOption(ShipmentType.courier, Icons.flight, 'Courier', Colors.purple)),
        const SizedBox(width: 8),
        Expanded(child: _buildTypeOption(ShipmentType.inPerson, Icons.person, 'Pickup', Colors.green)),
      ],
    );
  }

  Widget _buildTypeOption(ShipmentType type, IconData icon, String label, Color color) {
    final isSelected = _selectedType == type;
    
    return InkWell(
      onTap: () => setState(() => _selectedType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.grey.shade50,
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isSelected ? color : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTruckFields() {
    return [
      TextFormField(
        controller: _truckNumberController,
        decoration: const InputDecoration(
          labelText: 'Truck Number *',
          prefixIcon: Icon(Icons.local_shipping),
          border: OutlineInputBorder(),
          hintText: 'MH12AB1234',
        ),
        textCapitalization: TextCapitalization.characters,
        validator: ShipmentValidation.validateTruckNumber,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _driverNameController,
        decoration: const InputDecoration(
          labelText: 'Driver Name *',
          prefixIcon: Icon(Icons.person),
          border: OutlineInputBorder(),
        ),
        validator: ShipmentValidation.validateDriverName,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _driverPhoneController,
        decoration: const InputDecoration(
          labelText: 'Driver Phone *',
          prefixIcon: Icon(Icons.phone),
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.phone,
        maxLength: 10,
        validator: ShipmentValidation.validatePhoneNumber,
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amber.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Loading Strategy *', style: TextStyle(fontWeight: FontWeight.bold)),
            RadioListTile<LoadingStrategy>(
              title: const Text('NON-LIFO - Any Order (First In, First Out)'),
              value: LoadingStrategy.nonLifo, // ✅ Changed from fifo to nonLifo
              groupValue: _loadingStrategy,
              onChanged: (value) => setState(() => _loadingStrategy = value!),
            ),
            RadioListTile<LoadingStrategy>(
              title: const Text('LIFO - Last In, First Out'),
              value: LoadingStrategy.lifo,
              groupValue: _loadingStrategy,
              onChanged: (value) => setState(() => _loadingStrategy = value!),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildCourierFields() {
    return [
      DropdownButtonFormField<String>(
        value: _selectedCourier,
        decoration: const InputDecoration(
          labelText: 'Courier Service *',
          prefixIcon: Icon(Icons.flight),
          border: OutlineInputBorder(),
        ),
        items: ['Blue Dart', 'Delhivery', 'FedEx', 'DHL', 'DTDC']
            .map((courier) => DropdownMenuItem(value: courier, child: Text(courier)))
            .toList(),
        onChanged: (value) => setState(() => _selectedCourier = value!),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _awbController,
        decoration: const InputDecoration(
          labelText: 'AWB Number *',
          prefixIcon: Icon(Icons.qr_code),
          border: OutlineInputBorder(),
        ),
        validator: ShipmentValidation.validateAWBNumber,
      ),
    ];
  }

  List<Widget> _buildInPersonFields() {
    return [
      TextFormField(
        controller: _contactPersonController,
        decoration: const InputDecoration(
          labelText: 'Contact Person *',
          prefixIcon: Icon(Icons.person),
          border: OutlineInputBorder(),
        ),
        validator: ShipmentValidation.validateContactPerson,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _pickupPhoneController,
        decoration: const InputDecoration(
          labelText: 'Phone Number *',
          prefixIcon: Icon(Icons.phone),
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.phone,
        maxLength: 10,
        validator: ShipmentValidation.validatePhoneNumber,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _idProofController,
        decoration: const InputDecoration(
          labelText: 'ID Proof *',
          prefixIcon: Icon(Icons.badge),
          border: OutlineInputBorder(),
        ),
        validator: ShipmentValidation.validateIDProof,
      ),
    ];
  }

  Future<void> _handleGenerate() async {
    if (!_formKey.currentState!.validate()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please fix validation errors'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _isProcessing = true);

    try {
      Map<String, dynamic>? details;
      
      if (_selectedType == ShipmentType.truck) {
        details = {
          'truckNumber': _truckNumberController.text.toUpperCase(),
          'driverName': _driverNameController.text,
          'driverPhone': _driverPhoneController.text,
        };
      } else if (_selectedType == ShipmentType.courier) {
        details = {
          'courierName': _selectedCourier,
          'awbNumber': _awbController.text,
        };
      } else {
        details = {
          'contactPerson': _contactPersonController.text,
          'phoneNumber': _pickupPhoneController.text,
          'idProof': _idProofController.text,
        };
      }

      final result = await ShipmentService.configureShipment(
        shipmentOrderId: widget.shipment.id,
        shipmentType: _selectedType,
        loadingStrategy: _selectedType == ShipmentType.truck ? _loadingStrategy : null,
        truckDetails: _selectedType == ShipmentType.truck ? details : null,
        courierDetails: _selectedType == ShipmentType.courier ? details : null,
        inPersonDetails: _selectedType == ShipmentType.inPerson ? details : null,
        destination: _destinationController.text,
        specialInstructions: _specialInstructionsController.text.isNotEmpty
            ? _specialInstructionsController.text
            : null,
      );

      if (!result['success']) {
        throw Exception(result['message']);
      }

      await ShipmentService.generateShipmentQR(shipmentOrderId: widget.shipment.id);

      if (mounted) {
        Navigator.pop(context);
        widget.onConfigured();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
