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
    this.embedded = false,
    this.onJoined,
  });

  final Channel channel;
  final dynamic api;
  final String myUserId;
  final dynamic livekit;
  final bool embedded; // true = shown as bottom-nav tab (no back button)
  final void Function(Channel channel)? onJoined; // for direct call switch

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.member, required this.speaking});
  final Member member;
  final bool speaking;

  @override
  Widget build(BuildContext context) {
    // If member has avatarPath (from profile) — show photo, else initial
    // Note: Member model doesn't have avatarPath yet — using initial with color
    final bgColor = speaking
        ? AppTheme.accent
        : member.online
            ? AppTheme.accentDim
            : AppTheme.border;
    final textColor = speaking ? Colors.black : AppTheme.textPrimary;
    return CircleAvatar(
      backgroundColor: bgColor,
      child: Text(
        member.initial,
        style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _MembersScreenState extends State<MembersScreen> {
  List<Member> _members = [];
  Set<String> _speaking = {};
  StreamSubscription? _subSpeak;

  @override
  void initState() {
    super.initState();
    _load();
    // Refresh members every 5 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _load();
    });
    _subSpeak = (widget.livekit.speakingStream as Stream<Set<String>>).listen((s) {
      if (mounted) setState(() => _speaking = s);
    });
  }

  Timer? _refreshTimer;

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _subSpeak?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final m = await widget.api.members(widget.channel.id) as List<Member>;
      if (mounted) {
        setState(() => _members = m);
        print('Members loaded: ${m.length}');
      }
    } catch (e) {
      print('Members load error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки участников: $e')),
        );
      }
    }
  }

  Future<void> _actions(Member m) async {
    if (widget.channel.role != 'creator' || m.userId == widget.myUserId) return;
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
              leading: const Icon(Icons.record_voice_over, color: AppTheme.accent),
              title: const Text('Говорить только ему'),
              subtitle: const Text('Личный вызов (в разработке)', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              onTap: () => Navigator.pop(ctx, 'private_call'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(m.muted ? Icons.mic : Icons.mic_off, color: AppTheme.warning),
              title: Text(m.muted ? 'Снять мьют (включить микрофон)' : 'Замьютить (выключить микрофон)'),
              onTap: () => Navigator.pop(ctx, 'mute'),
            ),
            ListTile(
              leading: const Icon(Icons.volume_off, color: AppTheme.warning),
              title: const Text('Отключить звук (не слышит эфир)'),
              onTap: () => Navigator.pop(ctx, 'deafen'),
            ),
            if (widget.channel.isCreator)
              ListTile(
                leading: const Icon(Icons.shield_outlined, color: AppTheme.accent),
                title: Text(m.role == 'admin' ? 'Снять админа' : 'Назначить админом'),
                onTap: () => Navigator.pop(ctx, 'toggle_admin'),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.exit_to_app, color: AppTheme.danger),
              title: const Text('Кикнуть из канала'),
              onTap: () => Navigator.pop(ctx, 'kick'),
            ),
            if (widget.channel.isCreator)
              ListTile(
                leading: const Icon(Icons.block, color: AppTheme.danger),
                title: const Text('Забанить (не сможет вернуться)'),
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
      if (act == 'toggle_admin') await widget.api.setRole(widget.channel.id, m.userId, m.role == 'admin' ? 'member' : 'admin');
      if (act == 'private_call') {
        // Create direct channel and switch to it
        try {
          final direct = await widget.api.createDirectChannel(m.userId) as Channel;
          if (mounted) {
            Navigator.pop(context); // close members screen
            // Switch to the direct channel
            if (widget.onJoined != null) {
              widget.onJoined!(direct);
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Ошибка: $e')),
            );
          }
        }
      }
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
    final body = RefreshIndicator(
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
              leading: _MemberAvatar(member: m, speaking: speaking),
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
                    Icon(Icons.mic_off, size: 14, color: AppTheme.danger),
                  ],
                  if (m.deafened) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.volume_off, size: 14, color: AppTheme.warning),
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
    );

    if (widget.embedded) {
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
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
        body: body,
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AppTheme.accent,
          foregroundColor: Colors.black,
          icon: const Icon(Icons.mic),
          label: const Text('Говорить', style: TextStyle(fontWeight: FontWeight.w700)),
          onPressed: () {
            // Switch to Radio tab (index 0) — the main PTT is there
            // This is a hint: user taps the big PTT on Radio tab
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Перейди на вкладку «Рация» — там большая кнопка')),
            );
          },
        ),
      );
    }

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
      body: body,
    );
  }
}
