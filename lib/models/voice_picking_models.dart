// lib/models/voice_picking_models.dart

class VoicePickingTask {
  final String id;
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
  
  // Inventory details
  final String? itemName;
  final String? sku;
  final String? barcode;
  final int? availableQuantity;
  final String? category;
  
  // Order details
  final String? orderNumber;
  final String? customerName;
  final String? orderPriority;

  VoicePickingTask({
    required this.id,
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
    this.itemName,
    this.sku,
    this.barcode,
    this.availableQuantity,
    this.category,
    this.orderNumber,
    this.customerName,
    this.orderPriority,
  });

  factory VoicePickingTask.fromMap(Map<String, dynamic> map) {
    // Extract inventory data if available
    final inventory = map['inventory'] as Map<String, dynamic>?;
    final orders = map['orders'] as Map<String, dynamic>?;

    return VoicePickingTask(
      id: map['id'] ?? '',
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
      
      // Inventory fields
      itemName: inventory?['name'],
      sku: inventory?['sku'],
      barcode: inventory?['barcode'],
      availableQuantity: inventory?['quantity'],
      category: inventory?['category'],
      
      // Order fields
      orderNumber: orders?['order_number'],
      customerName: orders?['customer_name'],
      orderPriority: orders?['priority'],
    );
  }

  // Get location check digit (last digit of location)
  String get locationCheckDigit {
    if (location == null || location!.isEmpty) return '0';
    final digits = location!.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isNotEmpty ? digits[digits.length - 1] : '0';
  }

  // Get barcode check digits (last 3 digits)
  String get barcodeCheckDigits {
    if (barcode == null || barcode!.isEmpty) return '000';
    final digits = barcode!.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 3) {
      return digits.substring(digits.length - 3);
    }
    return digits.padLeft(3, '0');
  }

  // Check if item is ready for picking
  bool get isReadyForPicking {
    return status == 'pending' || status == 'in_progress';
  }

  // Check if sufficient quantity available
  bool get hasSufficientQuantity {
    return (availableQuantity ?? 0) >= quantityRequested;
  }

  // Get display priority
  String get displayPriority {
    switch (priority.toLowerCase()) {
      case 'high':
        return 'HIGH';
      case 'medium':
        return 'MED';
      case 'low':
        return 'LOW';
      default:
        return 'NORM';
    }
  }
}

class VoicePickingSession {
  final String sessionId;
  final String pickerName;
  final List<VoicePickingTask> tasks;
  final DateTime startTime;
  DateTime? endTime;
  int completedTasks;
  int totalQuantityPicked;
  String status;

  VoicePickingSession({
    required this.sessionId,
    required this.pickerName,
    required this.tasks,
    required this.startTime,
    this.endTime,
    this.completedTasks = 0,
    this.totalQuantityPicked = 0,
    this.status = 'active',
  });

  // Get session duration
  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }

  // Get completion percentage
  double get completionPercentage {
    if (tasks.isEmpty) return 0.0;
    return (completedTasks / tasks.length) * 100;
  }

  // Get average time per pick
  Duration get averageTimePerPick {
    if (completedTasks == 0) return Duration.zero;
    return Duration(seconds: duration.inSeconds ~/ completedTasks);
  }

  // Get remaining tasks
  List<VoicePickingTask> get remainingTasks {
    return tasks.where((task) => task.status != 'completed').toList();
  }

  // Get current task
  VoicePickingTask? get currentTask {
    final remaining = remainingTasks;
    return remaining.isNotEmpty ? remaining.first : null;
  }

  // Complete a task
  void completeTask(String taskId, int quantityPicked) {
    final taskIndex = tasks.indexWhere((task) => task.id == taskId);
    if (taskIndex != -1) {
      completedTasks++;
      totalQuantityPicked += quantityPicked;
      
      if (completedTasks >= tasks.length) {
        status = 'completed';
        endTime = DateTime.now();
      }
    }
  }
}

class VoicePickingStats {
  final int todayPicks;
  final int todayQuantity;
  final int totalPicks;
  final int totalQuantity;
  final int pendingPicks;
  final String efficiency;

  VoicePickingStats({
    this.todayPicks = 0,
    this.todayQuantity = 0,
    this.totalPicks = 0,
    this.totalQuantity = 0,
    this.pendingPicks = 0,
    this.efficiency = '0.0',
  });

  factory VoicePickingStats.fromMap(Map<String, dynamic> map) {
    return VoicePickingStats(
      todayPicks: map['today_picks'] ?? 0,
      todayQuantity: map['today_quantity'] ?? 0,
      totalPicks: map['total_picks'] ?? 0,
      totalQuantity: map['total_quantity'] ?? 0,
      pendingPicks: map['pending_picks'] ?? 0,
      efficiency: map['efficiency'] ?? '0.0',
    );
  }
}
