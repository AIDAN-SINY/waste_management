import 'download_helper_stub.dart'
    if (dart.library.html) 'download_helper_web.dart';

/// Triggers a file download in the browser. No-op on non-web platforms.
void downloadFile(List<int> bytes, String filename, String mimeType) {
  downloadFileImpl(bytes, filename, mimeType);
}
