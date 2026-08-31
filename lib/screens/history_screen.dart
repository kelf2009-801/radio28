import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';

/// History of calls in the channel (who, when, how long).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.channel, required this.api});
  final Channel channel;
  final dynamic api;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<HistoryEntry> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final h = await widget.api.history(widget.channel.id) as List<HistoryEntry>;
      if (mounted) {
        setState(() {
          _items = h;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('История')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : _items.isEmpty
              ? const Center(
                  child: Text('Пока тихо', style: TextStyle(color: AppTheme.textMuted)))
              : RefreshIndicator(
                  color: AppTheme.accent,
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final e = _items[i];
                      final dur = e.durationSec;
                      final durStr = dur >= 60
                          ? '${(dur / 60).floor()}м ${(dur % 60).round()}с'
                          : '${dur.round()}с';
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: AppTheme.accentDim,
                          child: Text(
                            e.callsign.isEmpty ? '?' : e.callsign[0].toUpperCase(),
                            style: const TextStyle(fontSize: 12, color: AppTheme.accent),
                          ),
                        ),
                        title: Text(e.callsign, style: const TextStyle(fontSize: 14)),
                        subtitle: Text(e.startedAt,
                            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        trailing: Text(durStr,
                            style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w600)),
                      );
                    },
                  ),
                ),
    );
  }
}
