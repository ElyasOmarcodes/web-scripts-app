import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/script.dart';
import '../models/settings.dart';

class ApiException implements Exception {
  ApiException(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Thin REST + WebSocket client for the local Python backend.
class ApiClient {
  ApiClient({this.host = '127.0.0.1', this.port = 8765, http.Client? client})
      : _client = client ?? http.Client();

  final String host;
  final int port;
  final http.Client _client;

  String get baseUrl => 'http://$host:$port';
  Uri _uri(String path, [Map<String, dynamic>? query]) =>
      Uri.parse('$baseUrl$path').replace(
        queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
      );

  Future<Map<String, dynamic>> health() async =>
      _decodeMap(await _client.get(_uri('/api/health')));

  Future<bool> isUp() async {
    try {
      await health().timeout(const Duration(seconds: 2));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<WebScript>> listScripts() async {
    final response = await _client.get(_uri('/api/scripts'));
    final list = _decodeList(response);
    return list
        .map((e) => WebScript.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<WebScript> createScript({String name = 'نوی سکریپټ', String startUrl = ''}) async =>
      WebScript.fromJson(await _post('/api/scripts', {
        'name': name,
        'start_url': startUrl,
      }));

  Future<WebScript> getScript(String id) async =>
      WebScript.fromJson(_decodeMap(await _client.get(_uri('/api/scripts/$id'))));

  Future<WebScript> updateScript(
    String id, {
    String? name,
    String? description,
    String? startUrl,
    List<StepModel>? steps,
    List<VariableModel>? variables,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    if (startUrl != null) body['start_url'] = startUrl;
    if (steps != null) body['steps'] = steps.map((s) => s.toJson()).toList();
    if (variables != null) {
      body['variables'] = variables.map((v) => v.toJson()).toList();
    }
    return WebScript.fromJson(_decodeMap(await _post('/api/scripts/$id', body,
        method: 'PUT')));
  }

  Future<void> deleteScript(String id) async {
    final response = await _client.delete(_uri('/api/scripts/$id'));
    _ensureOk(response);
  }

  Future<void> startRecording({
    required String name,
    required String url,
    bool? captureScroll,
    String? browser,
  }) async {
    await _post('/api/record/start', {
      'name': name,
      'url': url,
      if (captureScroll != null) 'capture_scroll': captureScroll,
      if (browser != null) 'browser': browser,
    });
  }

  Future<Map<String, dynamic>> stopRecording() async =>
      _decodeMap(await _postRaw('/api/record/stop', const {}));

  /// Omitted options fall back to the values saved in Settings.
  Future<void> run(
    String id, {
    Map<String, String> variables = const {},
    double? speed,
    bool? headless,
    bool? keepOpen,
    String? browser,
  }) async {
    await _post('/api/scripts/$id/run', {
      'variables': variables,
      if (speed != null) 'speed': speed,
      if (headless != null) 'headless': headless,
      if (keepOpen != null) 'keep_open': keepOpen,
      if (browser != null) 'browser': browser,
    });
  }

  Future<void> stopSession() async => _post('/api/session/stop', const {});

  Future<Map<String, dynamic>> sessionStatus() async =>
      _decodeMap(await _client.get(_uri('/api/session')));

  // ---------------------------------------------------------------- settings

  Future<AppSettings> settings() async =>
      AppSettings.fromJson(_decodeMap(await _client.get(_uri('/api/settings'))));

  Future<AppSettings> saveSettings(Map<String, dynamic> changes) async =>
      AppSettings.fromJson(await _post('/api/settings', changes, method: 'PUT'));

  Future<AppSettings> resetSettings() async =>
      AppSettings.fromJson(await _post('/api/settings/reset', const {}));

  Future<BrowserList> browsers({bool refresh = false}) async => BrowserList.fromJson(
        _decodeMap(await _client.get(_uri('/api/browsers', {'refresh': refresh}))),
      );

  Future<List<AppEvent>> eventHistory({int limit = 200}) async {
    final list = _decodeList(
        await _client.get(_uri('/api/events', {'limit': limit})));
    return list
        .map((e) => AppEvent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Live event stream. The caller is responsible for reconnecting.
  Stream<AppEvent> events() {
    final channel =
        WebSocketChannel.connect(Uri.parse('ws://$host:$port/ws'));
    return channel.stream.map((raw) {
      final decoded = jsonDecode(raw as String);
      return AppEvent.fromJson(decoded as Map<String, dynamic>);
    });
  }

  // ------------------------------------------------------------------ helpers

  Future<http.Response> _postRaw(String path, Map<String, dynamic> body,
      {String method = 'POST'}) async {
    final request = http.Request(method, _uri(path))
      ..headers['content-type'] = 'application/json'
      ..body = jsonEncode(body);
    final streamed = await _client.send(request);
    return http.Response.fromStream(streamed);
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body,
      {String method = 'POST'}) async {
    return _decodeMap(await _postRaw(path, body, method: method));
  }

  Map<String, dynamic> _decodeMap(http.Response response) {
    _ensureOk(response);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  List<dynamic> _decodeList(http.Response response) {
    _ensureOk(response);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return decoded is List ? decoded : const [];
  }

  void _ensureOk(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    String message = 'د سرور تېروتنه (${response.statusCode})';
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map && decoded['detail'] != null) {
        message = decoded['detail'].toString();
      }
    } catch (_) {
      // keep the generic message
    }
    throw ApiException(message, response.statusCode);
  }

  void close() => _client.close();
}
