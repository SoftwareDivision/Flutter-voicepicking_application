class PickingItem {
  final String location;
  final int slot;
  final String locationCheckDigit;
  final String itemCode;
  final String barcodeDigits;
  final String itemName;
  final int quantity;
  final String priority;
  final String category;
  final double weight;

  const PickingItem({
    required this.location,
    required this.slot,
    required this.locationCheckDigit,
    required this.itemCode,
    required this.barcodeDigits,
    required this.itemName,
    required this.quantity,
    required this.priority,
    required this.category,
    required this.weight, required String id,
  });

  Map<String, dynamic> toJson() {
    return {
      'location': location,
      'slot': slot,
      'locationCheckDigit': locationCheckDigit,
      'itemCode': itemCode,
      'barcodeDigits': barcodeDigits,
      'itemName': itemName,
      'quantity': quantity,
      'priority': priority,
      'category': category,
      'weight': weight,
    };
  }

  factory PickingItem.fromJson(Map<String, dynamic> json) {
    return PickingItem(
      location: json['location'] ?? '',
      slot: json['slot'] ?? 0,
      locationCheckDigit: json['locationCheckDigit'] ?? '',
      itemCode: json['itemCode'] ?? '',
      barcodeDigits: json['barcodeDigits'] ?? '',
      itemName: json['itemName'] ?? '',
      quantity: json['quantity'] ?? 0,
      priority: json['priority'] ?? 'NORMAL',
      category: json['category'] ?? '',
      weight: json['weight'] ?? 0.0, id: '',
    );
  }
}

class PickingDataService {
  static const List<PickingItem> _samplePickingData = [
    PickingItem(
      location: 'A1',
      slot: 1,
      locationCheckDigit: '91',
      itemCode: 'ITM001',
      barcodeDigits: '960',
      itemName: 'Wireless Mouse Pro',
      quantity: 1,
      priority: 'HIGH',
      category: 'Electronics',
      weight: 0.2, id: '',
    ),
    PickingItem(
      location: 'A2',
      slot: 3,
      locationCheckDigit: '45',
      itemCode: 'ITM002',
      barcodeDigits: '123',
      itemName: 'USB Cable 2M',
      quantity: 2,
      priority: 'NORMAL',
      category: 'Accessories',
      weight: 0.1, id: '',
    ),
    PickingItem(
      location: 'B1',
      slot: 2,
      locationCheckDigit: '78',
      itemCode: 'ITM003',
      barcodeDigits: '456',
      itemName: 'Keyboard Mechanical',
      quantity: 1,
      priority: 'HIGH',
      category: 'Electronics',
      weight: 1.2, id: '',
    ),
    PickingItem(
      location: 'B3',
      slot: 4,
      locationCheckDigit: '89',
      itemCode: 'ITM004',
      barcodeDigits: '789',
      itemName: 'Monitor Stand',
      quantity: 3,
      priority: 'LOW',
      category: 'Furniture',
      weight: 2.5, id: '',
    ),
    PickingItem(
      location: 'C1',
      slot: 1,
      locationCheckDigit: '34',
      itemCode: 'ITM005',
      barcodeDigits: '012',
      itemName: 'Headset Wireless',
      quantity: 1,
      priority: 'HIGH',
      category: 'Electronics',
      weight: 0.3, id: '',
    ),
    PickingItem(
      location: 'C2',
      slot: 2,
      locationCheckDigit: '67',
      itemCode: 'ITM006',
      barcodeDigits: '345',
      itemName: 'Power Bank 20000mAh',
      quantity: 2,
      priority: 'NORMAL',
      category: 'Electronics',
      weight: 0.5, id: '',
    ),
    PickingItem(
      location: 'D1',
      slot: 1,
      locationCheckDigit: '23',
      itemCode: 'ITM007',
      barcodeDigits: '678',
      itemName: 'Bluetooth Speaker',
      quantity: 1,
      priority: 'HIGH',
      category: 'Electronics',
      weight: 0.8, id: '',
    ),
    PickingItem(
      location: 'D3',
      slot: 3,
      locationCheckDigit: '56',
      itemCode: 'ITM008',
      barcodeDigits: '901',
      itemName: 'Tablet Stand',
      quantity: 1,
      priority: 'LOW',
      category: 'Accessories',
      weight: 0.4, id: '',
    ),
  ];

  // ✅ Get all picking items
  static Future<List<PickingItem>> getPickingItems() async {
    try {
      // Simulate API call delay
      await Future.delayed(const Duration(milliseconds: 500));
      return List.from(_samplePickingData);
    } catch (e) {
      throw Exception('Failed to load picking items: $e');
    }
  }

  // ✅ Get items by priority
  static Future<List<PickingItem>> getItemsByPriority(String priority) async {
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      return _samplePickingData
          .where((item) => item.priority == priority)
          .toList();
    } catch (e) {
      throw Exception('Failed to filter items by priority: $e');
    }
  }

  // ✅ Get items by location
  static Future<List<PickingItem>> getItemsByLocation(String location) async {
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      return _samplePickingData
          .where((item) => item.location == location)
          .toList();
    } catch (e) {
      throw Exception('Failed to filter items by location: $e');
    }
  }

  // ✅ Simulate item completion
  static Future<bool> completeItem(String itemCode) async {
    try {
      await Future.delayed(const Duration(milliseconds: 200));
      return true;
    } catch (e) {
      throw Exception('Failed to complete item: $e');
    }
  }
}
