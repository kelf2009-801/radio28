import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'core/theme.dart';
import 'models/models.dart';
import 'screens/home_screen.dart';
import 'screens/history_screen.dart';
import 'screens/members_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/pending_screen.dart';
import 'screens/radio_screen.dart';
import 'screens/settings_screen.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/livekit_service.dart';
import 'services/ws_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Request mic + bluetooth upfront (radio app — user expects it)
  await [
    Permission.microphone,
    Permission.bluetoothConnect,
    Permission.notification,
  ].request();
  runApp(const Radio28App());
}

class Radio28App extends StatefulWidget {
  const Radio28App({super.key});

  @override
  State<Radio28App> createState() => _Radio28AppState();
}

class _Radio28AppState extends State<Radio28App> with WidgetsBindingObserver {
  late final AuthService auth;
  late final ApiService api;
  late final LiveKitService livekit;
  late final WsService ws;

  bool _booting = true;
  bool _hasIdentity = false;
  Channel? _activeChannel;
  Channel? _pendingChannel;
  int _navIndex = 0;

  StreamSubscription? _wsSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    auth = AuthService();
    api = ApiService(auth);
    livekit = LiveKitService();
    ws = WsService(auth);
    _boot();
  }

  Future<void> _boot() async {
    final has = await auth.load();
    if (has) {
      try {
        await api.login();
        await ws.connect();
        _listenWs();
        final mine = await api.myChannels();
        if (mine.isNotEmpty) _activeChannel = mine.first;
      } catch (_) {
        // server unreachable — stay logged-out-ish, user can set server URL
      }
    }
    if (mounted) {
      setState(() {
        _hasIdentity = has;
        _booting = false;
      });
    }
  }

  void _listenWs() {
    _wsSub?.cancel();
    _wsSub = ws.events.listen((e) {
      final type = e['type'] as String?;
      if (type == 'approved' && _pendingChannel != null) {
        setState(() {
          _activeChannel = _pendingChannel;
          _pendingChannel = null;
        });
      } else if (type == 'kicked' || type == 'banned') {
        if (mounted) {
          setState(() => _activeChannel = null);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(type == 'kicked' ? 'Тебя исключили из канала' : 'Ты забанен')),
          );
        }
      } else if (type == 'join_request' && _activeChannel?.isAdmin == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${e['callsign'] ?? 'Кто-то'} просится в канал')),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wsSub?.cancel();
    ws.dispose();
    livekit.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _hasIdentity && !ws.connected) {
      ws.connect();
    }
  }

  Future<void> _onOnboarded(String callsign, String route, String? avatarPath) async {
    await auth.register(callsign: callsign, route: route.isEmpty ? null : route, avatarPath: avatarPath);
    await api.registerOnServer();
    await api.login();
    await ws.connect();
    _listenWs();
    // If this is the server's first account, it owns the seeded "Сызрань-28" channel.
    Channel? initial;
    try {
      final mine = await api.myChannels();
      if (mine.isNotEmpty) initial = mine.first;
    } catch (_) {}
    if (mounted) {
      setState(() {
        _hasIdentity = true;
        if (initial != null) _activeChannel = initial;
      });
    }
  }

  void _onJoined(Channel ch) {
    setState(() {
      _activeChannel = ch;
      _pendingChannel = null;
      _navIndex = 0;
    });
  }

  void _onPending(Channel ch) {
    setState(() => _pendingChannel = ch);
  }

  void _onApproved() {
    setState(() {
      _activeChannel = _pendingChannel;
      _pendingChannel = null;
    });
  }

  void _leaveChannel() {
    livekit.disconnect();
    setState(() {
      _activeChannel = null;
      _navIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Рация 28',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: _build(),
    );
  }

  Widget _build() {
    if (_booting) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppTheme.accent)),
      );
    }

    if (!_hasIdentity) {
      return OnboardingScreen(onDone: _onOnboarded);
    }

    if (_pendingChannel != null && _activeChannel == null) {
      return PendingScreen(
        channel: _pendingChannel!,
        api: api,
        onApproved: _onApproved,
        onCancel: () => setState(() => _pendingChannel = null),
      );
    }

    if (_activeChannel == null) {
      return HomeScreen(
        api: api,
        auth: auth,
        onJoined: _onJoined,
        onPending: _onPending,
      );
    }

    final ch = _activeChannel!;
    final screens = [
      RadioScreen(
        channel: ch,
        api: api,
        livekit: livekit,
        profile: auth.profile!,
        onLeave: _leaveChannel,
        onOpenMembers: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MembersScreen(
              channel: ch,
              api: api,
              myUserId: auth.profile!.userId,
              livekit: livekit,
            ),
          ),
        ),
      ),
      MembersScreen(
        channel: ch,
        api: api,
        myUserId: auth.profile!.userId,
        livekit: livekit,
        embedded: true,
        onJoined: _onJoined,
      ),
      HistoryScreen(channel: ch, api: api),
      SettingsScreen(
        auth: auth,
        channel: ch,
        api: api,
        onLeaveChannel: _leaveChannel,
        onUpdateProfile: (route) async {
          await auth.updateProfile(route: route);
          try {
            await api.registerOnServer();
          } catch (_) {}
        },
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _navIndex, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _navIndex,
        onTap: (i) => setState(() => _navIndex = i),
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.radio), label: 'Рация'),
          const BottomNavigationBarItem(icon: Icon(Icons.people_alt_outlined), label: 'Онлайн'),
          const BottomNavigationBarItem(icon: Icon(Icons.history), label: 'История'),
          const BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Настройки'),
        ],
      ),
    );
  }
}
