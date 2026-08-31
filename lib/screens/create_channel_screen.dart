import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';

/// Create a new channel: name + open/private + optional invite code.
class CreateChannelScreen extends StatefulWidget {
  const CreateChannelScreen({super.key, required this.api, required this.onCreated});

  final dynamic api;
  final void Function(Channel channel) onCreated;

  @override
  State<CreateChannelScreen> createState() => _CreateChannelScreenState();
}

class _CreateChannelScreenState extends State<CreateChannelScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _isPrivate = true;
  bool _useCode = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.length < 2) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Название — минимум 2 символа')));
      return;
    }
    setState(() => _busy = true);
    try {
      final ch = await widget.api.createChannel(
        name,
        inviteCode: _useCode ? _code.text.trim() : null,
        isPrivate: _isPrivate,
      ) as Channel;
      if (mounted) widget.onCreated(ch);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        final msg = e.toString().contains('channel_name_taken')
            ? 'Канал с таким названием уже занят. Придумай другое.'
            : 'Ошибка: $e';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Новый канал')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('НАЗВАНИЕ', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, letterSpacing: 1)),
          const SizedBox(height: 6),
          TextField(
            controller: _name,
            maxLength: 30,
            decoration: const InputDecoration(
              hintText: 'Например, Сызрань-28',
              counterText: '',
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 20),

          const Text('ДОСТУП', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, letterSpacing: 1)),
          const SizedBox(height: 6),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                RadioListTile<bool>(
                  value: true,
                  groupValue: _isPrivate,
                  onChanged: (v) => setState(() => _isPrivate = v!),
                  title: const Text('Приватный', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Водители находят поиском, входят по заявке — ты подтверждаешь',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  activeColor: AppTheme.accent,
                ),
                const Divider(height: 1),
                RadioListTile<bool>(
                  value: false,
                  groupValue: _isPrivate,
                  onChanged: (v) => setState(() => _isPrivate = v!),
                  title: const Text('Открытый', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Нашёл → вошёл сразу, без заявок (общий эфир)',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  activeColor: AppTheme.accent,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          SwitchListTile(
            value: _useCode,
            onChanged: (v) => setState(() => _useCode = v),
            title: const Text('Код-приглашение'),
            subtitle: const Text('Кто знает код — входит без заявки',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            activeColor: AppTheme.accent,
          ),
          if (_useCode) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration: const InputDecoration(
                hintText: 'Код, например 6 цифр',
                counterText: '',
              ),
            ),
          ],

          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _busy ? null : _create,
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Text('Создать канал'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Ты станешь создателем канала: сможешь принимать заявки, мьютить и кикать.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted, height: 1.5),
          ),
        ],
      ),
    );
  }
}
