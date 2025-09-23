import 'dart:convert';
import 'dart:developer' as dev;
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/material.dart';
import '../main.dart';          // gemini instance + navigatorKey
import '../home.dart';          // Task model

class AiScheduler {
  /// Calls Gemini and returns the same tasks with AI-chosen start times.
  static Future<List<Task>> optimise(List<Task> raw) async {
    final prompt = '''
You are a time-blocking assistant.
Working hours: 08:00-18:00. Break 15 min between tasks.
Return ONLY a JSON array like [{"id":"taskId","start":"HH:mm"}].

Tasks:
${raw.map((t) => '- ${t.id}|${t.title}|${t.durationMin}min|priority:${t.priority.name}').join('\n')}
''';

    final resp = await gemini.generateContent([Content.text(prompt)]);
    final jsonStr = resp.text ?? '[]';

    // 1. console proof
    dev.log('🤖  RAW GEMINI REPLY:\n$jsonStr', name: 'AiScheduler');

    // 2. on-screen proof
        // 2. on-screen proof
    if (raw.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
          SnackBar(content: Text('AI said: $jsonStr')),
        );
      });
    }

    final List<dynamic> list = jsonDecode(jsonStr);
    final Map<String, DateTime> starts = {
      for (final e in list) e['id']: _todayAt(e['start'])
    };

    return raw.map((t) {
      final start = starts[t.id] ?? t.deadline;
      return Task(
        id: t.id,
        title: t.title,
        desc: t.desc,
        durationMin: t.durationMin,
        deadline: start,          // we reuse this field for start time
        priority: t.priority,
        uid: t.uid,
      );
    }).toList();
  }

  static DateTime _todayAt(String hhmm) {
    final p = hhmm.split(':');
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day, int.parse(p[0]), int.parse(p[1]));
  }
}