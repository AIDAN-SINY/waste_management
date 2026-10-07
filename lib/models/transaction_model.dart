class TransactionModel {
  final String id;
  final String userId;
  final String type; // 'payment', 'refund', 'subscription'
  final double amount;
  final String currency; // 'XAF', 'USD', etc.
  final String status; // 'pending', 'completed', 'failed'
  final String paymentMethod; // 'momo', 'om', 'card'
  final DateTime createdAt;
  final String? description;

  TransactionModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    required this.currency,
    required this.status,
    required this.paymentMethod,
    required this.createdAt,
    this.description,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json['id'] as String,
      userId: json['userId'] as String,
      type: json['type'] as String,
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String,
      status: json['status'] as String,
      paymentMethod: json['paymentMethod'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'type': type,
      'amount': amount,
      'currency': currency,
      'status': status,
      'paymentMethod': paymentMethod,
      'createdAt': createdAt.toIso8601String(),
      'description': description,
    };
  }
}
