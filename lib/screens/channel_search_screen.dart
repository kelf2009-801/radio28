import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import 'create_channel_screen.dart';
import 'settings_screen.dart';

/// Channel search + join flow (open -> instant, private -> request to admin,
/// invite code -> auto accept). FAB creates a new channel.
class ChannelSearchScreen extends StatefulWidget {
  const ChannelSearchScreen({
    super.key,
    required this.api,
    required this.auth,
    required this.onJoined,
    required this.onPending,
    required this.onCreated,
  });

  final dynamic api;
  final AuthService auth;
  final void Function(Channel channel) onJoined;
  final void Function(Channel channel) onPending;
  final void Function(Channel channel) onCreated;

  @override
  State<ChannelSearchScreen> createState() => _ChannelSearchScreenState();
}

class _ChannelSearchScreenState extends State<ChannelSearchScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Channel> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _run);
  }

  Future<void> _run() async {
    final q = _search.text.trim();
    if (q.length < 2) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.api.searchChannels(q) as List<Channel>;
      if (mounted) {
        setState(() {
          _results = r;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Сервер не отвечает';
          _loading = false;
        });
      }
    }
  }

  Future<void> _join(Channel ch) async {
    String? code;
    if (ch.hasInviteCode) {
      code = await _askCode(ch);
      if (code == null) return; // cancelled
    }
    setState(() => _loading = true);
    try {
      final status = await widget.api.joinChannel(ch.id, inviteCode: code) as String;
      if (!mounted) return;
      if (status == 'member') {
        widget.onJoined(ch);
      } else {
        widget.onPending(ch);
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString().contains('wrong_invite_code') ? 'Неверный код' : 'Ошибка входа';
      });
    }
  }

  Future<String?> _askCode(Channel ch) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ch.name, style: const TextStyle(fontSize: 16)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          maxLength: 8,
          decoration: const InputDecoration(hintText: 'Код-приглашение'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Войти', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Найти канал'),
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
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Создать канал', style: TextStyle(fontWeight: FontWeight.w700)),
        onPressed: () async {
          final created = await Navigator.push<Channel>(
            context,
            MaterialPageRoute(builder: (_) => CreateChannelScreen(api: widget.api, onCreated: (ch) => Navigator.pop(context, ch))),
          );
          if (created != null) widget.onCreated(created);
        },
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Название канала, например Сызрань-28',
                prefixIcon: const Icon(Icons.search, color: AppTheme.textMuted),
                suffixIcon: _loading
                    ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                    : null,
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 13)),
            ),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      _search.text.trim().length < 2 ? 'Введи минимум 2 буквы' : 'Каналы не найдены',
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final ch = _results[i];
                      return Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          leading: Icon(
                            ch.isPrivate ? Icons.lock_outline : Icons.lock_open,
                            color: ch.isPrivate ? AppTheme.warning : AppTheme.accent,
                          ),
                          title: Text(ch.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            '${ch.memberCount} чел.${ch.hasInviteCode ? " · вход по коду" : ch.isPrivate ? " · по запросу" : " · открытый"}',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                          ),
                          trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
                          onTap: () => _join(ch),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
