import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';

/// Members of the channel: online, speaking, muted badges. Admin long-press = actions.
class MembersScreen extends StatefulWidget {
  const MembersScreen({
    super.key,
    required this.channel,
    required this.api,
    required this.myUserId,
    required this.livekit,
  });

  final Channel channel;
  final dynamic api;
  final String myUserId;
  final dynamic livekit;

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  List<Member> _members = [];
  Set<String> _speaking = {};
  StreamSubscription? _subSpeak;

  @override
  void initState() {
    super.initState();
    _load();
    _subSpeak = (widget.livekit.speakingStream as Stream<Set<String>>).listen((s) {
      if (mounted) setState(() => _speaking = s);
    });
  }

  @override
  void dispose() {
    _subSpeak?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final m = await widget.api.members(widget.channel.id) as List<Member>;
      if (mounted) setState(() => _members = m);
    } catch (_) {}
  }

  Future<void> _actions(Member m) async {
    if (!widget.channel.isAdmin || m.userId == widget.myUserId) return;
    if (m.role == 'creator') return;
    final act = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(m.callsign, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            ListTile(
              leading: Icon(m.muted ? Icons.mic : Icons.mic_off, color: AppTheme.warning),
              title: Text(m.muted ? 'Снять мьют' : 'Замьютить'),
              onTap: () => Navigator.pop(ctx, 'mute'),
            ),
            ListTile(
              leading: const Icon(Icons.exit_to_app, color: AppTheme.danger),
              title: const Text('Кикнуть из канала'),
              onTap: () => Navigator.pop(ctx, 'kick'),
            ),
            if (widget.channel.isCreator)
              ListTile(
                leading: const Icon(Icons.block, color: AppTheme.danger),
                title: const Text('Забанить'),
                onTap: () => Navigator.pop(ctx, 'ban'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (act == null) return;
    try {
      if (act == 'mute') await widget.api.mute(widget.channel.id, m.userId, !m.muted);
      if (act == 'kick') await widget.api.kick(widget.channel.id, m.userId);
      if (act == 'ban') await widget.api.ban(widget.channel.id, m.userId);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = _members.where((m) => m.online).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.channel.name),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('$online онлайн · ${_members.length} всего',
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: AppTheme.accent,
        onRefresh: _load,
        child: ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: _members.length,
          separatorBuilder: (_, __) => const SizedBox(height: 4),
          itemBuilder: (_, i) {
            final m = _members[i];
            final speaking = _speaking.contains(m.userId);
            return Card(
              color: speaking ? AppTheme.accentDim : AppTheme.card,
              child: ListTile(
                onLongPress: () => _actions(m),
                leading: CircleAvatar(
                  backgroundColor: speaking
                      ? AppTheme.accent
                      : m.online
                          ? AppTheme.card
                          : AppTheme.border,
                  child: Text(
                    m.initial,
                    style: TextStyle(
                      color: speaking ? Colors.black : AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(m.callsign, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    if (m.role == 'creator' || m.role == 'admin') ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accentDim,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          m.role == 'creator' ? 'СОЗДАТЕЛЬ' : 'АДМИН',
                          style: const TextStyle(fontSize: 9, color: AppTheme.accent, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                    if (m.muted) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.mic_off, size: 14, color: AppTheme.danger),
                    ],
                  ],
                ),
                subtitle: Text(
                  [
                    if (m.route != null) m.route!,
                    m.online ? 'онлайн' : 'офлайн',
                    if (speaking) '· говорит',
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 12,
                    color: speaking ? AppTheme.accent : AppTheme.textSecondary,
                  ),
                ),
                trailing: speaking
                    ? const Icon(Icons.graphic_eq, color: AppTheme.accent)
                    : Icon(Icons.circle, size: 8, color: m.online ? AppTheme.accent : AppTheme.textMuted),
              ),
            );
          },
        ),
      ),
    );
  }
}
