/// Error thrown when a required drawer field is blank. The [message] is
/// displayed as an error toast while the drawer stays open for a retry.
class ValidationError implements Exception {
  const ValidationError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Returns the trimmed value of [form][key] or throws a [ValidationError]
/// when it is missing/blank — used to block drawer saves on empty required
/// fields (e.g. Company name, City, Full name).
String requireField(
  Map<String, dynamic> form,
  String key,
  String label,
) {
  final value = form[key]?.toString().trim() ?? '';
  if (value.isEmpty) {
    throw ValidationError('The field "$label" is required.');
  }
  return value;
}
