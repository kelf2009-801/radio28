import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/theme.dart';

/// Onboarding: avatar photo (pick from gallery) + callsign + route.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final Future<void> Function(String callsign, String route, String? avatarPath) onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _callsign = TextEditingController();
  final _route = TextEditingController();
  final _picker = ImagePicker();
  String? _avatarPath;
  bool _busy = false;

  @override
  void dispose() {
    _callsign.dispose();
    _route.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      if (picked != null && mounted) {
        setState(() => _avatarPath = picked.path);
      }
    } catch (_) {}
  }

  Future<void> _submit() async {
    final cs = _callsign.text.trim();
    if (cs.length < 2) {
      _toast('Позывной — минимум 2 символа');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onDone(cs, _route.text.trim(), _avatarPath);
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
            const SizedBox(height: 40),
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
            const SizedBox(height: 16),
            const Text(
              'SHALUN',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 2, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 4),
            const Text(
              'Онлайн-рация для водителей',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 28),

            // Avatar photo picker
            Center(
              child: GestureDetector(
                onTap: _pickAvatar,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 52,
                      backgroundColor: AppTheme.card,
                      backgroundImage: _avatarPath != null ? FileImage(File(_avatarPath!)) : null,
                      child: _avatarPath == null
                          ? Text(
                              initial,
                              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: AppTheme.accent),
                            )
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(color: AppTheme.accent, shape: BoxShape.circle),
                        child: const Icon(Icons.camera_alt, size: 16, color: Colors.black),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text('Тапни чтобы выбрать фото', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            ),
            const SizedBox(height: 24),

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
