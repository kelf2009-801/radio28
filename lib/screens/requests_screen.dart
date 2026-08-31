import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';

/// Admin's join-request inbox: approve / reject with reason.
class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key, required this.channel, required this.api});
  final Channel channel;
  final dynamic api;

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  List<JoinRequest> _reqs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.joinRequests(widget.channel.id) as List<JoinRequest>;
      if (mounted) {
        setState(() {
          _reqs = r;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(JoinRequest r) async {
    try {
      await widget.api.approve(widget.channel.id, r.id);
      setState(() => _reqs.removeWhere((x) => x.id == r.id));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${r.callsign} принят')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  Future<void> _reject(JoinRequest r) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: Text('Отклонить ${r.callsign}?'),
          content: TextField(
            controller: c,
            decoration: const InputDecoration(hintText: 'Причина (необязательно)'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Отклонить', style: TextStyle(color: AppTheme.danger)),
            ),
          ],
        );
      },
    );
    if (reason == null) return;
    try {
      await widget.api.reject(widget.channel.id, r.id, reason: reason.isEmpty ? null : reason);
      setState(() => _reqs.removeWhere((x) => x.id == r.id));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Запросы на вход'),
        actions: [
          if (_reqs.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.danger,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${_reqs.length}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : _reqs.isEmpty
              ? const Center(
                  child: Text('Нет новых запросов',
                      style: TextStyle(color: AppTheme.textMuted)))
              : RefreshIndicator(
                  color: AppTheme.accent,
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _reqs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final r = _reqs[i];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: AppTheme.accentDim,
                                child: Text(r.callsign[0].toUpperCase(),
                                    style: const TextStyle(color: AppTheme.accent)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(r.callsign,
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                    if (r.route != null)
                                      Text(r.route!,
                                          style: const TextStyle(
                                              fontSize: 12, color: AppTheme.textSecondary)),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: AppTheme.danger),
                                style: IconButton.styleFrom(
                                  backgroundColor: AppTheme.danger.withOpacity(0.12),
                                ),
                                onPressed: () => _reject(r),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.check, color: AppTheme.accent),
                                style: IconButton.styleFrom(
                                  backgroundColor: AppTheme.accent.withOpacity(0.12),
                                ),
                                onPressed: () => _approve(r),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
