import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/api_config.dart';
import 'api_exceptions.dart';

/// Thin wrapper around the Stigla backend's REST API. The app only ever
/// talks to this backend — never to the upstream transit source directly.
class StiglaApiClient {
  StiglaApiClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;
  static const _timeout = Duration(seconds: 10);

  Future<Map<String, dynamic>> getJson(
    String path, [
    Map<String, String>? query,
    Map<String, String>? headers,
  ]) async {
    final uri = Uri.parse('$apiBaseUrl$path').replace(queryParameters: query);
    final response = await _send(() => _http.get(uri, headers: headers));
    return _decode(response);
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('$apiBaseUrl$path');
    final response = await _send(
      () => _http.post(
        uri,
        headers: {'content-type': 'application/json', ...?headers},
        body: body != null ? jsonEncode(body) : null,
      ),
    );
    return _decode(response);
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(_timeout);
    } on SocketException catch (e) {
      throw NetworkException(e.message);
    } on HttpException catch (e) {
      throw NetworkException(e.message);
    } catch (e) {
      throw NetworkException(e.toString());
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode == 404) {
      throw NotFoundException(response.body);
    }
    if (response.statusCode == 429) {
      throw RateLimitedException(response.body);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
    if (response.bodyBytes.isEmpty) return const {};
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }
}
