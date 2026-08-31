import 'dart:io';

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
  List<Channel> _allChannels = [];
  List<Channel> _myChannels = [];
  List<Channel> _favorites = [];
  List<Channel> _searchResults = [];
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  bool _searching = false;
  int _tabIndex = 0; // 0 = Все каналы, 1 = Приватные, 2 = Мои каналы, 3 = Избранное

  @override
  void initState() {
    super.initState();
    _loadAll();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    try {
      // Get all channels (search with empty string returns all)
      final all = await widget.api.searchChannels('') as List<Channel>;
      // Get my channels (where I'm a member with any role)
      final mine = await widget.api.myChannels() as List<Channel>;
      // Get favorites
      final favs = await widget.api.favorites() as List<Channel>;
      if (mounted) {
        setState(() {
          _allChannels = all;
          _myChannels = mine;
          _favorites = favs;
          _loading = false;
        });
        print('Loaded: all=${all.length}, mine=${mine.length}, favs=${favs.length}');
      }
    } catch (e) {
      print('Load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFavorite(Channel ch) async {
    try {
      final favorited = await widget.api.toggleFavorite(ch.id) as bool;
      if (mounted) {
        setState(() {
          // Update in both lists
          _myChannels = _myChannels.map((c) =>
            c.id == ch.id ? c.copyWith(isFavorite: favorited) : c
          ).toList();
          _favorites = _favorites.map((c) =>
            c.id == ch.id ? c.copyWith(isFavorite: favorited) : c
          ).toList();
          if (!favorited) {
            _favorites.removeWhere((c) => c.id == ch.id);
          } else if (!_favorites.any((c) => c.id == ch.id)) {
            _favorites.add(ch.copyWith(isFavorite: true));
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(favorited ? 'Добавлено в избранное' : 'Убрано из избранного'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (_) {}
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
    // Simple rule: if channel is in myChannels (we have role) — enter directly.
    // Otherwise — show dialog for private, join for open.
    if (ch.role != null) {
      widget.onJoined(ch);
      return;
    }

    // Not a member — need to join
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
      drawer: _buildDrawer(),
      body: RefreshIndicator(
        color: AppTheme.accent,
        onRefresh: _loadAll,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_tabIndex) {
      case 0: return _buildChannelList(_allChannels, 'Все каналы');
      case 1: return _buildChannelList(_allChannels.where((c) => c.isPrivate).toList(), 'Приватные каналы');
      case 2: return _buildChannelList(_myChannels.where((c) => c.role == 'creator').toList(), 'Мои каналы');
      case 3: return _buildFavorites();
      default: return _buildChannelList(_allChannels, 'Все каналы');
    }
  }

  Widget _buildChannelList(List<Channel> channels, String title) {
    if (channels.isEmpty && !_loading) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 60),
          Icon(Icons.radio, size: 48, color: AppTheme.textMuted),
          const SizedBox(height: 16),
          Text(
            'Нет каналов',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            title == 'Мои каналы' ? 'Ты ещё не создал канал' : 'Создай первый канал',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 32),
          Center(
            child: ElevatedButton.icon(
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
                  _loadAll();
                  widget.onJoined(created);
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Создать канал'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ),
        ],
      );
    }
    return ListView(
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

        // Search results
        if (_searchResults.isNotEmpty) ...[
          const Text('РЕЗУЛЬТАТЫ ПОИСКА', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, letterSpacing: 1)),
          const SizedBox(height: 8),
          ..._searchResults.map((ch) => _ChannelCard(
                channel: ch,
                onTap: () => _joinOrEnter(ch),
                onFavorite: () => _toggleFavorite(ch),
                showJoinHint: true,
              )),
          const SizedBox(height: 20),
        ],

        // Channel list
        ...channels.map((ch) => _ChannelCard(
              channel: ch,
              onTap: () => _joinOrEnter(ch),
              onFavorite: () => _toggleFavorite(ch),
              showJoinHint: ch.role == null,
            )),

        // Create channel button
        const SizedBox(height: 20),
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
                _loadAll();
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
    );
  }

  Widget _buildDrawer() {
    final p = widget.auth.profile;
    return Drawer(
      backgroundColor: AppTheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            // Header with profile
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppTheme.accentDim,
                    backgroundImage: p?.avatarPath != null ? FileImage(File(p!.avatarPath!)) : null,
                    child: p?.avatarPath == null
                        ? Text(
                            p?.callsign.isNotEmpty == true ? p!.callsign[0].toUpperCase() : '?',
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.accent),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p?.callsign ?? '—',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          p?.route ?? 'без маршрута',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Menu items
            _drawerItem(Icons.public, 'Все каналы', 0),
            _drawerItem(Icons.lock_outline, 'Приватные каналы', 1),
            _drawerItem(Icons.radio, 'Мои каналы', 2),
            _drawerItem(Icons.star_outline, 'Избранное', 3),
            const Divider(color: AppTheme.border),
            _drawerItem(Icons.history, 'История', null, onTap: () {
              Navigator.pop(context);
              // TODO: open history
            }),
            _drawerItem(Icons.people_outline, 'Контакты', null, onTap: () {
              Navigator.pop(context);
              // TODO: open contacts
            }),
            const Divider(color: AppTheme.border),
            _drawerItem(Icons.settings_outlined, 'Настройки', null, onTap: () {
              Navigator.pop(context);
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
            }),
            const Spacer(),
            const Divider(color: AppTheme.border),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'SHALUN v1.0.0',
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem(IconData icon, String label, int? index, {VoidCallback? onTap}) {
    final selected = index != null && _tabIndex == index;
    return ListTile(
      leading: Icon(icon, color: selected ? AppTheme.accent : AppTheme.textSecondary),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? AppTheme.accent : AppTheme.textPrimary,
          fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
        ),
      ),
      selected: selected,
      onTap: () {
        if (index != null) {
          setState(() => _tabIndex = index);
          Navigator.pop(context);
        } else if (onTap != null) {
          onTap();
        }
      },
    );
  }

  Widget _buildMyChannels() {
    return ListView(
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

        // Search results
        if (_searchResults.isNotEmpty) ...[
          const Text('РЕЗУЛЬТАТЫ ПОИСКА', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, letterSpacing: 1)),
          const SizedBox(height: 8),
          ..._searchResults.map((ch) => _ChannelCard(
                channel: ch,
                onTap: () => _joinOrEnter(ch),
                onFavorite: () => _toggleFavorite(ch),
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
                onFavorite: () => _toggleFavorite(ch),
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
                // Refresh list and enter the new channel
                _loadAll();
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
    );
  }

  Widget _buildFavorites() {
    if (_favorites.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.star_outline, size: 48, color: AppTheme.textMuted),
            const SizedBox(height: 16),
            const Text(
              'Нет избранных каналов',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              'Нажми ★ на канале чтобы добавить сюда',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ..._favorites.map((ch) => _ChannelCard(
              channel: ch,
              onTap: () => widget.onJoined(ch),
              onFavorite: () => _toggleFavorite(ch),
              showJoinHint: false,
            )),
      ],
    );
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({
    required this.channel,
    required this.onTap,
    required this.onFavorite,
    required this.showJoinHint,
  });

  final Channel channel;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                channel.isFavorite ? Icons.star : Icons.star_outline,
                color: channel.isFavorite ? AppTheme.warning : AppTheme.textMuted,
              ),
              onPressed: onFavorite,
              tooltip: channel.isFavorite ? 'Убрать из избранного' : 'В избранное',
            ),
            if (showJoinHint && channel.role == null)
              const Icon(Icons.chevron_right, color: AppTheme.textMuted)
            else
              const Icon(Icons.radio, color: AppTheme.accent),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
