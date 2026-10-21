import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/referrer_model.dart';
import '../models/sale_model.dart';

/// Plumbers/painters plus every real sale tagged with one of them,
/// delivered together so business totals are always consistent.
class ReferrerData {
  final List<Referrer> referrers;

  /// Non-mock sales linked to a referrer.
  final List<Sale> sales;

  ReferrerData({required this.referrers, required this.sales});

  /// [referrerId]'s sales made in [year] (all years when null), newest first.
  List<Sale> salesFor(String referrerId, {int? year}) => sales
      .where((s) =>
          s.referrerId == referrerId &&
          (year == null || s.createdAt.year == year))
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Years that have at least one referred sale, plus the current year,
  /// newest first.
  List<int> get years {
    final set = {DateTime.now().year, for (final s in sales) s.createdAt.year};
    return set.toList()..sort((a, b) => b.compareTo(a));
  }
}

/// Business brought by a referrer over a period.
class ReferrerBusiness {
  final int bills;
  final double amount;
  final double profit;

  /// Incentive already paid to them on the spot, across these sales.
  final double incentivePaid;

  const ReferrerBusiness(
      this.bills, this.amount, this.profit, this.incentivePaid);

  /// What the shop kept after paying their incentives.
  double get netProfit => profit - incentivePaid;

  /// Totals [sales]. A sale's total already excludes anything returned.
  factory ReferrerBusiness.of(List<Sale> sales) {
    double amount = 0, profit = 0, incentive = 0;
    for (final sale in sales) {
      amount += sale.totalAmount;
      incentive += sale.referrerIncentive ?? 0;
      for (final item in sale.items) {
        profit += (item.salePrice - item.purchasePrice) * item.quantity;
      }
    }
    return ReferrerBusiness(sales.length, amount, profit, incentive);
  }
}

class ReferrerService {
  static final ReferrerService _instance = ReferrerService._internal();
  factory ReferrerService() => _instance;
  ReferrerService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _referrersCollection = 'referrers';
  static const String _salesCollection = 'sales';

  CollectionReference<Map<String, dynamic>> get _referrers =>
      _firestore.collection(_referrersCollection);

  /// Referrers and referred sales, re-emitted whenever either changes.
  Stream<ReferrerData> watch() {
    late StreamController<ReferrerData> controller;
    final subs = <StreamSubscription>[];
    List<Referrer>? referrers;
    List<Sale>? sales;

    void emit() {
      if (referrers == null || sales == null) return;
      controller.add(ReferrerData(referrers: referrers!, sales: sales!));
    }

    controller = StreamController<ReferrerData>(
      onListen: () {
        subs.add(_referrers.snapshots().listen((snap) {
          referrers = snap.docs.map(Referrer.fromFirestore).toList()
            ..sort((a, b) =>
                a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          emit();
        }, onError: controller.addError));
        subs.add(_firestore
            .collection(_salesCollection)
            .where('referrerId', isGreaterThan: '')
            .snapshots()
            .listen((snap) {
          sales = snap.docs
              .map(Sale.fromFirestore)
              .where((s) => !s.isMock)
              .toList();
          emit();
        }, onError: controller.addError));
      },
      onCancel: () async {
        for (final sub in subs) {
          await sub.cancel();
        }
      },
    );
    return controller.stream;
  }

  Future<List<Referrer>> getReferrers() async {
    final snap = await _referrers.get();
    return snap.docs.map(Referrer.fromFirestore).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<Referrer> addReferrer(Referrer referrer) async {
    final ref = await _referrers.add(referrer.toFirestore());
    return referrer.copyWith(id: ref.id);
  }

  /// Saves [referrer] and renames it on the sales it's tagged on, so bills
  /// and the sales list show the current name.
  Future<void> updateReferrer(Referrer referrer) async {
    await _referrers.doc(referrer.id).update(referrer.toFirestore());
    final sales = await _firestore
        .collection(_salesCollection)
        .where('referrerId', isEqualTo: referrer.id)
        .get();
    final stale =
        sales.docs.where((d) => d.data()['referrerName'] != referrer.name);
    // Firestore batches cap at 500 writes.
    var batch = _firestore.batch();
    var count = 0;
    for (final doc in stale) {
      batch.update(doc.reference, {'referrerName': referrer.name});
      if (++count == 400) {
        await batch.commit();
        batch = _firestore.batch();
        count = 0;
      }
    }
    if (count > 0) await batch.commit();
  }

  /// Deletes a referrer only when no sale is tagged with them, so their
  /// business history is never lost by accident.
  Future<void> deleteReferrer(Referrer referrer) async {
    final sales = await _firestore
        .collection(_salesCollection)
        .where('referrerId', isEqualTo: referrer.id)
        .limit(1)
        .get();
    if (sales.docs.isNotEmpty) {
      throw Exception(
          '${referrer.name} is tagged on sales. Remove them from those sales first.');
    }
    await _referrers.doc(referrer.id).delete();
  }
}
