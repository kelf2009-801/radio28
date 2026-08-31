import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:livekit_client/livekit_client.dart' hide ConnectionState;
import 'package:livekit_client/livekit_client.dart' as lk show ConnectionState;
import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/theme.dart';
import '../models/models.dart';

/// Main radio screen: big PTT button, who is speaking, volume slider, members preview.
class RadioScreen extends StatefulWidget {
  const RadioScreen({
    super.key,
    required this.channel,
    required this.api,
    required this.livekit,
    required this.profile,
    required this.onOpenMembers,
  });

  final Channel channel;
  final dynamic api;
  final dynamic livekit; // LiveKitService
  final Profile profile;
  final VoidCallback onOpenMembers;

  @override
  State<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends State<RadioScreen> {
  bool _connecting = true;
  String? _error;
  bool _pressed = false;
  Set<String> _speaking = {};
  int _online = 0;
  String? _lastSpeaker;
  DateTime? _lastSpokeAt;
  double _volume = 0.8;
  lk.ConnectionState _conn = lk.ConnectionState.disconnected;

  StreamSubscription? _subSpeak;
  StreamSubscription? _subParts;
  StreamSubscription? _subConn;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _connect();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _subSpeak?.cancel();
    _subParts?.cancel();
    _subConn?.cancel();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final j = await widget.api.voiceToken(widget.channel.id) as Map<String, dynamic>;
      final url = j['url'] as String;
      final token = j['token'] as String;
      await widget.livekit.connectToRoom(url: url, token: token, roomName: widget.channel.name);

      _subSpeak = (widget.livekit.speakingStream as Stream<Set<String>>).listen((s) {
        if (!mounted) return;
        final others = s.where((id) => id != widget.profile.userId).toSet();
        setState(() => _speaking = others);
        if (others.isNotEmpty) {
          _lastSpeaker = others.first;
          _lastSpokeAt = DateTime.now();
        }
      });
      _subParts = (widget.livekit.participantsStream as Stream<List<Participant>>).listen((p) {
        if (!mounted) return;
        setState(() => _online = p.length);
      });
      _subConn = (widget.livekit.connectionStream as Stream<lk.ConnectionState>).listen((c) {
        if (!mounted) return;
        setState(() => _conn = c);
      });

      setState(() => _connecting = false);
    } catch (e) {
      setState(() {
        _connecting = false;
        _error = e.toString().contains('muted')
            ? 'Ты замьючен админом'
            : 'Нет связи с сервером голоса';
      });
    }
  }

  Future<void> _pttDown() async {
    if (_pressed) return;
    setState(() => _pressed = true);
    HapticFeedback.mediumImpact();
    try {
      if (await Vibration.hasVibrator() ?? false) Vibration.vibrate(duration: 30);
    } catch (_) {}
    await widget.livekit.startTalking();
  }

  Future<void> _pttUp() async {
    if (!_pressed) return;
    setState(() => _pressed = false);
    await widget.livekit.stopTalking();
  }

  String get _speakingName {
    if (_speaking.isEmpty) return '';
    final id = _speaking.first;
    // identity == userId; display as short id for now, members screen maps to callsign
    return id.length > 8 ? id.substring(0, 8) : id;
  }

  @override
  Widget build(BuildContext context) {
    final someoneTalking = _speaking.isNotEmpty;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.settings_input_antenna, color: AppTheme.accent, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.channel.name,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        Text(
                          _conn == lk.ConnectionState.connected
                              ? '$_online онлайн'
                              : _connecting
                                  ? 'подключение…'
                                  : _error ?? 'нет связи',
                          style: TextStyle(
                            fontSize: 11,
                            color: _conn == lk.ConnectionState.connected
                                ? AppTheme.accent
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.people_outline, color: AppTheme.textSecondary),
                    onPressed: widget.onOpenMembers,
                  ),
                ],
              ),
            ),

            // Volume quick slider
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.volume_down, color: AppTheme.textMuted, size: 18),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                        activeTrackColor: AppTheme.accent,
                        inactiveTrackColor: AppTheme.border,
                        thumbColor: AppTheme.accent,
                      ),
                      child: Slider(
                        value: _volume,
                        onChanged: (v) {
                          setState(() => _volume = v);
                          // LiveKit plays through remote participants' audio tracks;
                          // system media volume handles the rest.
                        },
                      ),
                    ),
                  ),
                  const Icon(Icons.volume_up, color: AppTheme.textMuted, size: 18),
                ],
              ),
            ),

            const Spacer(),

            // Who is speaking
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: someoneTalking
                  ? Column(
                      key: const ValueKey('speaking'),
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.accent.withOpacity(0.12),
                            border: Border.all(color: AppTheme.accent, width: 2),
                          ),
                          child: const Icon(Icons.mic, color: AppTheme.accent, size: 28),
                        ),
                        const SizedBox(height: 10),
                          Text(
                            'Говорит: $_speakingName',
                            style: const TextStyle(color: AppTheme.accent, fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                      ],
                    )
                  : Column(
                      key: const ValueKey('idle'),
                      children: [
                        const Text('Эфир свободен',
                            style: TextStyle(color: AppTheme.textMuted, fontSize: 14)),
                        if (_lastSpokeAt != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Последний: ${_lastSpeaker ?? "?"} · ${TimeOfDay.fromDateTime(_lastSpokeAt!).format(context)}',
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                          ),
                        ],
                      ],
                    ),
            ),

            const Spacer(),

            // PTT button
            GestureDetector(
              onTapDown: (_) => _pttDown(),
              onTapUp: (_) => _pttUp(),
              onTapCancel: _pttUp,
              onLongPressStart: (_) => _pttDown(),
              onLongPressEnd: (_) => _pttUp(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _pressed ? AppTheme.accent : AppTheme.card,
                  border: Border.all(color: AppTheme.accent, width: 3),
                  boxShadow: _pressed
                      ? [BoxShadow(color: AppTheme.accent.withOpacity(0.5), blurRadius: 40, spreadRadius: 4)]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.mic, size: 40, color: _pressed ? Colors.black : AppTheme.accent),
                    const SizedBox(height: 6),
                    Text(
                      _pressed ? 'ГОВОРЮ' : 'ГОВОРИТЬ',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: _pressed ? Colors.black : AppTheme.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text('Удерживай кнопку', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
