import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../models/models.dart';
import 'create_channel_screen.dart';

/// Profile / channel / sound settings + server URL + logout.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.auth,
    required this.channel,
    required this.api,
    required this.onLeaveChannel,
    required this.onUpdateProfile,
  });

  final dynamic auth; // AuthService
  final Channel? channel;
  final dynamic api;
  final VoidCallback onLeaveChannel;
  final Future<void> Function(String? route) onUpdateProfile;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _serverCtrl = TextEditingController();
  bool _noiseSuppression = true;
  bool _pttSound = true;
  bool _vibrationOn = true;

  @override
  void initState() {
    super.initState();
    _load();
  }
  Future<void> _load() async {
    final s = await widget.auth.serverUrl as String;
    final prefs = await widget.auth.prefs();
    if (mounted) {
      setState(() {
        _serverCtrl.text = s;
        _noiseSuppression = prefs['noise_suppression'] as bool? ?? true;
        _pttSound = prefs['ptt_sound'] as bool? ?? true;
        _vibrationOn = prefs['vibration_on'] as bool? ?? true;
      });
    }
  }

  Future<void> _saveSetting(String key, bool value) async {
    await widget.auth.savePref(key, value);
  }

  Future<void> _saveServer() async {
    final v = _serverCtrl.text.trim();
    if (v.isEmpty) return;
    await widget.auth.setServerUrl(v);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Сервер сохранён. Перезапусти приложение.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.auth.profile as Profile?;
    final ch = widget.channel;
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _group('Профиль', [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AppTheme.accentDim,
                child: Text(
                  (p?.callsign.isNotEmpty ?? false) ? p!.callsign[0].toUpperCase() : '?',
                  style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w700),
                ),
              ),
              title: Text(p?.callsign ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Позывной (не меняется)',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            ),
            ListTile(
              leading: const Icon(Icons.route_outlined, color: AppTheme.textSecondary),
              title: const Text('Маршрут'),
              subtitle: Text(p?.route ?? 'не указан',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              trailing: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.textMuted),
              onTap: _editRoute,
            ),
          ]),
          if (ch != null) ...[
            _group('Канал', [
              ListTile(
                title: Text(ch.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(ch.isPrivate ? 'Приватный' : 'Открытый',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                trailing: Text('${ch.memberCount} чел.',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              ),
              if (ch.isCreator)
                ListTile(
                  leading: const Icon(Icons.qr_code, color: AppTheme.accent),
                  title: const Text('Код-приглашение'),
                  subtitle: const Text('Сгенерить новый (старый перестанет работать)',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  onTap: _regenCode,
                ),
              ListTile(
                leading: const Icon(Icons.add_circle_outline, color: AppTheme.accent),
                title: const Text('Создать ещё канал'),
                subtitle: const Text('Открытый или приватный',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final created = await Navigator.push<Channel>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CreateChannelScreen(
                        api: widget.api,
                        onCreated: (c) => Navigator.pop(context, c),
                      ),
                    ),
                  );
                  if (created != null && mounted) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Канал «${created.name}» создан')),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: AppTheme.danger),
                title: const Text('Выйти из канала', style: TextStyle(color: AppTheme.danger)),
                onTap: widget.onLeaveChannel,
              ),
            ]),
          ],
          _group('Звук', [
            SwitchListTile(
              value: _noiseSuppression,
              onChanged: (v) {
                setState(() => _noiseSuppression = v);
                _saveSetting('noise_suppression', v);
              },
              title: const Text('Шумоподавление'),
              subtitle: const Text('Убирает фоновый шум',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              activeColor: AppTheme.accent,
            ),
            SwitchListTile(
              value: _pttSound,
              onChanged: (v) {
                setState(() => _pttSound = v);
                _saveSetting('ptt_sound', v);
              },
              title: const Text('Звук нажатия PTT'),
              activeColor: AppTheme.accent,
            ),
            SwitchListTile(
              value: _vibrationOn,
              onChanged: (v) {
                setState(() => _vibrationOn = v);
                _saveSetting('vibration_on', v);
              },
              title: const Text('Вибрация при нажатии'),
              activeColor: AppTheme.accent,
            ),
          ]),
          _group('Сервер', [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextField(
                controller: _serverCtrl,
                decoration: const InputDecoration(
                  hintText: 'http://IP:8000',
                  labelText: 'Адрес сервера',
                ),
                keyboardType: TextInputType.url,
                onEditingComplete: _saveServer,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: OutlinedButton(
                onPressed: _saveServer,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.border),
                  foregroundColor: AppTheme.textPrimary,
                ),
                child: const Text('Сохранить адрес'),
              ),
            ),
          ]),
          _group('О приложении', [
            const ListTile(
              title: Text('Версия'),
              trailing: Text('1.0.0', style: TextStyle(color: AppTheme.textMuted)),
            ),
            ListTile(
              title: const Text('Скопировать ID устройства'),
              subtitle: const Text('Для восстановления аккаунта',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
              onTap: () {
                final id = p?.userId ?? '';
                Clipboard.setData(ClipboardData(text: id));
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('ID скопирован')));
              },
            ),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _regenCode() async {
    try {
      final code = await widget.api.regenerateInviteCode(widget.channel!.id) as String;
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Новый код-приглашение'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(
                code,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.accent,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 8),
              const Text('Старый код больше не работает',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ОК')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  Widget _group(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Text(title.toUpperCase(),
              style: const TextStyle(
                  fontSize: 11, color: AppTheme.textMuted, letterSpacing: 1, fontWeight: FontWeight.w700)),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
    );
  }

  Future<void> _editRoute() async {
    final p = widget.auth.profile as Profile?;
    final ctrl = TextEditingController(text: p?.route ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Маршрут'),
        content: TextField(
          controller: ctrl,
          maxLength: 12,
          decoration: const InputDecoration(hintText: 'Например, №28', counterText: ''),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Сохранить', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
    if (result == null) return;
    await widget.onUpdateProfile(result.isEmpty ? null : result);
    if (mounted) setState(() {});
  }
}
