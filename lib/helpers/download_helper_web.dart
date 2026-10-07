import 'dart:html' as html;

/// Web implementation: triggers a browser file download.
void downloadFileImpl(List<int> bytes, String filename, String mimeType) {
  final blob = html.Blob([bytes], mimeType, 'native');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
