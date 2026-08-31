import 'dart:async';

import 'package:livekit_client/livekit_client.dart';

/// LiveKit voice layer.
/// Connects to a room (one channel = one room), handles PTT mic on/off,
/// and reports who is currently speaking.
class LiveKitService {
  Room? _room;
  EventsListener<RoomEvent>? _listener;

  final _speaking = StreamController<Set<String>>.broadcast();
  Stream<Set<String>> get speakingStream => _speaking.stream;

  final _participants = StreamController<List<Participant>>.broadcast();
  Stream<List<Participant>> get participantsStream => _participants.stream;

  final _connState = StreamController<ConnectionState>.broadcast();
  Stream<ConnectionState> get connectionStream => _connState.stream;

  bool _talking = false;
  bool get talking => _talking;
  bool get connected => _room?.connectionState == ConnectionState.connected;
  String? currentRoomName;

  final Set<String> _activeSpeakers = {};

  Future<void> connectToRoom({
    required String url,
    required String token,
    required String roomName,
  }) async {
    await disconnect();
    final room = Room(
      roomOptions: const RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultAudioPublishOptions: AudioPublishOptions(
          dtx: true,
          red: true,
        ),
      ),
    );
    _room = room;
    currentRoomName = roomName;

    _listener = room.createListener();

    _listener!
      ..on<ActiveSpeakersChangedEvent>((e) {
        _activeSpeakers
          ..clear()
          ..addAll(e.speakers.map((p) => p.identity));
        _speaking.add(Set.from(_activeSpeakers));
      })
      ..on<ParticipantConnectedEvent>((e) => _emitParticipants())
      ..on<ParticipantDisconnectedEvent>((e) => _emitParticipants())
      ..on<RoomDisconnectedEvent>((e) {
        _connState.add(ConnectionState.disconnected);
      })
      ..on<RoomReconnectedEvent>((e) {
        _connState.add(ConnectionState.connected);
      })
      ..on<RoomReconnectingEvent>((e) {
        _connState.add(ConnectionState.reconnecting);
      });

    await room.connect(
      url,
      token,
      connectOptions: const ConnectOptions(autoSubscribe: true),
    );
    _connState.add(room.connectionState);
    _emitParticipants();
  }

  void _emitParticipants() {
    final room = _room;
    if (room == null) return;
    final list = <Participant>[
      if (room.localParticipant != null) room.localParticipant as Participant,
      ...room.remoteParticipants.values,
    ];
    _participants.add(list);
  }

  /// PTT down — start publishing mic.
  Future<void> startTalking() async {
    final room = _room;
    if (room == null || _talking) return;
    _talking = true;
    try {
      await room.localParticipant?.setMicrophoneEnabled(true);
    } catch (_) {
      _talking = false;
    }
  }

  /// PTT up — stop publishing.
  Future<void> stopTalking() async {
    final room = _room;
    _talking = false;
    if (room == null) return;
    try {
      await room.localParticipant?.setMicrophoneEnabled(false);
    } catch (_) {}
  }

  Future<void> disconnect() async {
    _talking = false;
    _activeSpeakers.clear();
    try {
      await _listener?.dispose();
    } catch (_) {}
    _listener = null;
    try {
      await _room?.disconnect();
      await _room?.dispose();
    } catch (_) {}
    _room = null;
    currentRoomName = null;
  }

  void dispose() {
    unawaited(disconnect());
    _speaking.close();
    _participants.close();
    _connState.close();
  }
}
