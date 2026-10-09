/// Error returned by the backend (or a network failure), with a stable [code]
/// from the API contract (e.g. `FACE_MISMATCH`, `BEACON_TOO_FAR`).
class ApiException implements Exception {
  const ApiException(this.message, {this.code = 'UNKNOWN', this.statusCode});

  final String message;
  final String code;
  final int? statusCode;

  bool get isNetwork => code == 'NETWORK_ERROR' || code == 'TIMEOUT';

  @override
  String toString() => message;
}

/// Human-readable message for any error thrown in the app.
String errorMessage(Object error) {
  if (error is ApiException) return error.message;
  final text = error.toString();
  return text.startsWith('Exception: ') ? text.substring(11) : text;
}
