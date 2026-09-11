import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Сессия: токены и профиль вошедшего.
class Session {
  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final String userId;
  final DateTime expiresAt;

  bool get isExpiring =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 1)));

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'user_id': userId,
    'expires_at': expiresAt.toIso8601String(),
  };

  static Session fromJson(Map<String, dynamic> json) => Session(
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String,
    userId: json['user_id'] as String,
    expiresAt: DateTime.parse(json['expires_at'] as String),
  );

  /// Собирает сессию из ответа сервера на вход или обновление.
  static Session fromAuthResponse(Map<String, dynamic> json) => Session(
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String,
    userId: (json['user'] as Map<String, dynamic>)['id'] as String,
    expiresAt: DateTime.now().add(
      Duration(seconds: json['expires_in'] as int? ?? 900),
    ),
  );
}

/// Хранилище сессии.
///
/// Именно защищённое хранилище устройства — Keychain на iOS и EncryptedShared
/// Preferences на Android, — а не обычные настройки: refresh-токен живёт
/// месяц и даёт полный доступ к переписке.
class SessionStore {
  SessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'tito.session';

  final FlutterSecureStorage _storage;
  Session? _cached;

  Future<Session?> read() async {
    if (_cached != null) return _cached;
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      return _cached = Session.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      // Формат поменялся или запись побилась — проще переспросить вход,
      // чем разбираться в мусоре.
      await clear();
      return null;
    }
  }

  Future<void> write(Session session) async {
    _cached = session;
    await _storage.write(key: _key, value: jsonEncode(session.toJson()));
  }

  Future<void> clear() async {
    _cached = null;
    await _storage.delete(key: _key);
  }
}
