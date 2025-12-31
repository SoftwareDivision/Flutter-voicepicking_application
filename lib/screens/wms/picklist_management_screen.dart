// lib/screens/wms/picklist_management_screen.dart

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';
import 'dart:io';
import '../../utils/colors.dart';
import '../../services/warehouse_service.dart';

class PicklistManagementScreen extends StatefulWidget {
  final String userName;

  const PicklistManagementScreen({
    super.key,
    required this.userName,
  });

  @override
  State<PicklistManagementScreen> createState() => _PicklistManagementScreenState();
}

class _PicklistManagementScreenState extends State<PicklistManagementScreen> {
  List<Map<String, dynamic>> picklist = [];
  bool isLoading = true;
  bool isExporting = false;
  String? errorMessage;
  String selectedFilter = 'all';
  String searchQuery = '';

  // Search controller
  final searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadPicklist();
    searchController.addListener(onSearchChanged);
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void onSearchChanged() {
    setState(() {
      searchQuery = searchController.text.toLowerCase();
    });
  }

  Future<void> loadPicklist() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final items = await WarehouseService.fetchPicklist(limit: 1000);
      if (mounted) {
        setState(() {
          // Filter out cancelled/deleted items and sort professionally
          picklist = items.where((item) => 
            item['status'] != 'cancelled' && 
            item['status'] != 'deleted'
          ).toList();
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = e.toString();
          isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get filteredPicklist {
    var filtered = picklist.where((item) {
      // Apply status filter
      bool matchesStatus = true;
      switch (selectedFilter) {
        case 'pending':
          matchesStatus = item['status'] == 'pending';
          break;
        case 'in_progress':
          matchesStatus = item['status'] == 'in_progress';
          break;
        case 'completed':
          matchesStatus = item['status'] == 'completed';
          break;
        case 'all':
        default:
          matchesStatus = true;
          break;
      }

      // Apply search filter
      bool matchesSearch = true;
      if (searchQuery.isNotEmpty) {
        matchesSearch = (item['item_name']?.toString().toLowerCase().contains(searchQuery) ?? false) ||
            (item['sku']?.toString().toLowerCase().contains(searchQuery) ?? false) ||
            (item['wave_number']?.toString().toLowerCase().contains(searchQuery) ?? false) ||
            (item['picker_name']?.toString().toLowerCase().contains(searchQuery) ?? false) ||
            (item['customer_name']?.toString().toLowerCase().contains(searchQuery) ?? false) ||
            (item['order_source']?.toString().toLowerCase().contains(searchQuery) ?? false);
      }

      return matchesStatus && matchesSearch;
    }).toList();

    // Sort by priority and creation date professionally
    filtered.sort((a, b) {
      final priorityOrder = {'urgent': 4, 'high': 3, 'normal': 2, 'low': 1};
      int priorityComparison = (priorityOrder[b['priority']] ?? 2) - (priorityOrder[a['priority']] ?? 2);
      if (priorityComparison != 0) return priorityComparison;
      return (a['created_at']?.toString() ?? '').compareTo(b['created_at']?.toString() ?? '');
    });

    return filtered;
  }

  Future<void> deletePicklistItem(String itemId) async {
    try {
      setState(() {
        isLoading = true;
      });

      final success = await WarehouseService.deletePicklistItem(itemId);
      if (success) {
        showSuccessMessage('Item deleted successfully');
        // Remove from local list immediately
        setState(() {
          picklist.removeWhere((item) => item['id'] == itemId);
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
        });
        showErrorMessage('Failed to delete item');
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      showErrorMessage('Error deleting item: ${e.toString()}');
    }
  }

  void showDeleteConfirmation(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Expanded(child: Text('Delete Picklist Item')),
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
              child: Column(
                children: [
                  const Icon(Icons.delete_forever, color: Colors.red, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Delete "${item['item_name'] ?? 'Unknown Item'}"?',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Wave: ${item['wave_number'] ?? 'N/A'} • Qty: ${item['quantity_requested'] ?? 0}',
                    style: const TextStyle(color: Colors.red, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'This will permanently remove the item from the picklist. This action cannot be undone.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              deletePicklistItem(item['id']);
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

  Future<void> exportPicklistReport() async {
    setState(() {
      isExporting = true;
    });

    try {
      // Create comprehensive CSV data
      List<List<dynamic>> csvData = [];

      // Header Section
      csvData.addAll([
        ['PICKLIST MANAGEMENT REPORT'],
        ['Generated on:', DateTime.now().toString()],
        ['Generated by:', widget.userName],
        ['Total Items:', filteredPicklist.length.toString()],
        [''],
      ]);

      // Statistics
      final pendingCount = filteredPicklist.where((i) => i['status'] == 'pending').length;
      final inProgressCount = filteredPicklist.where((i) => i['status'] == 'in_progress').length;
      final completedCount = filteredPicklist.where((i) => i['status'] == 'completed').length;

      csvData.addAll([
        ['SUMMARY STATISTICS'],
        ['Pending Items:', pendingCount.toString()],
        ['In Progress Items:', inProgressCount.toString()],
        ['Completed Items:', completedCount.toString()],
        [''],
      ]);

      // Data Headers
      csvData.add([
        'ID', 'Wave Number', 'Item Name', 'SKU', 'Picker Name',
        'Customer Name', 'Order Source', 'Quantity Requested', 'Quantity Picked',
        'Location', 'Priority', 'Status', 'Created Date', 'Completed Date'
      ]);

      // Data Rows
      for (var item in filteredPicklist) {
        csvData.add([
          item['id']?.toString() ?? '',
          item['wave_number']?.toString() ?? '',
          item['item_name']?.toString() ?? '',
          item['sku']?.toString() ?? '',
          item['picker_name']?.toString() ?? '',
          item['customer_name']?.toString() ?? '',
          item['order_source']?.toString() ?? 'manual',
          item['quantity_requested']?.toString() ?? '0',
          item['quantity_picked']?.toString() ?? '0',
          item['location']?.toString() ?? '',
          item['priority']?.toString() ?? '',
          item['status']?.toString() ?? '',
          item['created_at']?.toString().substring(0, 19) ?? '',
          item['completed_at']?.toString().substring(0, 19) ?? '',
        ]);
      }

      // Convert to CSV string
      String csvString = const ListToCsvConverter().convert(csvData);

      // Save to file
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toString().replaceAll(':', '-').substring(0, 19);
      final file = File('${directory.path}/picklist_report_$timestamp.csv');
      await file.writeAsString(csvString);

      // Share file
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Picklist Report - ${filteredPicklist.length} items',
      );

      showSuccessMessage('Picklist report exported successfully!');
    } catch (e) {
      showErrorMessage('Export failed: ${e.toString()}');
    } finally {
      setState(() {
        isExporting = false;
      });
    }
  }

  void editPickStatus(Map<String, dynamic> item) {
    String newStatus = item['status'] ?? 'pending';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.edit, color: Colors.green),
            SizedBox(width: 12),
            Expanded(child: Text('Update Pick Status')),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Item: ${item['item_name'] ?? 'N/A'}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Wave: ${item['wave_number'] ?? 'N/A'}',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Location: ${item['location'] ?? 'N/A'}',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    if (item['customer_name'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Customer: ${item['customer_name']}',
                        style: const TextStyle(fontSize: 14, color: Colors.blue),
                      ),
                    ],
                    if (item['order_source'] != null && item['order_source'] == 'telegram_bot') ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'TELEGRAM ORDER',
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: newStatus,
                decoration: InputDecoration(
                  labelText: 'New Status',
                  prefixIcon: const Icon(Icons.edit),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey.withOpacity(0.1),
                ),
                isExpanded: true,
                items: [
                  DropdownMenuItem(
                    value: 'pending',
                    child: Row(
                      children: [
                        Icon(Icons.pending_actions, size: 20, color: Colors.orange),
                        const SizedBox(width: 8),
                        const Flexible(child: Text('PENDING')),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'in_progress',
                    child: Row(
                      children: [
                        Icon(Icons.play_circle, size: 20, color: Colors.blue),
                        const SizedBox(width: 8),
                        const Flexible(child: Text('IN PROGRESS')),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'completed',
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, size: 20, color: Colors.green),
                        const SizedBox(width: 8),
                        const Flexible(child: Text('COMPLETED')),
                      ],
                    ),
                  ),
                ],
                onChanged: (value) {
                  newStatus = value ?? 'pending';
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await WarehouseService.updatePickStatus(item['id'], newStatus);
              if (success) {
                await loadPicklist();
                showSuccessMessage('Pick status updated to ${newStatus.toUpperCase().replaceAll('_', ' ')}');
              } else {
                showErrorMessage('Failed to update pick status');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void showItemDetails(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.assignment, color: Colors.green),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Pick ID: ${item['id'] ?? ''}',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                buildDialogDetailRow('Wave Number', item['wave_number'] ?? 'N/A'),
                buildDialogDetailRow('Item Name', item['item_name'] ?? 'N/A'),
                buildDialogDetailRow('SKU', item['sku'] ?? 'N/A'),
                buildDialogDetailRow('Picker Name', item['picker_name'] ?? 'Unassigned'),
                buildDialogDetailRow('Status', item['status'] ?? 'pending'),
                buildDialogDetailRow('Location', item['location'] ?? 'Unknown'),
                buildDialogDetailRow('Barcode', item['barcode'] ?? 'N/A'),
                buildDialogDetailRow('Priority', item['priority'] ?? 'Normal'),
                buildDialogDetailRow('Quantity Requested', item['quantity_requested']?.toString() ?? '0'),
                buildDialogDetailRow('Quantity Picked', item['quantity_picked']?.toString() ?? '0'),
                if (item['customer_name'] != null)
                  buildDialogDetailRow('Customer', item['customer_name']),
                if (item['order_source'] != null)
                  buildDialogDetailRow('Order Source', item['order_source'] == 'telegram_bot' ? 'Telegram Order' : 'Manual'),
                buildDialogDetailRow('Created', formatDate(item['created_at']?.toString() ?? '')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              editPickStatus(item);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Update Status'),
          ),
        ],
      ),
    );
  }

  Widget buildDialogDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
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

  Widget buildPicklistCard(Map<String, dynamic> item, int index) {
    final waveNumber = item['wave_number'] ?? 'N/A';
    final pickerName = item['picker_name'] ?? 'Unassigned';
    final status = item['status'] ?? 'pending';
    final quantityRequested = item['quantity_requested'] ?? 0;
    final quantityPicked = item['quantity_picked'] ?? 0;
    final location = item['location'] ?? 'Unknown';
    final priority = item['priority'] ?? 'Normal';
    final customerName = item['customer_name'];
    final orderSource = item['order_source'];

    Color statusColor = Colors.orange;
    IconData statusIcon = Icons.pending_actions;

    switch (status.toLowerCase()) {
      case 'completed':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'in_progress':
        statusColor = Colors.blue;
        statusIcon = Icons.play_circle;
        break;
      case 'pending':
      default:
        statusColor = Colors.orange;
        statusIcon = Icons.pending_actions;
        break;
    }

    return Dismissible(
      key: Key(item['id'].toString()),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        return await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Confirm Delete'),
              content: const Text('Are you sure you want to delete this item?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        );
      },
      onDismissed: (direction) {
        deletePicklistItem(item['id']);
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20.0),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.delete,
          color: Colors.white,
          size: 30,
        ),
      ),
      child: Container(
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
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Wave: $waveNumber',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        flex: 1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: getPriorityColor(priority).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            priority.toUpperCase(),
                            style: TextStyle(
                              color: getPriorityColor(priority),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (orderSource == 'telegram_bot') ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'TELEGRAM ORDER',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Item: ${item['item_name'] ?? 'N/A'}',
                    style: const TextStyle(fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Picker: $pickerName',
                    style: const TextStyle(fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (customerName != null)
                    Text(
                      'Customer: $customerName',
                      style: const TextStyle(fontSize: 14, color: Colors.blue),
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(
                    'Qty: $quantityPicked/$quantityRequested',
                    style: const TextStyle(fontSize: 14),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) => handlePickAction(value, item),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'edit_status',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 18),
                        SizedBox(width: 8),
                        Text('Update Status'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'view_details',
                    child: Row(
                      children: [
                        Icon(Icons.visibility, size: 18),
                        SizedBox(width: 8),
                        Text('View Details'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
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
                      buildDetailRow('Location', location),
                      buildDetailRow('Priority', priority),
                      buildDetailRow('SKU', item['sku'] ?? 'N/A'),
                      buildDetailRow('Barcode', item['barcode'] ?? 'N/A'),
                      buildDetailRow('Quantity Requested', quantityRequested.toString()),
                      buildDetailRow('Quantity Picked', quantityPicked.toString()),
                      buildDetailRow('Created', formatDate(item['created_at']?.toString() ?? '')),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => editPickStatus(item),
                              icon: const Icon(Icons.edit, size: 18),
                              label: const Text('Update Status'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => showDeleteConfirmation(item),
                              icon: const Icon(Icons.delete, size: 18),
                              label: const Text('Delete'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
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
      ),
    );
  }

  Widget buildDetailRow(String label, String value) {
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

  void handlePickAction(String action, Map<String, dynamic> item) {
    switch (action) {
      case 'edit_status':
        editPickStatus(item);
        break;
      case 'view_details':
        showItemDetails(item);
        break;
      case 'delete':
        showDeleteConfirmation(item);
        break;
    }
  }

  Color getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'urgent':
        return Colors.red;
      case 'high':
        return Colors.orange;
      case 'normal':
        return Colors.blue;
      case 'low':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  String formatDate(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateStr.length > 19 ? dateStr.substring(0, 19) : dateStr;
    }
  }

  void showSuccessMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      );
    }
  }

  void showErrorMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      );
    }
  }

  Widget buildFilterChips() {
    final filters = [
      {'key': 'all', 'label': 'All', 'icon': Icons.list},
      {'key': 'pending', 'label': 'Pending', 'icon': Icons.pending_actions},
      {'key': 'in_progress', 'label': 'In Progress', 'icon': Icons.play_circle},
      {'key': 'completed', 'label': 'Completed', 'icon': Icons.check_circle},
    ];

    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: filters.map((filter) {
          final isSelected = selectedFilter == filter['key'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              avatar: Icon(
                filter['icon'] as IconData,
                size: 18,
                color: isSelected ? Colors.white : Colors.green,
              ),
              label: Text(filter['label'] as String),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    selectedFilter = filter['key'] as String;
                  });
                }
              },
              backgroundColor: Colors.green.withOpacity(0.1),
              selectedColor: Colors.green,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.green,
                fontWeight: FontWeight.w500,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Picklist Management'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: loadPicklist,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.file_download),
            onPressed: isExporting ? null : exportPicklistReport,
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
              Colors.green.withOpacity(0.08),
              Colors.white,
            ],
          ),
        ),
        child: Column(
          children: [
            // Search Bar
            Container(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: searchController,
                decoration: InputDecoration(
                  hintText: 'Search by item, SKU, wave number, picker, or customer...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            searchController.clear();
                            setState(() {
                              searchQuery = '';
                            });
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
            ),

            // Filter Chips
            buildFilterChips(),

            // Statistics
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  buildStatItem('Total', filteredPicklist.length, Colors.blue),
                  buildStatItem('Pending', filteredPicklist.where((i) => i['status'] == 'pending').length, Colors.orange),
                  buildStatItem('In Progress', filteredPicklist.where((i) => i['status'] == 'in_progress').length, Colors.blue),
                  buildStatItem('Completed', filteredPicklist.where((i) => i['status'] == 'completed').length, Colors.green),
                ],
              ),
            ),

            // Content
            Expanded(
              child: isLoading
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Loading picklist...',
                            style: TextStyle(
                              fontSize: 16,
                              color: AppColors.textLight,
                            ),
                          ),
                        ],
                      ),
                    )
                  : errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 64,
                                  color: Colors.red.withOpacity(0.7),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Error loading picklist',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.withOpacity(0.8),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppColors.textLight,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                ElevatedButton.icon(
                                  onPressed: loadPicklist,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Retry'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : filteredPicklist.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.assignment_outlined,
                                    size: 64,
                                    color: Colors.grey.withOpacity(0.6),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'No picklist items found',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textLight,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    searchQuery.isNotEmpty 
                                        ? 'No items match your search'
                                        : 'Orders from Telegram will appear here automatically',
                                    style: const TextStyle(
                                      color: AppColors.textLight,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: loadPicklist,
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: filteredPicklist.length,
                                itemBuilder: (context, index) {
                                  final item = filteredPicklist[index];
                                  return buildPicklistCard(item, index);
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildStatItem(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color.withOpacity(0.8),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
