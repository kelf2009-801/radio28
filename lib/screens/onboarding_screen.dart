import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Callsign + route onboarding. Generates keypair on submit.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final Future<void> Function(String callsign, String route) onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _callsign = TextEditingController();
  final _route = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _callsign.dispose();
    _route.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cs = _callsign.text.trim();
    if (cs.length < 2) {
      _toast('Позывной — минимум 2 символа');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onDone(cs, _route.text.trim());
    } catch (e) {
      _toast('Ошибка: $e');
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppTheme.accentDim,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.accent.withOpacity(0.4)),
                  ),
                  child: const Icon(Icons.settings_input_antenna, color: AppTheme.accent, size: 36),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Рация',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 6),
              const Text(
                'Онлайн-рация для водителей',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 32),
              const Text('ПОЗЫВНОЙ', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, letterSpacing: 1)),
              const SizedBox(height: 6),
              TextField(
                controller: _callsign,
                maxLength: 20,
                decoration: const InputDecoration(hintText: 'Как тебя слышать в эфире', counterText: ''),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 14),
              const Text('МАРШРУТ (по желанию)', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, letterSpacing: 1)),
              const SizedBox(height: 6),
              TextField(
                controller: _route,
                maxLength: 12,
                decoration: const InputDecoration(hintText: 'Например, №28', counterText: ''),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Text('Начать'),
              ),
              const SizedBox(height: 14),
              const Text(
                'Без номера телефона и паролей.\nАккаунт — это ключ на твоём телефоне.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted, height: 1.5),
              ),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}
