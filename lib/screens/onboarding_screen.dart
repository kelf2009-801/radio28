import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Onboarding: avatar (auto from callsign, changeable color) + callsign + route.
/// No channel search here — user does it on the next screen.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final Future<void> Function(String callsign, String route, int avatarColor) onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _callsign = TextEditingController();
  final _route = TextEditingController();
  bool _busy = false;
  int _colorIdx = 0;

  static const _colors = [
    Color(0xFF00FF8C), // green
    Color(0xFF4D9FFF), // blue
    Color(0xFFFFB84D), // orange
    Color(0xFFFF6B9D), // pink
    Color(0xFFB98CFF), // purple
    Color(0xFFFF5C5C), // red
  ];

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
      await widget.onDone(cs, _route.text.trim(), _colorIdx);
    } catch (e) {
      _toast('Нет связи с сервером. Проверь интернет и попробуй ещё раз.');
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final initial = _callsign.text.isEmpty ? '?' : _callsign.text[0].toUpperCase();
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: [
            const SizedBox(height: 48),
            // Logo
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
              'SHALUN',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 2, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 6),
            const Text(
              'Онлайн-рация для водителей',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 32),

            // Avatar preview + color picker
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: _colors[_colorIdx].withOpacity(0.2),
                    child: Text(
                      initial,
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: _colors[_colorIdx]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_colors.length, (i) {
                      final sel = i == _colorIdx;
                      return GestureDetector(
                        onTap: () => setState(() => _colorIdx = i),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: _colors[i],
                            shape: BoxShape.circle,
                            border: sel ? Border.all(color: Colors.white, width: 2) : null,
                          ),
                          child: sel ? const Icon(Icons.check, color: Colors.black, size: 16) : null,
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            const Text('ПОЗЫВНОЙ', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, letterSpacing: 1)),
            const SizedBox(height: 6),
            TextField(
              controller: _callsign,
              maxLength: 20,
              decoration: const InputDecoration(hintText: 'Как тебя слышать в эфире', counterText: ''),
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
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
              'Без номера телефона и паролей.\nНа следующем экране найдёшь канал.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted, height: 1.5),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
