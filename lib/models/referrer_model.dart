import 'package:cloud_firestore/cloud_firestore.dart';

/// The trade of someone who brings customers to the shop.
enum ReferrerType {
  plumber,
  painter;

  String get label => this == ReferrerType.plumber ? 'Plumber' : 'Painter';

  static ReferrerType fromName(String? name) => ReferrerType.values
      .firstWhere((t) => t.name == name, orElse: () => ReferrerType.plumber);
}

/// A plumber or painter whose customers buy from the shop. Sales they
/// bring are tagged with their id (see [Sale.referrerId]) so their yearly
/// business can be totalled up to decide their perks.
class Referrer {
  final String id;
  final String name;
  final String? phone;
  final ReferrerType type;
  final DateTime createdAt;

  Referrer({
    required this.id,
    required this.name,
    required this.type,
    this.phone,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'phone': phone,
        'type': type.name,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  factory Referrer.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Referrer(
      id: doc.id,
      name: data['name'] ?? '',
      phone: data['phone'],
      type: ReferrerType.fromName(data['type'] as String?),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Referrer copyWith({String? id, String? name, String? phone, ReferrerType? type}) =>
      Referrer(
        id: id ?? this.id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        type: type ?? this.type,
        createdAt: createdAt,
      );
}
