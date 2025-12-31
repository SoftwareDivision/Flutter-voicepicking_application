// lib/utils/currency.dart

import 'package:flutter/material.dart';

class CurrencyHelper {
  // ✅ Single source of truth for currency
  static const String symbol = '₹';  // Rupees
  static const String code = 'INR';
  static const String name = 'Indian Rupee';
  
  /// Format price with currency symbol
  static String format(double amount, {bool compact = false}) {
    if (compact && amount >= 10000000) {
      return '$symbol${(amount / 10000000).toStringAsFixed(2)}Cr';
    } else if (compact && amount >= 100000) {
      return '$symbol${(amount / 100000).toStringAsFixed(2)}L';
    } else if (compact && amount >= 1000) {
      return '$symbol${(amount / 1000).toStringAsFixed(1)}K';
    }
    return '$symbol${amount.toStringAsFixed(2)}';
  }
  
  /// Format for display with symbol
  static String display(dynamic value) {
    final amount = _parseAmount(value);
    return '$symbol${amount.toStringAsFixed(2)}';
  }
  
  /// Format for reports/exports (without symbol)
  static String exportFormat(dynamic value) {
    final amount = _parseAmount(value);
    return amount.toStringAsFixed(2);
  }
  
  /// Parse amount from various types
  static double _parseAmount(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }
  
  /// Get currency icon (Material Icon)
  static IconData get icon => Icons.currency_rupee; // Use this instead of Icons.attach_money
}
