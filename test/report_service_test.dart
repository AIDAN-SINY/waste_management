import 'package:flutter_test/flutter_test.dart';
import 'package:waste_pro/services/report_service.dart';

void main() {
  group('ReportType', () {
    test('has all expected report types', () {
      final types = ReportType.values;
      expect(types.length, 5);
      expect(types, contains(ReportType.daily));
      expect(types, contains(ReportType.weekly));
      expect(types, contains(ReportType.monthly));
      expect(types, contains(ReportType.annual));
      expect(types, contains(ReportType.paymentLog));
    });

    test('ReportType enum values have correct names', () {
      expect(ReportType.daily.name, 'daily');
      expect(ReportType.weekly.name, 'weekly');
      expect(ReportType.monthly.name, 'monthly');
      expect(ReportType.annual.name, 'annual');
      expect(ReportType.paymentLog.name, 'paymentLog');
    });
  });
}
