/// Thrown when the request never reached the backend (offline, DNS, timeout).
class NetworkException implements Exception {
  const NetworkException(this.message);
  final String message;
}

/// Thrown on a 404 — e.g. an unknown stop_id or route_id.
class NotFoundException implements Exception {
  const NotFoundException(this.message);
  final String message;
}

/// Thrown on any other non-2xx response from our own backend.
class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;
}
