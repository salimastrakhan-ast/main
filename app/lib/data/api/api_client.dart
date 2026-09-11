import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config.dart';
import 'session_store.dart';

/// Ошибка HTTP-слоя с машинным кодом от сервера.
class ApiException implements Exception {
  const ApiException(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;

  @override
  String toString() => 'ApiException($status/$code): $message';
}

/// REST-клиент.
///
/// Через сокет идёт всё живое общение; сюда вынесено то, что либо
/// предшествует соединению (вход), либо плохо ложится на кадры — постраничная
/// история и загрузка файлов.
class ApiClient {
  ApiClient({required this.sessions, http.Client? client})
    : _http = client ?? http.Client();

  final SessionStore sessions;
  final http.Client _http;

  Future<Map<String, dynamic>> requestCode(String phone) {
    return _post('/v1/auth/request-code', {'phone': phone}, auth: false);
  }

  Future<Session> verifyCode({
    required String phone,
    required String code,
    required String platform,
    String device = '',
  }) async {
    final json = await _post('/v1/auth/verify', {
      'phone': phone,
      'code': code,
      'platform': platform,
      'device': device,
    }, auth: false);

    final session = Session.fromAuthResponse(json);
    await sessions.write(session);
    return session;
  }

  Future<void> logout() async {
    final session = await sessions.read();
    if (session != null) {
      try {
        await _post('/v1/auth/logout', {
          'refresh_token': session.refreshToken,
        }, auth: false);
      } catch (_) {
        // Сервер недоступен — локальную сессию всё равно стираем: человек
        // нажал «выйти», и его ожидание важнее аккуратного отзыва токена.
      }
    }
    await sessions.clear();
  }

  /// Возвращает годный access-токен, обновляя пару при необходимости.
  ///
  /// Это единственная точка, где токен обновляется, — иначе параллельные
  /// запросы устроили бы гонку ротаций и разлогинили человека.
  Future<String?> freshAccessToken() async {
    final session = await sessions.read();
    if (session == null) return null;
    if (!session.isExpiring) return session.accessToken;

    _refreshing ??= _refresh(session.refreshToken);
    try {
      return (await _refreshing)?.accessToken;
    } finally {
      _refreshing = null;
    }
  }

  Future<Session?>? _refreshing;

  Future<Session?> _refresh(String refreshToken) async {
    try {
      final json = await _post('/v1/auth/refresh', {
        'refresh_token': refreshToken,
      }, auth: false);
      final session = Session.fromAuthResponse(json);
      await sessions.write(session);
      return session;
    } on ApiException catch (e) {
      if (e.status == 401) {
        // Refresh мёртв — сессию восстановить нельзя, нужен новый вход.
        await sessions.clear();
      }
      return null;
    }
  }

  Future<Map<String, dynamic>> me() => _get('/v1/users/me');

  /// Меняет профиль. Пока это только имя: аватары ещё не заведены.
  Future<Map<String, dynamic>> updateMe({required String displayName}) {
    return _send('PATCH', '/v1/users/me', {'display_name': displayName});
  }

  Future<List<dynamic>> history(
    String chatId, {
    int? beforeSeq,
    int limit = 50,
  }) async {
    final query = {
      'limit': '$limit',
      if (beforeSeq != null && beforeSeq > 0) 'before_seq': '$beforeSeq',
    };
    final json = await _get('/v1/chats/$chatId/messages', query: query);
    return json['messages'] as List<dynamic>? ?? const [];
  }

  /// Адресная книга: те из знакомых, кто уже зарегистрирован.
  Future<List<dynamic>> contacts() async {
    final json = await _get('/v1/contacts');
    return json['contacts'] as List<dynamic>? ?? const [];
  }

  Future<List<dynamic>> syncContacts(List<Map<String, String>> contacts) async {
    final json = await _post('/v1/contacts/sync', {'contacts': contacts});
    return json['users'] as List<dynamic>? ?? const [];
  }

  Future<List<dynamic>> searchUsers(String query) async {
    final json = await _get('/v1/users/search', query: {'q': query});
    return json['users'] as List<dynamic>? ?? const [];
  }

  /// Загружает файл и возвращает описание вложения.
  ///
  /// Файл уходит ДО отправки сообщения: так виден прогресс, а сообщение
  /// отправляется одним кадром со списком идентификаторов.
  Future<Map<String, dynamic>> upload({
    required String fileName,
    required List<int> bytes,
    required String mime,
    int? width,
    int? height,
  }) async {
    final token = await freshAccessToken();
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse('${AppConfig.apiBase}/v1/media/upload'),
          )
          ..headers['Authorization'] = 'Bearer $token'
          ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: fileName),
          )
          ..fields.addAll({
            if (width != null) 'width': '$width',
            if (height != null) 'height': '$height',
          });

    final response = await http.Response.fromStream(await request.send());
    final json = _parse(response);
    return json['attachment'] as Map<String, dynamic>;
  }

  /// Ставит аватар. Одним запросом: сервер сам кладёт файл в хранилище и
  /// запоминает ключ, а подписанную ссылку выдаёт при каждом чтении профиля.
  /// Хранить её нельзя — она живёт шесть часов.
  Future<Map<String, dynamic>> setAvatar({
    required String fileName,
    required List<int> bytes,
  }) async {
    final token = await freshAccessToken();
    final request =
        http.MultipartRequest(
            'PUT',
            Uri.parse('${AppConfig.apiBase}/v1/users/me/avatar'),
          )
          ..headers['Authorization'] = 'Bearer $token'
          ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: fileName),
          );

    return _parse(await http.Response.fromStream(await request.send()));
  }

  Future<Map<String, dynamic>> removeAvatar() async {
    final request = http.Request(
      'DELETE',
      Uri.parse('${AppConfig.apiBase}/v1/users/me/avatar'),
    )..headers.addAll(await _headers(true));
    return _parse(await http.Response.fromStream(await _http.send(request)));
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse(
      '${AppConfig.apiBase}$path',
    ).replace(queryParameters: query);
    final response = await _http.get(uri, headers: await _headers(true));
    return _parse(response);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    final response = await _http.post(
      Uri.parse('${AppConfig.apiBase}$path'),
      headers: await _headers(auth),
      body: jsonEncode(body),
    );
    return _parse(response);
  }

  /// Запрос произвольным методом — для PATCH, которого нет у http.post.
  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Map<String, dynamic> body,
  ) async {
    final request = http.Request(
      method,
      Uri.parse('${AppConfig.apiBase}$path'),
    )
      ..headers.addAll(await _headers(true))
      ..body = jsonEncode(body);
    final response = await http.Response.fromStream(await _http.send(request));
    return _parse(response);
  }

  Future<Map<String, String>> _headers(bool auth) async {
    final headers = {'Content-Type': 'application/json; charset=utf-8'};
    if (auth) {
      final token = await freshAccessToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Map<String, dynamic> _parse(http.Response response) {
    final Map<String, dynamic> json;
    try {
      json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(
        response.statusCode,
        'bad_response',
        'Сервер ответил неожиданно',
      );
    }

    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        json['code'] as String? ?? 'unknown',
        json['message'] as String? ?? 'Что-то пошло не так',
      );
    }
    return json;
  }

  void close() => _http.close();
}
