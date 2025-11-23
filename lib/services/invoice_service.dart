import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Service to manage invoice numbering
class InvoiceService {
  InvoiceService._internal();
  static final InvoiceService _instance = InvoiceService._internal();
  factory InvoiceService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _counterCollection = 'counters';
  static const String _invoiceCounterDoc = 'invoice_counter';

  /// Get the next invoice number and increment counter
  Future<int> getNextInvoiceNumber() async {
    try {
      final counterRef = _firestore
          .collection(_counterCollection)
          .doc(_invoiceCounterDoc);

      // Use transaction to ensure atomic increment
      final newInvoiceNumber = await _firestore.runTransaction<int>((transaction) async {
        final snapshot = await transaction.get(counterRef);

        int currentNumber;
        if (!snapshot.exists) {
          // Initialize counter if it doesn't exist
          currentNumber = 1;
          transaction.set(counterRef, {
            'currentNumber': currentNumber,
            'lastUpdated': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
          });
        } else {
          // Increment existing counter
          currentNumber = (snapshot.data()?['currentNumber'] ?? 0) + 1;
          transaction.update(counterRef, {
            'currentNumber': currentNumber,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
        }

        return currentNumber;
      });

      debugPrint('✅ New invoice number: $newInvoiceNumber');
      return newInvoiceNumber;
    } catch (e) {
      debugPrint('❌ Error getting invoice number: $e');
      // Fallback to timestamp-based number
      return DateTime.now().millisecondsSinceEpoch % 1000000;
    }
  }

  /// Get current invoice number without incrementing
  Future<int> getCurrentInvoiceNumber() async {
    try {
      final snapshot = await _firestore
          .collection(_counterCollection)
          .doc(_invoiceCounterDoc)
          .get();

      if (snapshot.exists) {
        return snapshot.data()?['currentNumber'] ?? 0;
      }
      return 0;
    } catch (e) {
      debugPrint('Error getting current invoice number: $e');
      return 0;
    }
  }

  /// Reset counter (admin function)
  Future<void> resetCounter({int startFrom = 1}) async {
    await _firestore
        .collection(_counterCollection)
        .doc(_invoiceCounterDoc)
        .set({
      'currentNumber': startFrom - 1,
      'lastUpdated': FieldValue.serverTimestamp(),
      'resetAt': FieldValue.serverTimestamp(),
    });
    debugPrint('✅ Invoice counter reset to start from $startFrom');
  }
}