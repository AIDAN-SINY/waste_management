import 'package:flutter_test/flutter_test.dart';
import 'package:waste_pro/models/agence_model.dart';
import 'package:waste_pro/services/agency_directory.dart';

void main() {
  AgenceModel agence(String id, String ville, {String location = ''}) =>
      AgenceModel.fromMap({
        'id': id,
        'ville': ville,
        'location': location,
        'status': 'Active',
      });

  final directory = AgencyDirectory(
    agences: [
      agence('ag1', 'Yaoundé — Bastos', location: 'Rue 1.750'),
      agence('ag2', 'Douala — Akwa'),
    ],
    zones: const {
      'ag1': ['Étoudi', 'Mvan'],
      'ag2': ['Bonapriso'],
    },
    hasManagerlessAgencies: false,
  );

  test('finds the agency whose registered zone matches (accents ignored)', () {
    final results = directory.agenciesForZone('etoudi');
    expect(results.map((m) => m.agence.id), ['ag1']);
    expect(results.single.zone, 'Étoudi');
  });

  test('city: neighbourhood input matches on the neighbourhood', () {
    final results = directory.agenciesForZone('Douala: BONAPRISO');
    expect(results.map((m) => m.agence.id), ['ag2']);
  });

  test("falls back on the agency's city / address", () {
    final results = directory.agenciesForZone('Akwa');
    expect(results.map((m) => m.agence.id), ['ag2']);
    expect(results.single.zone, isNull);
  });

  test('zone matches come before city matches', () {
    final both = AgencyDirectory(
      agences: [agence('a', 'Yaoundé — Centre'), agence('b', 'Douala')],
      zones: const {'b': ['Yaoundé Nord']},
      hasManagerlessAgencies: false,
    );
    expect(both.agenciesForZone('Yaoundé: Nord').map((m) => m.agence.id),
        ['b', 'a']);
  });

  test('no agency for an unknown or too-short zone', () {
    expect(directory.agenciesForZone('Bonabéri'), isEmpty);
    expect(directory.agenciesForZone('ab'), isEmpty);
  });
}
