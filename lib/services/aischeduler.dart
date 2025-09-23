import 'dart:convert';
import 'dart:developer' as dev;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:intl/intl.dart';
import '../main.dart'; // gemini + db
import '../home.dart'; // Task model

class AiScheduler {
  /* ------------------------------------------------------------------
   * 1.  Returns the list of time-slots that are **already** blocked
   *     for the given user on the given calendar day.
   * ------------------------------------------------------------------ */
  static Future<List<_BlockedSlot>> _blockedSlots({
    required String uid,
    required DateTime day,
  }) async {
    final start = DateTime(day.year, day.month, day.day, 8); // 08:00
    final end = DateTime(day.year, day.month, day.day, 18); // 18:00

    final snap = await db
        .collection('schedules')
        .where('uid', isEqualTo: uid)
        .where('scheduleDate', isEqualTo: DateFormat('yyyy-MM-dd').format(day))
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return [];

    final List<dynamic> ordered = snap.docs.first.data()['orderedTasks'] ?? [];
    return ordered.map((json) {
      final date = DateFormat('yyyy-MM-dd').parseUtc(json['date']).toLocal();
      final startTime = DateFormat('HH:mm').parseUtc(json['start']).toLocal();
      final realStart = DateTime(
          date.year, date.month, date.day, startTime.hour, startTime.minute);
      final duration = json['durationMin'] as int;
      return _BlockedSlot(
        start: realStart,
        end: realStart.add(Duration(minutes: duration + 15)), // +15 min break
      );
    }).toList();
  }

  /* ------------------------------------------------------------------
   * 2.  Build a prompt that already contains the blocked slots so
   *     Gemini can **never** overlap them.
   * ------------------------------------------------------------------ */
  static Future<String> optimiseAndSave(List<Task> raw) async {
    final today = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(today);
    final uid = raw.first.uid;

    final blocked = await _blockedSlots(uid: uid, day: today);

    final buffer = StringBuffer()
      ..writeln('You are a time-blocking assistant.')
      ..writeln('Working hours: 08:00-18:00.  Break 15 min between tasks.')
      ..writeln('Return ONLY a JSON array like:')
      ..writeln('[{"id":"taskId","start":"HH:mm","date":"$dateStr"}]')
      ..writeln()
      ..writeln('Already blocked slots (never use these times):');

    for (final slot in blocked) {
      buffer.writeln(
          '- ${DateFormat('HH:mm').format(slot.start)}–${DateFormat('HH:mm').format(slot.end)}');
    }

    buffer
      ..writeln()
      ..writeln('Tasks to schedule (only these):');

    final newTasks = raw.where((t) => t.deadline == null).toList();
    if (newTasks.isEmpty) {
      dev.log('🤖  Nothing new to schedule', name: 'AiScheduler');
      return ''; // caller can ignore
    }

    for (final t in newTasks) {
      buffer.writeln(
          '- ${t.id}|${t.title}|${t.durationMin}min|priority:${t.priority.name}');
    }

    final prompt = buffer.toString();
    dev.log('🤖  PROMPT:\n$prompt', name: 'AiScheduler');

    final resp = await gemini.generateContent([Content.text(prompt)]);
    String jsonStr = (resp.text ?? '[]').trim()
        .replaceFirst(RegExp(r'^```json\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '');
    dev.log('🤖  CLEAN GEMINI REPLY:\n$jsonStr', name: 'AiScheduler');

    final List<dynamic> list = jsonDecode(jsonStr);

    /* ----------------------------------------------------------
     * 3.  Merge newly created slots with existing schedule
     * ---------------------------------------------------------- */
    final existingSnap = await db
        .collection('schedules')
        .where('uid', isEqualTo: uid)
        .where('scheduleDate', isEqualTo: dateStr)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    List<dynamic> merged = [];
    if (existingSnap.docs.isNotEmpty) {
      merged = List.from(existingSnap.docs.first.data()['orderedTasks']);
    }

    for (final item in list) {
      final start = DateFormat('HH:mm').parseUtc(item['start']).toLocal();
      final realStart = DateTime(today.year, today.month, today.day,
          start.hour, start.minute);
      merged.add({
        'id': item['id'],
        'title': newTasks.firstWhere((t) => t.id == item['id']).title,
        'durationMin': newTasks.firstWhere((t) => t.id == item['id']).durationMin,
        'start': DateFormat('HH:mm').format(realStart),
        'date': dateStr,
        'priority': newTasks.firstWhere((t) => t.id == item['id']).priority.name,
      });
    }

    // sort by time
    merged.sort((a, b) =>
        DateFormat('HH:mm').parseUtc(a['start']).compareTo(DateFormat('HH:mm').parseUtc(b['start'])));

    /* ----------------------------------------------------------
     * 4.  Write back (update or create)
     * ---------------------------------------------------------- */
    final docId = existingSnap.docs.isEmpty
        ? (await db.collection('schedules').add({
            'uid': uid,
            'scheduleDate': dateStr,
            'orderedTasks': merged,
            'createdAt': FieldValue.serverTimestamp(),
          }))
            .id
        : await () {
            final id = existingSnap.docs.first.id;
            db.collection('schedules').doc(id).update({
              'orderedTasks': merged,
              'createdAt': FieldValue.serverTimestamp(),
            });
            return id;
          }();

    return docId;
  }
}

/* ----------------------------------------------------------
 * tiny helper
 * ---------------------------------------------------------- */
class _BlockedSlot {
  final DateTime start;
  final DateTime end;
  _BlockedSlot({required this.start, required this.end});
}