import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'auth_service.dart';

/// Own WebSocket hub — replaces Firebase push.
/// Server pushes: join_request, approved, rejected, kicked, banned, muted, unmuted, presence, channel events.
class WsService {
  WsService(this.auth);
  final AuthService auth;

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _ping;
  Timer? _reconnect;
  int _retrySec = 1;
  bool _stopped = false;

  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _events.stream;

  bool get connected => _ch != null;

  Future<void> connect() async {
    _stopped = false;
    await _connectOnce();
  }

  Future<void> _connectOnce() async {
    if (_stopped) return;
    if (auth.sessionToken == null) {
      _scheduleReconnect();
      return;
    }
    try {
      final base = await auth.serverUrl;
      final wsBase = base.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');
      final uri = Uri.parse('$wsBase/ws?token=${auth.sessionToken}');
      _ch = WebSocketChannel.connect(uri);
      _retrySec = 1;
      _sub = _ch!.stream.listen(
        _onData,
        onError: (_) => _onClosed(),
        onDone: _onClosed,
        cancelOnError: true,
      );
      _ping?.cancel();
      _ping = Timer.periodic(const Duration(seconds: 25), (_) {
        try {
          _ch?.sink.add(jsonEncode({'type': 'ping'}));
        } catch (_) {}
      });
      _events.add({'type': 'ws_connected'});
    } catch (_) {
      _onClosed();
    }
  }

  void _onData(dynamic data) {
    try {
      final j = jsonDecode(data as String) as Map<String, dynamic>;
      _events.add(j);
    } catch (_) {}
  }

  void _onClosed() {
    _ping?.cancel();
    _sub?.cancel();
    _ch = null;
    _events.add({'type': 'ws_disconnected'});
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_stopped) return;
    _reconnect?.cancel();
    _reconnect = Timer(Duration(seconds: _retrySec), _connectOnce);
    _retrySec = (_retrySec * 2).clamp(1, 60); // exponential backoff
  }

  void dispose() {
    _stopped = true;
    _ping?.cancel();
    _reconnect?.cancel();
    _sub?.cancel();
    _ch?.sink.close();
    _ch = null;
  }
}
