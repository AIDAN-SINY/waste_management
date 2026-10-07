import 'package:waste_pro/providers/notification_provider.dart';

/// A no-op [NotificationProvider] for tests — constructed without a
/// [NotificationService], so all methods are silent no-ops and no
/// Firebase dependency is required.
class FakeNotificationProvider extends NotificationProvider {
  FakeNotificationProvider() : super(service: null);
}
