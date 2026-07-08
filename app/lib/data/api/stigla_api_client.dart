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

  Future<Map<String, dynamic>> getJson(String path, [Map<String, String>? query]) async {
    final uri = Uri.parse('$apiBaseUrl$path').replace(queryParameters: query);
    late final http.Response response;
    try {
      response = await _http.get(uri).timeout(_timeout);
    } on SocketException catch (e) {
      throw NetworkException(e.message);
    } on HttpException catch (e) {
      throw NetworkException(e.message);
    } catch (e) {
      throw NetworkException(e.toString());
    }

    if (response.statusCode == 404) {
      throw NotFoundException(response.body);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }
}
