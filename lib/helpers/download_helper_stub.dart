/// Stub implementation: does nothing on non-web platforms.
/// Native downloads are handled via Share.shareXFiles instead.
void downloadFileImpl(List<int> bytes, String filename, String mimeType) {
  // No-op — native platforms use share_plus in report_service.dart.
}
