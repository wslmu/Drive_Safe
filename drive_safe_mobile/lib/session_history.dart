import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_bootstrap.dart';

class SessionRecord {
  final String startedAtIso;
  final int durationSeconds;
  final int alertCount;
  final Map<String, int> alertBreakdown;
  final List<String> alertEvents;
  final int maxFatigueScore;
  final int averageFatigueScore;
  final String dominantState;

  const SessionRecord({
    required this.startedAtIso,
    required this.durationSeconds,
    required this.alertCount,
    required this.alertBreakdown,
    required this.alertEvents,
    required this.maxFatigueScore,
    required this.averageFatigueScore,
    required this.dominantState,
  });

  Map<String, dynamic> toJson() {
    return {
      'startedAtIso': startedAtIso,
      'durationSeconds': durationSeconds,
      'alertCount': alertCount,
      'alertBreakdown': alertBreakdown,
      'alertEvents': alertEvents,
      'maxFatigueScore': maxFatigueScore,
      'averageFatigueScore': averageFatigueScore,
      'dominantState': dominantState,
    };
  }

  factory SessionRecord.fromJson(Map<String, dynamic> json) {
    return SessionRecord(
      startedAtIso: json['startedAtIso'] as String? ?? '',
      durationSeconds: json['durationSeconds'] as int? ?? 0,
      alertCount: json['alertCount'] as int? ?? 0,
      alertBreakdown: (json['alertBreakdown'] as Map<String, dynamic>? ?? const {})
          .map((key, value) => MapEntry(key, (value as num?)?.toInt() ?? 0)),
      alertEvents: ((json['alertEvents'] as List<dynamic>?) ?? const [])
          .map((item) => item.toString())
          .toList(),
      maxFatigueScore: json['maxFatigueScore'] as int? ?? 0,
      averageFatigueScore: json['averageFatigueScore'] as int? ?? 0,
      dominantState: json['dominantState'] as String? ?? 'Session terminee',
    );
  }
}

class SessionHistoryStore {
  static const _keyPrefix = 'drive_safe_sessions';
  static const _maxItems = 20;

  static Future<List<SessionRecord>> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_storageKey()) ?? <String>[];
    final local = raw
        .map((item) => SessionRecord.fromJson(jsonDecode(item) as Map<String, dynamic>))
        .toList();

    if (!FirebaseBootstrap.isEnabled) {
      return local;
    }

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return local;

      final query = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('sessions')
          .orderBy('savedAt', descending: true)
          .limit(_maxItems)
          .get();

      final cloud = query.docs
          .map((doc) => SessionRecord.fromJson(doc.data()))
          .toList();

      return _mergeSessions(cloud, local);
    } catch (_) {
      return local;
    }
  }

  static Future<void> saveSession(SessionRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_storageKey()) ?? <String>[];
    final updated = <String>[jsonEncode(record.toJson()), ...existing];
    await prefs.setStringList(_storageKey(), updated.take(_maxItems).toList());

    if (!FirebaseBootstrap.isEnabled) {
      return;
    }

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final payload = {
        ...record.toJson(),
        'savedAt': FieldValue.serverTimestamp(),
      };

      final id = '${record.startedAtIso}_${record.durationSeconds}';
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('sessions')
          .doc(id)
          .set(payload, SetOptions(merge: true));
    } catch (_) {
      // Local persistence is already done above.
    }
  }

  static List<SessionRecord> _mergeSessions(
    List<SessionRecord> first,
    List<SessionRecord> second,
  ) {
    final merged = <SessionRecord>[];
    final seen = <String>{};

    for (final record in [...first, ...second]) {
      final key = '${record.startedAtIso}_${record.durationSeconds}';
      if (seen.add(key)) {
        merged.add(record);
      }
      if (merged.length >= _maxItems) break;
    }

    merged.sort((a, b) => b.startedAtIso.compareTo(a.startedAtIso));
    return merged.take(_maxItems).toList();
  }

  static String _storageKey() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return '${_keyPrefix}_guest';
    }
    return '${_keyPrefix}_$uid';
  }
}
