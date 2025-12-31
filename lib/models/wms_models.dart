// lib/models/wms_models.dart

class InventoryItem {
  final String id;
  final String warehouseId;
  final String name;
  final String sku;
  final String? barcode;
  final int quantity;
  final int minStock;
  final int maxStock;
  final double unitPrice;
  final String? location;
  final String? category;
  final String? supplier;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  InventoryItem({
    required this.id,
    required this.warehouseId,
    required this.name,
    required this.sku,
    this.barcode,
    required this.quantity,
    this.minStock = 10,
    this.maxStock = 1000,
    this.unitPrice = 0.0,
    this.location,
    this.category,
    this.supplier,
    this.status = 'active',
    required this.createdAt,
    required this.updatedAt,
  });

  factory InventoryItem.fromMap(Map<String, dynamic> map) {
    return InventoryItem(
      id: map['id'] ?? '',
      warehouseId: map['warehouse_id'] ?? '',
      name: map['name'] ?? '',
      sku: map['sku'] ?? '',
      barcode: map['barcode'],
      quantity: map['quantity'] ?? 0,
      minStock: map['min_stock'] ?? 10,
      maxStock: map['max_stock'] ?? 1000,
      unitPrice: (map['unit_price'] ?? 0.0).toDouble(),
      location: map['location'],
      category: map['category'],
      supplier: map['supplier'],
      status: map['status'] ?? 'active',
      createdAt: DateTime.parse(map['created_at'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(map['updated_at'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'warehouse_id': warehouseId,
      'name': name,
      'sku': sku,
      'barcode': barcode,
      'quantity': quantity,
      'min_stock': minStock,
      'max_stock': maxStock,
      'unit_price': unitPrice,
      'location': location,
      'category': category,
      'supplier': supplier,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  bool get isLowStock => quantity <= minStock;
}

class Order {
  final String id;
  final String warehouseId;
  final String orderNumber;
  final String? customerName;
  final String status;
  final String priority;
  final int totalItems;
  final DateTime createdAt;
  final DateTime updatedAt;

  Order({
    required this.id,
    required this.warehouseId,
    required this.orderNumber,
    this.customerName,
    this.status = 'pending',
    this.priority = 'normal',
    this.totalItems = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Order.fromMap(Map<String, dynamic> map) {
    return Order(
      id: map['id'] ?? '',
      warehouseId: map['warehouse_id'] ?? '',
      orderNumber: map['order_number'] ?? '',
      customerName: map['customer_name'],
      status: map['status'] ?? 'pending',
      priority: map['priority'] ?? 'normal',
      totalItems: map['total_items'] ?? 0,
      createdAt: DateTime.parse(map['created_at'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(map['updated_at'] ?? DateTime.now().toIso8601String()),
    );
  }
}

class PicklistItem {
  final String id;
  final String warehouseId;
  final String? orderId;
  final String? inventoryId;
  final String? waveNumber;
  final String? pickerName;
  final int quantityRequested;
  final int quantityPicked;
  final String? location;
  final String status;
  final String priority;
  final DateTime createdAt;
  final DateTime updatedAt;

  PicklistItem({
    required this.id,
    required this.warehouseId,
    this.orderId,
    this.inventoryId,
    this.waveNumber,
    this.pickerName,
    required this.quantityRequested,
    this.quantityPicked = 0,
    this.location,
    this.status = 'pending',
    this.priority = 'normal',
    required this.createdAt,
    required this.updatedAt,
  });

  factory PicklistItem.fromMap(Map<String, dynamic> map) {
    return PicklistItem(
      id: map['id'] ?? '',
      warehouseId: map['warehouse_id'] ?? '',
      orderId: map['order_id'],
      inventoryId: map['inventory_id'],
      waveNumber: map['wave_number'],
      pickerName: map['picker_name'],
      quantityRequested: map['quantity_requested'] ?? 0,
      quantityPicked: map['quantity_picked'] ?? 0,
      location: map['location'],
      status: map['status'] ?? 'pending',
      priority: map['priority'] ?? 'normal',
      createdAt: DateTime.parse(map['created_at'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(map['updated_at'] ?? DateTime.now().toIso8601String()),
    );
  }
}

class DashboardStats {
  final int totalProducts;
  final int activeWaves;
  final int pendingOrders;
  final int activePickers;
  final int lowStockAlerts;
  final double systemEfficiency;

  DashboardStats({
    this.totalProducts = 0,
    this.activeWaves = 0,
    this.pendingOrders = 0,
    this.activePickers = 0,
    this.lowStockAlerts = 0,
    this.systemEfficiency = 0.0,
  });

  factory DashboardStats.fromMap(Map<String, dynamic> map) {
    return DashboardStats(
      totalProducts: map['totalProducts'] ?? 0,
      activeWaves: map['activeWaves'] ?? 0,
      pendingOrders: map['pendingOrders'] ?? 0,
      activePickers: map['activePickers'] ?? 0,
      lowStockAlerts: map['lowStockAlerts'] ?? 0,
      systemEfficiency: (map['systemEfficiency'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'totalProducts': totalProducts,
      'activeWaves': activeWaves,
      'pendingOrders': pendingOrders,
      'activePickers': activePickers,
      'lowStockAlerts': lowStockAlerts,
      'systemEfficiency': systemEfficiency,
    };
  }
}

