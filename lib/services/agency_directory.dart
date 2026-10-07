import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/agence_model.dart';
import 'functions_client.dart';

/// An agency found for the applicant's neighbourhood.
class AgencyMatch {
  const AgencyMatch(this.agence, {this.zone});

  final AgenceModel agence;

  /// The agency's registered zone that matched (null when only its city /
  /// address matched).
  final String? zone;
}

/// Agencies an applicant can apply to: only those covered by an active
/// Agency Manager (an application to an agency without a manager would be
/// invisible in every backoffice).
class AgencyDirectory {
  const AgencyDirectory({
    required this.agences,
    required this.hasManagerlessAgencies,
    this.zones = const {},
  });

  final List<AgenceModel> agences;

  /// Agencies exist but NONE has an active manager (guides the applicant).
  final bool hasManagerlessAgencies;

  /// Neighbourhoods served by each agency (`agenceId` → zone names), as
  /// defined by its manager in the backoffice.
  final Map<String, List<String>> zones;

  /// Agencies serving the neighbourhood [input] (« Bastos », « Yaoundé:
  /// Etoudi », « carrefour Mvan »…), best matches first: an agency whose
  /// registered zone matches, then one whose city / address matches.
  /// Accents and case are ignored. Empty when no agency covers it.
  List<AgencyMatch> agenciesForZone(String input) {
    final keys = _keys(input);
    if (keys.isEmpty) return const [];
    final byZone = <AgencyMatch>[];
    final byPlace = <AgencyMatch>[];
    for (final a in agences) {
      final zone = (zones[a.id] ?? const <String>[]).firstWhere(
        (z) => _matches(keys, normalize(z)),
        orElse: () => '',
      );
      if (zone.isNotEmpty) {
        byZone.add(AgencyMatch(a, zone: zone));
      } else if (_matches(keys, normalize('${a.ville} ${a.location}'),
          oneWay: true)) {
        byPlace.add(AgencyMatch(a));
      }
    }
    return [...byZone, ...byPlace];
  }

  /// Lower case, no accents, single spaces.
  static String normalize(String value) {
    const from = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿœæ';
    const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
    final out = StringBuffer();
    for (final ch in value.toLowerCase().split('')) {
      final i = from.indexOf(ch);
      out.write(i >= 0 ? to[i] : ch);
    }
    return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// « Yaoundé: Bastos, Rue 1.750 » → [yaounde: bastos, rue 1.750, yaounde,
  /// bastos, rue 1.750] (pieces shorter than 3 letters are ignored).
  static List<String> _keys(String input) {
    final full = normalize(input);
    if (full.length < 3) return const [];
    final parts = full
        .split(RegExp(r'[:,;/\-]'))
        .map((s) => s.trim())
        .where((s) => s.length >= 3);
    return {full, ...parts}.toList();
  }

  /// A zone matches when it equals, contains or is contained in a key.
  /// [oneWay]: the target (city + address text) must contain the key.
  static bool _matches(List<String> keys, String target, {bool oneWay = false}) {
    if (target.length < 3) return false;
    return keys.any((k) =>
        target.contains(k) || (!oneWay && k.contains(target)));
  }

  /// Production: the `publicAgencies` Cloud Function — signed-out visitors
  /// cannot read `utilisateurs` (staff accounts) under the Firestore rules.
  static Future<AgencyDirectory> fromPublicFunction({
    FunctionsClient? functions,
  }) async {
    final data =
        await (functions ?? FunctionsClient()).getPublic('publicAgencies');
    final list = (data['agences'] as List<dynamic>? ?? const [])
        .map((e) => AgenceModel.fromMap(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.ville.compareTo(b.ville));
    final zones = <String, List<String>>{};
    (data['zones'] as Map<String, dynamic>? ?? const {}).forEach((id, names) {
      zones[id] = (names as List<dynamic>).whereType<String>().toList();
    });
    return AgencyDirectory(
      agences: list,
      zones: zones,
      hasManagerlessAgencies: data['hasManagerlessAgencies'] as bool? ?? false,
    );
  }

  /// Direct Firestore read (tests / emulator, or a signed-in staff device).
  /// Mirrors `publicAgencies` in functions/index.js.
  static Future<AgencyDirectory> fromFirestore(FirebaseFirestore db) async {
    final results = await Future.wait<QuerySnapshot<Map<String, dynamic>>>([
      db.collection('agences').get(),
      db.collection('utilisateurs').get(),
      db.collection('zones').get(),
    ]);
    final agencesSnap = results[0];
    final usersSnap = results[1];
    final zonesSnap = results[2];

    final managed = <String>{};
    for (final d in usersSnap.docs) {
      final data = d.data();
      final role =
          (data['role'] as String? ?? '').toLowerCase().replaceAll("'", '');
      final isManager =
          role == 'agency manager' || role == 'responsable dagence';
      final status = (data['status'] as String? ?? '').toLowerCase();
      final agenceId = data['agenceId'] as String? ?? '';
      if (isManager &&
          (status == 'active' || status == 'actif') &&
          agenceId.isNotEmpty) {
        managed.add(agenceId);
      }
    }

    final all = agencesSnap.docs
        .map((d) => AgenceModel.fromMap(d.data()))
        .toList()
      ..sort((a, b) => a.ville.compareTo(b.ville));
    final list = all.where((a) => managed.contains(a.id)).toList();

    final zones = <String, List<String>>{};
    for (final d in zonesSnap.docs) {
      final z = d.data();
      final agenceId = z['agenceId'] as String? ?? '';
      final name = z['name'] as String? ?? '';
      final status = (z['status'] as String? ?? 'active').toLowerCase();
      if (!managed.contains(agenceId) || name.isEmpty ||
          status == 'inactive' || status == 'inactif') {
        continue;
      }
      (zones[agenceId] ??= []).add(name);
    }
    return AgencyDirectory(
      agences: list,
      zones: zones,
      hasManagerlessAgencies: all.isNotEmpty && list.isEmpty,
    );
  }
}
