import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import 'create_channel_screen.dart';
import 'settings_screen.dart';

/// Home after login: My channels (active) + Discover (search/create).
/// This is what the driver sees first — not a bare search field.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.auth,
    required this.onJoined,
    required this.onPending,
  });

  final dynamic api;
  final AuthService auth;
  final void Function(Channel channel) onJoined;
  final void Function(Channel channel) onPending;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Channel> _myChannels = [];
  List<Channel> _searchResults = [];
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _loadMyChannels();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMyChannels() async {
    try {
      final mine = await widget.api.myChannels() as List<Channel>;
      if (mounted) {
        setState(() {
          _myChannels = mine;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onSearchChanged() async {
    final q = _searchCtrl.text.trim();
    if (q.length < 2) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final r = await widget.api.searchChannels(q) as List<Channel>;
      if (mounted) setState(() => _searchResults = r);
    } catch (_) {}
  }

  Future<void> _joinOrEnter(Channel ch) async {
    // If already member — enter directly
    if (ch.role != null) {
      widget.onJoined(ch);
      return;
    }
    // Check if we're actually a member (role might be null in search results)
    try {
      final st = await widget.api.joinStatus(ch.id) as Map<String, dynamic>;
      if (!mounted) return;
      if (st['status'] == 'member') {
        widget.onJoined(ch);
        return;
      }
    } catch (_) {}

    // Otherwise — request to join
    if (ch.isPrivate) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ch.name, style: const TextStyle(fontSize: 16)),
          content: const Text(
            'Это приватный канал. Админ получит твой запрос и подтвердит вход.',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.black,
              ),
              child: const Text('Отправить запрос'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      try {
        await widget.api.joinChannel(ch.id);
        if (mounted) widget.onPending(ch);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: $e')),
          );
        }
      }
    } else {
      // Open channel — join instantly
      try {
        await widget.api.joinChannel(ch.id);
        if (mounted) widget.onJoined(ch);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SHALUN'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: AppTheme.textSecondary),
            tooltip: 'Настройки',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    auth: widget.auth,
                    channel: null,
                    api: widget.api,
                    onLeaveChannel: () {},
                    onUpdateProfile: (_) async {},
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.accent,
        onRefresh: _loadMyChannels,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Search field
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Найти канал...',
                prefixIcon: const Icon(Icons.search, color: AppTheme.textMuted),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 20),

            // Search results (when searching)
            if (_searchResults.isNotEmpty) ...[
              const Text('РЕЗУЛЬТАТЫ ПОИСКА', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, letterSpacing: 1)),
              const SizedBox(height: 8),
              ..._searchResults.map((ch) => _ChannelCard(
                    channel: ch,
                    onTap: () => _joinOrEnter(ch),
                    showJoinHint: true,
                  )),
              const SizedBox(height: 20),
            ],

            // My channels
            if (_myChannels.isNotEmpty) ...[
              const Text('МОИ КАНАЛЫ', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, letterSpacing: 1)),
              const SizedBox(height: 8),
              ..._myChannels.map((ch) => _ChannelCard(
                    channel: ch,
                    onTap: () => widget.onJoined(ch),
                    showJoinHint: false,
                  )),
              const SizedBox(height: 20),
            ],

            // Empty state
            if (_myChannels.isEmpty && _searchResults.isEmpty && !_loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    Icon(Icons.radio, size: 48, color: AppTheme.textMuted),
                    const SizedBox(height: 16),
                    const Text(
                      'Пока нет каналов',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Создай свой или найди существующий через поиск выше',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),

            // Create channel button
            Center(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final created = await Navigator.push<Channel>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CreateChannelScreen(
                        api: widget.api,
                        onCreated: (c) => Navigator.pop(context, c),
                      ),
                    ),
                  );
                  if (created != null) {
                    _loadMyChannels();
                    widget.onJoined(created);
                  }
                },
                icon: const Icon(Icons.add, color: AppTheme.accent),
                label: const Text('Создать канал', style: TextStyle(color: AppTheme.accent)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.accent),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({
    required this.channel,
    required this.onTap,
    required this.showJoinHint,
  });

  final Channel channel;
  final VoidCallback onTap;
  final bool showJoinHint;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: channel.isPrivate ? AppTheme.warning.withOpacity(0.15) : AppTheme.accentDim,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            channel.isPrivate ? Icons.lock_outline : Icons.lock_open,
            color: channel.isPrivate ? AppTheme.warning : AppTheme.accent,
          ),
        ),
        title: Text(
          channel.name,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        subtitle: Text(
          [
            '${channel.memberCount} чел.',
            if (channel.role != null) ' · ${channel.role == 'creator' ? 'Создатель' : channel.role == 'admin' ? 'Админ' : 'Участник'}',
            if (channel.isPrivate && channel.role == null) ' · по запросу',
            if (!channel.isPrivate && channel.role == null) ' · открытый',
          ].join(),
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        trailing: showJoinHint && channel.role == null
            ? const Icon(Icons.chevron_right, color: AppTheme.textMuted)
            : const Icon(Icons.radio, color: AppTheme.accent),
        onTap: onTap,
      ),
    );
  }
}
