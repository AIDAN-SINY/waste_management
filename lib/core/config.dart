/// Central app configuration.
///
/// CamPay credentials are NOT in the app: payments go through the
/// `startPayment` / `checkPayment` Cloud Functions (see `functions/`).
class AppConfig {
  AppConfig._();

  /// Display hint only — the server decides the real charge. Must match
  /// `CAMPAY_ENV` in `functions/.env`. Build with
  /// `--dart-define=CAMPAY_ENV=production` for production.
  static const String _campayEnv = String.fromEnvironment(
    'CAMPAY_ENV',
    defaultValue: 'demo',
  );

  static bool get isCampayDemo => _campayEnv != 'production';

  /// Demo charge sent to CamPay while UI still shows full plan prices
  /// (mirrors DEMO_MAX_AMOUNT in functions/index.js).
  static const double campayDemoMaxAmount = 25;

  /// Default currency (Cameroon).
  static const String currency = 'XAF';
}
