import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../features/backoffice/models.dart';

/// Génération et règlement automatiques des factures
/// (Paiements → Factures, génération automatique).
///
/// - [generateForContract] : facture créée avec un contrat backoffice.
///   Les factures des paiements CamPay sont créées côté serveur
///   (`settle` dans functions/index.js).
///
/// Injectable en test (suit le `db` du store quand non fourni).
class InvoiceService {
  InvoiceService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Crée la facture d'un nouveau contrat.
  ///
  /// [clientName] est facultatif : le flux client ne le connaît pas
  /// toujours au moment de la génération (la facture est identifiée par
  /// [clientId], clé `users`).
  Future<void> generateForContract({
    required String contractId,
    required String clientId,
    String clientName = '',
    required num amount,
    String status = 'Pending',
    String agenceId = '',
    String societeId = '',
    String source = 'contrats',
    String paymentRef = '',
  }) async {
    final id = 'FCT-$contractId';
    final facture = FactureModel(
      id: id,
      client: clientName,
      montant: amount.toInt(),
      echeance: '',
      status: status,
      clientId: clientId,
      contractId: contractId,
      paymentRef: paymentRef,
      paidAt: status.toLowerCase() == 'paid' ? _today() : '',
      agenceId: agenceId,
      societeId: societeId,
    );
    try {
      await _db.collection('factures').doc(id).set(facture.toMap());
    } catch (error) {
      // Best-effort : la création du contrat ne doit pas échouer parce que
      // la facture n'a pas pu être générée.
      debugPrint('InvoiceService.generateForContract failed: $error');
    }
  }

  String _today() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }
}
