import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'auth_service.dart';

class ApiException implements Exception {
  final int status;
  final String code;
  const ApiException(this.status, this.code);
  @override
  String toString() => 'ApiException($status, $code)';
}

/// REST client for the radio backend (FastAPI on the VPS).
class ApiService {
  ApiService(this.auth);
  final AuthService auth;

  Future<Uri> _u(String path, [Map<String, String>? q]) async {
    final base = await auth.serverUrl;
    return Uri.parse('$base$path').replace(queryParameters: q);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (auth.sessionToken != null) 'Authorization': 'Bearer ${auth.sessionToken}',
      };

  Future<Map<String, dynamic>> _req(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool authRequired = true,
  }) async {
    final uri = await _u(path, query);
    http.Response r;
    final b = body == null ? null : jsonEncode(body);
    switch (method) {
      case 'GET':
        r = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
      case 'POST':
        r = await http.post(uri, headers: _headers, body: b).timeout(const Duration(seconds: 15));
      case 'DELETE':
        r = await http.delete(uri, headers: _headers, body: b).timeout(const Duration(seconds: 15));
      default:
        throw ArgumentError(method);
    }
    Map<String, dynamic> j;
    try {
      j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(r.statusCode, 'bad_response');
    }
    if (r.statusCode >= 400) {
      throw ApiException(r.statusCode, (j['detail'] ?? 'error').toString());
    }
    return j;
  }

  // ---- auth ----

  Future<bool> serverAlive() async {
    try {
      final j = await _req('GET', '/health', authRequired: false);
      return j['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<void> registerOnServer() async {
    final p = auth.profile!;
    await _req('POST', '/auth/register', body: p.toJson(), authRequired: false);
  }

  Future<void> login() async {
    final p = auth.profile!;
    final ch = await _req('GET', '/auth/challenge', query: {'user_id': p.userId}, authRequired: false);
    final nonce = ch['nonce'] as String;
    final sig = auth.signChallenge(nonce);
    final j = await _req('POST', '/auth/login',
        body: {'user_id': p.userId, 'nonce': nonce, 'signature': sig},
        authRequired: false);
    await auth.saveSession(j['session'] as String);
  }

  Future<void> ensureSession() async {
    if (auth.sessionToken != null) return;
    await login();
  }

  // ---- channels ----

  Future<List<Channel>> searchChannels(String q) async {
    final j = await _req('GET', '/channels/search', query: {'q': q});
    return (j['channels'] as List).map((e) => Channel.fromJson(e)).toList();
  }

  Future<List<Channel>> myChannels() async {
    final j = await _req('GET', '/channels/mine');
    return (j['channels'] as List).map((e) => Channel.fromJson(e)).toList();
  }

  Future<Channel> createChannel(String name, {String? inviteCode}) async {
    final j = await _req('POST', '/channels', body: {
      'name': name,
      if (inviteCode != null && inviteCode.isNotEmpty) 'invite_code': inviteCode,
    });
    return Channel.fromJson(j['channel']);
  }

  /// Join request flow. Returns 'member' | 'pending'
  Future<String> joinChannel(int channelId, {String? inviteCode}) async {
    final j = await _req('POST', '/channels/$channelId/join',
        body: {if (inviteCode != null) 'invite_code': inviteCode});
    return j['status'] as String;
  }

  Future<Map<String, dynamic>> joinStatus(int channelId) async {
    return _req('GET', '/channels/$channelId/join_status');
  }

  // ---- members / admin ----

  Future<List<Member>> members(int channelId) async {
    final j = await _req('GET', '/channels/$channelId/members');
    return (j['members'] as List).map((e) => Member.fromJson(e)).toList();
  }

  Future<List<JoinRequest>> joinRequests(int channelId) async {
    final j = await _req('GET', '/channels/$channelId/requests');
    return (j['requests'] as List).map((e) => JoinRequest.fromJson(e)).toList();
  }

  Future<void> approve(int channelId, int requestId) =>
      _req('POST', '/channels/$channelId/requests/$requestId/approve');

  Future<void> reject(int channelId, int requestId, {String? reason}) =>
      _req('POST', '/channels/$channelId/requests/$requestId/reject',
          body: {if (reason != null) 'reason': reason});

  Future<void> kick(int channelId, String userId) =>
      _req('POST', '/channels/$channelId/members/$userId/kick');

  Future<void> ban(int channelId, String userId) =>
      _req('POST', '/channels/$channelId/members/$userId/ban');

  Future<void> mute(int channelId, String userId, bool muted) =>
      _req('POST', '/channels/$channelId/members/$userId/mute', body: {'muted': muted});

  Future<String> regenerateInviteCode(int channelId) async {
    final j = await _req('POST', '/channels/$channelId/invite_code/regenerate');
    return j['invite_code'] as String;
  }

  // ---- voice token ----

  Future<Map<String, dynamic>> voiceToken(int channelId) async {
    return _req('POST', '/channels/$channelId/voice_token');
  }

  // ---- history ----

  Future<List<HistoryEntry>> history(int channelId) async {
    final j = await _req('GET', '/channels/$channelId/history');
    return (j['history'] as List).map((e) => HistoryEntry.fromJson(e)).toList();
  }
}
