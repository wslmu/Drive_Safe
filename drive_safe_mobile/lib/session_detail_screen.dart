import 'package:flutter/material.dart';

import 'session_history.dart';

class SessionDetailScreen extends StatelessWidget {
  final SessionRecord session;

  const SessionDetailScreen({
    super.key,
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
    final entries = session.alertBreakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      backgroundColor: const Color(0xFF08111D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF08111D),
        foregroundColor: Colors.white,
        title: const Text('Detail de session'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Resume', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
                const SizedBox(height: 10),
                Text('Duree: ${_formatDuration(session.durationSeconds)}', style: const TextStyle(color: Color(0xFF8FA2B7))),
                Text('Alertes totales: ${session.alertCount}', style: const TextStyle(color: Color(0xFF8FA2B7))),
                Text('Score fatigue max: ${session.maxFatigueScore}', style: const TextStyle(color: Color(0xFF8FA2B7))),
                Text('Score fatigue moyen: ${session.averageFatigueScore}', style: const TextStyle(color: Color(0xFF8FA2B7))),
                Text('Etat dominant: ${session.dominantState}', style: const TextStyle(color: Color(0xFF8FA2B7))),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Causes des alertes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
                const SizedBox(height: 10),
                if (entries.every((entry) => entry.value == 0))
                  const Text('Aucune alerte detaillee enregistree.', style: TextStyle(color: Color(0xFF8FA2B7)))
                else
                  ...entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _label(entry.key),
                              style: const TextStyle(color: Color(0xFF8FA2B7)),
                            ),
                          ),
                          Text(
                            '${entry.value}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Chronologie des alertes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
                const SizedBox(height: 10),
                if (session.alertEvents.isEmpty)
                  const Text('Aucun evenement enregistre.', style: TextStyle(color: Color(0xFF8FA2B7)))
                else
                  ...session.alertEvents.reversed.map(
                    (event) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('• $event', style: const TextStyle(color: Color(0xFF8FA2B7))),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _label(String key) {
    switch (key) {
      case 'eyes_closed':
        return 'Yeux fermes longtemps';
      case 'repeated_yawn':
        return 'Baillements repetes';
      case 'head_tilt':
        return 'Tete inclinee';
      case 'head_forward':
        return 'Tete vers avant';
      default:
        return key;
    }
  }

  String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final remMinutes = minutes % 60;
      return '${hours}h ${remMinutes.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class _Panel extends StatelessWidget {
  final Widget child;

  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111E2D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF243C55)),
      ),
      child: child,
    );
  }
}
