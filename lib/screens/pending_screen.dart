import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';

/// "Request sent — wait for admin approval" + polling join_status.
class PendingScreen extends StatefulWidget {
  const PendingScreen({
    super.key,
    required this.channel,
    required this.api,
    required this.onApproved,
    required this.onCancel,
  });

  final Channel channel;
  final dynamic api;
  final VoidCallback onApproved;
  final VoidCallback onCancel;

  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen> {
  Timer? _poll;
  String _status = 'pending';
  String? _reason;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _check());
    _check();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final j = await widget.api.joinStatus(widget.channel.id) as Map<String, dynamic>;
      final s = j['status'] as String? ?? 'pending';
      if (!mounted) return;
      if (s == 'member') {
        _poll?.cancel();
        widget.onApproved();
      } else if (s == 'rejected') {
        setState(() {
          _status = 'rejected';
          _reason = j['reason'] as String?;
        });
        _poll?.cancel();
      } else {
        setState(() => _status = s);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final rejected = _status == 'rejected';
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: rejected ? AppTheme.danger : AppTheme.accent,
                    width: 2,
                  ),
                ),
                child: Icon(
                  rejected ? Icons.close : Icons.schedule,
                  color: rejected ? AppTheme.danger : AppTheme.accent,
                  size: 36,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                rejected ? 'Запрос отклонён' : 'Ожидание подтверждения',
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                rejected
                    ? (_reason?.isNotEmpty ?? false ? 'Причина: $_reason' : 'Админ отклонил запрос')
                    : 'Администратор должен подтвердить твой запрос.\nПридёт уведомление, когда примут.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 16),
              Chip(
                label: Text(widget.channel.name),
                backgroundColor: AppTheme.card,
                side: const BorderSide(color: AppTheme.border),
                labelStyle: const TextStyle(color: AppTheme.accent),
              ),
              const SizedBox(height: 32),
              TextButton(
                onPressed: widget.onCancel,
                child: Text(rejected ? 'Назад' : 'Отменить запрос', style: const TextStyle(color: AppTheme.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
