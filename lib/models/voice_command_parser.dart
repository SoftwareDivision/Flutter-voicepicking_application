import 'dart:math';
import 'package:flutter/foundation.dart';

class VoiceCommandParser {
  static const double _similarityThreshold = 0.65;
  
  // ✅ Enhanced command variations with phonetic alternatives
  static const Map<String, List<String>> _commandVariations = {
    'READY': [
      'READY', 'REDE', 'REDDY', 'REDY', 'WREADY', 'RADI', 'RAEDY',
      'YES', 'OK', 'OKAY', 'GO', 'START', 'BEGIN', 'PROCEED', 'CONTINUE',
      'YESS', 'OKEI', 'OKES', 'OKAYS', 'GOES', 'STARTS'
    ],
    '91': [
      'NINETY ONE', 'NINE ONE', '91', 'NINE TEEN ONE', 'NINETEEN ONE',
      'NINEDY ONE', 'NIGHTY ONE', '9 1', 'NINTY ONE', 'NINTY WAN'
    ],
    '45': [
      'FORTY FIVE', 'FOUR FIVE', '45', 'FOURTY FIVE', 'FOR FIVE', '4 5',
      'FORTY FIFE', 'FOURTY FIFE', 'FOR FIFE'
    ],
    '78': [
      'SEVENTY EIGHT', 'SEVEN EIGHT', '78', 'SEVENTY ATE', 'SEVENTY EIGHT', '7 8',
      'SEBEN EIGHT', 'SEBEN ATE'
    ],
    '89': [
      'EIGHTY NINE', 'EIGHT NINE', '89', 'IGHTY NINE', 'EIGHTY NIEN', '8 9',
      'ATELY NINE', 'ATELY NIEN'
    ],
    '34': [
      'THIRTY FOUR', 'THREE FOUR', '34', 'THRITY FOUR', 'THIRTY FOR', '3 4',
      'TREE FOUR', 'TREE FOR'
    ],
    '67': [
      'SIXTY SEVEN', 'SIX SEVEN', '67', 'SIXTY SEBEN', 'SIXY SEVEN', '6 7',
      'SICK SEVEN', 'SICK SEBEN'
    ],
    '23': [
      'TWENTY THREE', 'TWO THREE', '23', 'TWENTY TREE', 'TWENY THREE', '2 3',
      'TO THREE', 'TO TREE'
    ],
    '56': [
      'FIFTY SIX', 'FIVE SIX', '56', 'FIFTHY SIX', 'FIFTY SICK', '5 6',
      'FIFE SIX', 'FIFE SICK'
    ],
    '960': [
      'NINE SIX ZERO', 'NINE SIXTY', '960', 'NIEN SIX ZERO', 'NINE SICK ZERO',
      '9 6 0', 'NINE SIX OH', 'NINE-SIX-ZERO', 'NIEN SICK ZERO'
    ],
    '123': [
      'ONE TWO THREE', 'ONE TWENTY THREE', '123', 'WAN TWO THREE', 'ONE TO THREE',
      '1 2 3', 'ONE-TWO-THREE', 'WAN TO TREE'
    ],
    '456': [
      'FOUR FIVE SIX', 'FOUR FIFTY SIX', '456', 'FOR FIVE SIX', 'FOUR FIVE SICK',
      '4 5 6', 'FOUR-FIVE-SIX', 'FOR FIFE SICK'
    ],
    '789': [
      'SEVEN EIGHT NINE', 'SEVEN EIGHTY NINE', '789', 'SEBEN EIGHT NINE',
      '7 8 9', 'SEVEN-EIGHT-NINE', 'SEBEN ATE NIEN'
    ],
    '012': [
      'ZERO ONE TWO', 'OH ONE TWO', '012', 'ZERO WAN TWO', 'O ONE TWO',
      '0 1 2', 'ZERO-ONE-TWO', 'OH WAN TO'
    ],
    '345': [
      'THREE FOUR FIVE', 'THREE FORTY FIVE', '345', 'TREE FOR FIVE',
      '3 4 5', 'THREE-FOUR-FIVE', 'TREE FOR FIFE'
    ],
    '678': [
      'SIX SEVEN EIGHT', 'SIX SEVENTY EIGHT', '678', 'SICK SEVEN EIGHT',
      '6 7 8', 'SIX-SEVEN-EIGHT', 'SICK SEBEN ATE'
    ],
    '901': [
      'NINE ZERO ONE', 'NINE OH ONE', '901', 'NIEN ZERO ONE', 'NINE O ONE',
      '9 0 1', 'NINE-ZERO-ONE', 'NIEN OH WAN'
    ],
    '1': ['ONE', 'WAN', 'WON', '1', 'SINGLE', 'FIST'],
    '2': ['TWO', 'TO', 'TOO', 'TU', '2', 'COUPLE', 'PAIR'],
    '3': ['THREE', 'TREE', 'FREE', '3', 'TRIPLE', 'THIRD'],
    '4': ['FOUR', 'FOR', 'FORE', '4', 'FORTH'],
    '5': ['FIVE', 'FIFE', '5', 'FIFTH'],
    '6': ['SIX', 'SICK', '6', 'SIXTH'],
    '7': ['SEVEN', 'SEBEN', '7', 'SEVENTH'],
    '8': ['EIGHT', 'ATE', '8', 'EIGHTH'],
    '9': ['NINE', 'NIEN', '9', 'NINTH'],
    '0': ['ZERO', 'OH', 'O', '0', 'NOTHING'],
  };

  // ✅ Enhanced parsing with phonetic matching
  static String parseCommand(String voiceInput, List<String> expectedCommands) {
    try {
      if (voiceInput.isEmpty) {
        debugPrint('⚠️ Empty voice input received');
        return '';
      }
      
      String cleanInput = _cleanVoiceInput(voiceInput);
      debugPrint('🎤 Parsing: "$cleanInput" against expected: $expectedCommands');
      
      // ✅ Direct match first (fastest)
      if (expectedCommands.contains(cleanInput)) {
        debugPrint('✅ Direct match found: $cleanInput');
        return cleanInput;
      }
      
      // ✅ Check variations with enhanced matching
      for (String expectedCommand in expectedCommands) {
        List<String> variations = _commandVariations[expectedCommand] ?? [expectedCommand];
        
        for (String variation in variations) {
          if (_isPhoneticMatch(cleanInput, variation)) {
            debugPrint('✅ Phonetic match: "$cleanInput" -> "$expectedCommand"');
            return expectedCommand;
          }
        }
      }
      
      // ✅ Enhanced fuzzy matching with multiple algorithms
      String bestMatch = '';
      double bestSimilarity = 0.0;
      
      for (String expectedCommand in expectedCommands) {
        // Check direct similarity
        double similarity = _calculateEnhancedSimilarity(cleanInput, expectedCommand);
        
        if (similarity > bestSimilarity && similarity >= _similarityThreshold) {
          bestSimilarity = similarity;
          bestMatch = expectedCommand;
        }
        
        // Check variations
        List<String> variations = _commandVariations[expectedCommand] ?? [expectedCommand];
        for (String variation in variations) {
          double varSimilarity = _calculateEnhancedSimilarity(cleanInput, variation);
          if (varSimilarity > bestSimilarity && varSimilarity >= _similarityThreshold) {
            bestSimilarity = varSimilarity;
            bestMatch = expectedCommand;
          }
        }
      }
      
      if (bestMatch.isNotEmpty) {
        debugPrint('✅ Enhanced fuzzy match: "$cleanInput" -> "$bestMatch" (${(bestSimilarity * 100).toInt()}%)');
        return bestMatch;
      }
      
      debugPrint('❌ No match found for: "$cleanInput"');
      return '';
      
    } catch (e) {
      debugPrint('❌ Command parsing error: $e');
      return '';
    }
  }
  
  // ✅ Enhanced phonetic matching
  static bool _isPhoneticMatch(String input, String target) {
    try {
      if (input == target) return true;
      
      // Convert to phonetic representations
      String phoneticInput = _toPhonetic(input);
      String phoneticTarget = _toPhonetic(target);
      
      if (phoneticInput == phoneticTarget) return true;
      
      // Check similarity of phonetic representations
      double similarity = _calculateSimilarity(phoneticInput, phoneticTarget);
      return similarity >= 0.8; // Higher threshold for phonetic matching
      
    } catch (e) {
      debugPrint('❌ Phonetic matching error: $e');
      return false;
    }
  }
  
  // ✅ Simple phonetic conversion
  static String _toPhonetic(String input) {
    try {
      return input
          .replaceAll('PH', 'F')
          .replaceAll('TH', 'T')
          .replaceAll('CK', 'K')
          .replaceAll('QU', 'KW')
          .replaceAll('X', 'KS')
          .replaceAll('Z', 'S')
          .replaceAll('C', 'K')
          .replaceAll('J', 'G')
          .replaceAll('Y', 'I')
          .replaceAll('W', 'V');
    } catch (e) {
      return input;
    }
  }
  
  // ✅ Enhanced similarity calculation
  static double _calculateEnhancedSimilarity(String s1, String s2) {
    try {
      // Combine multiple similarity metrics
      double levenshtein = _calculateSimilarity(s1, s2);
      double jaro = _calculateJaroSimilarity(s1, s2);
      double phonetic = _calculateSimilarity(_toPhonetic(s1), _toPhonetic(s2));
      
      // Weighted combination
      return (levenshtein * 0.4) + (jaro * 0.4) + (phonetic * 0.2);
    } catch (e) {
      debugPrint('❌ Enhanced similarity error: $e');
      return 0.0;
    }
  }
  
  // ✅ Jaro similarity algorithm
  static double _calculateJaroSimilarity(String s1, String s2) {
    try {
      if (s1 == s2) return 1.0;
      if (s1.isEmpty || s2.isEmpty) return 0.0;
      
      int matchWindow = max(s1.length, s2.length) ~/ 2 - 1;
      if (matchWindow < 0) matchWindow = 0;
      
      List<bool> s1Matches = List.filled(s1.length, false);
      List<bool> s2Matches = List.filled(s2.length, false);
      
      int matches = 0;
      int transpositions = 0;
      
      // Find matches
      for (int i = 0; i < s1.length; i++) {
        int start = max(0, i - matchWindow);
        int end = min(i + matchWindow + 1, s2.length);
        
        for (int j = start; j < end; j++) {
          if (s2Matches[j] || s1[i] != s2[j]) continue;
          s1Matches[i] = s2Matches[j] = true;
          matches++;
          break;
        }
      }
      
      if (matches == 0) return 0.0;
      
      // Find transpositions
      int k = 0;
      for (int i = 0; i < s1.length; i++) {
        if (!s1Matches[i]) continue;
        // ✅ FIXED: Added braces around while loop body
        while (!s2Matches[k]) {
          k++;
        }
        if (s1[i] != s2[k]) transpositions++;
        k++;
      }
      
      return (matches / s1.length + matches / s2.length + 
              (matches - transpositions / 2) / matches) / 3.0;
    } catch (e) {
      return 0.0;
    }
  }
  
  static String _cleanVoiceInput(String input) {
    try {
      return input
          .toUpperCase()
          .trim()
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(r'-'), ' ');
    } catch (e) {
      debugPrint('❌ Input cleaning error: $e');
      return input.toUpperCase().trim();
    }
  }
  
  static double _calculateSimilarity(String s1, String s2) {
    try {
      if (s1 == s2) return 1.0;
      if (s1.isEmpty || s2.isEmpty) return 0.0;
      
      int distance = _levenshteinDistance(s1, s2);
      int maxLength = max(s1.length, s2.length);
      
      return 1.0 - (distance / maxLength);
    } catch (e) {
      debugPrint('❌ Similarity calculation error: $e');
      return 0.0;
    }
  }
  
  static int _levenshteinDistance(String s1, String s2) {
    try {
      List<List<int>> matrix = List.generate(
        s1.length + 1,
        (i) => List.filled(s2.length + 1, 0),
      );
      
      for (int i = 0; i <= s1.length; i++) {
        matrix[i][0] = i;
      }
      
      for (int j = 0; j <= s2.length; j++) {
        matrix[0][j] = j;
      }
      
      for (int i = 1; i <= s1.length; i++) {
        for (int j = 1; j <= s2.length; j++) {
          int cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
          
          matrix[i][j] = [
            matrix[i - 1][j] + 1,
            matrix[i][j - 1] + 1,
            matrix[i - 1][j - 1] + cost
          ].reduce(min);
        }
      }
      
      return matrix[s1.length][s2.length];
    } catch (e) {
      debugPrint('❌ Levenshtein calculation error: $e');
      return s1.length + s2.length;
    }
  }
  
  static List<String> getExpectedCommands(String currentState, Map<String, dynamic>? currentItem) {
    try {
      switch (currentState) {
        case 'ready':
        case 'readyWait':
          return ['READY'];
          
        case 'locationCheck':
          if (currentItem != null) {
            String digit = currentItem['locationCheckDigit']?.toString() ?? '';
            return digit.isNotEmpty ? [digit] : [];
          }
          return [];
          
        case 'itemCheck':
          if (currentItem != null) {
            String digits = currentItem['barcodeDigits']?.toString() ?? '';
            return digits.isNotEmpty ? [digits] : [];
          }
          return [];
          
        case 'quantityCheck':
          if (currentItem != null) {
            String quantity = currentItem['quantity']?.toString() ?? '';
            return quantity.isNotEmpty ? [quantity] : [];
          }
          return [];
          
        default:
          debugPrint('⚠️ Unknown state: $currentState');
          return [];
      }
    } catch (e) {
      debugPrint('❌ Expected commands error: $e');
      return [];
    }
  }
}
