// lib/utils/shipment_validation.dart

class ShipmentValidation {
  /// Validate truck number format (e.g., MH12AB1234)
  static String? validateTruckNumber(String? truckNumber) {
    if (truckNumber == null || truckNumber.isEmpty) {
      return 'Truck number is required';
    }
    
    final cleaned = truckNumber.replaceAll(' ', '').toUpperCase();
    final regex = RegExp(r'^[A-Z]{2}\d{2}[A-Z]{1,2}\d{4}$');
    
    if (!regex.hasMatch(cleaned)) {
      return 'Invalid format. Expected: MH12AB1234';
    }
    return null;
  }

  /// Validate Indian phone number
  static String? validatePhoneNumber(String? phone) {
    if (phone == null || phone.isEmpty) {
      return 'Phone number is required';
    }
    
    final cleaned = phone.replaceAll(RegExp(r'[^\d]'), '');
    
    if (cleaned.length != 10) {
      return 'Phone number must be 10 digits';
    }
    
    if (!cleaned.startsWith(RegExp(r'[6-9]'))) {
      return 'Invalid phone number';
    }
    
    return null;
  }

  /// Validate driver name
  static String? validateDriverName(String? name) {
    if (name == null || name.isEmpty) {
      return 'Driver name is required';
    }
    
    if (name.length < 3) {
      return 'Name must be at least 3 characters';
    }
    
    return null;
  }

  /// Validate AWB number
  static String? validateAWBNumber(String? awb) {
    if (awb == null || awb.isEmpty) {
      return 'AWB number is required';
    }
    
    if (awb.length < 8) {
      return 'Invalid AWB number';
    }
    
    return null;
  }

  /// Validate destination address
  static String? validateDestination(String? destination) {
    if (destination == null || destination.isEmpty) {
      return 'Destination is required';
    }
    
    if (destination.length < 10) {
      return 'Please enter complete destination address';
    }
    
    return null;
  }

  /// Validate contact person name
  static String? validateContactPerson(String? name) {
    if (name == null || name.isEmpty) {
      return 'Contact person name is required';
    }
    
    if (name.length < 3) {
      return 'Name must be at least 3 characters';
    }
    
    return null;
  }

  /// Validate ID proof
  static String? validateIDProof(String? idProof) {
    if (idProof == null || idProof.isEmpty) {
      return 'ID proof number is required';
    }
    
    if (idProof.length < 6) {
      return 'Invalid ID proof number';
    }
    
    return null;
  }
}
