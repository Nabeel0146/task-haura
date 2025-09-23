import 'dart:convert';
import 'dart:developer' as dev;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:intl/intl.dart';
import '../main.dart'; // gemini + db
import '../home.dart'; // Task model

class AiScheduler {
  /* ----------  already blocked slots for a calendar day  ---------- */
  static Future<List<_BlockedSlot>> _blockedSlots({
    required String uid,
    required DateTime day,
  }) async {
    final snap = await db
        .collection('schedules')
        .where('uid', isEqualTo: uid)
        .where('scheduleDate', isEqualTo: DateFormat('yyyy-MM-dd').format(day))
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return [];

    return (snap.docs.first.data()['orderedTasks'] as List<dynamic>)
        .map((json) {
      final date = DateFormat('yyyy-MM-dd').parseUtc(json['date']).toLocal();
      final start = DateFormat('HH:mm').parseUtc(json['start']).toLocal();
      final realStart =
          DateTime(date.year, date.month, date.day, start.hour, start.minute);
      final dur = json['durationMin'] as int;
      return _BlockedSlot(
        start: realStart,
        end: realStart.add(Duration(minutes: dur + 15)), // incl. break
      );
    }).toList();
  }

  /* ================================================================
   *  MAIN ENTRY-POINT
   *  ---------------------------------------------------------------  
   *  1.  Builds a prompt that contains TASK TITLE so Gemini can
   *      reason about *what* the task is (reading, gym, coding …).
   *  2.  Stores a short human-readable REASON for every placement.
   * ================================================================ */
  static Future<String> optimiseAndSave(List<Task> raw) async {
    final today = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(today);
    final uid = raw.first.uid;

    /* ----------  1.  schedule every task  ---------- */
    final tasksToSchedule = raw;
    if (tasksToSchedule.isEmpty) {
      dev.log('🤖  No tasks provided', name: 'AiScheduler');
      return '';
    }

    /* ----------  2.  build prompt with blocked slots  ---------- */
    final blocked = await _blockedSlots(uid: uid, day: today);

    final buffer = StringBuffer()
      ..writeln('You are an expert productivity coach.')
      ..writeln('Working hours: 08:00-18:00.  15 min break between tasks.')
      ..writeln('')
      ..writeln('Already blocked slots (never overlap):');
    for (final s in blocked) {
      buffer.writeln(
          '- ${DateFormat('HH:mm').format(s.start)}–${DateFormat('HH:mm').format(s.end)}');
    }
    buffer
      ..writeln('')
      ..writeln('Tasks to schedule:');
    for (final t in tasksToSchedule) {
      buffer.writeln(
          '- ID:${t.id}|TITLE:${t.title}|DURATION:${t.durationMin}min|PRIORITY:${t.priority.name}');
    }
    buffer
      ..writeln('')
      ..writeln('Return **ONLY** a JSON array like:')
      ..writeln('[{"id":"taskId","start":"HH:mm","date":"$dateStr","reason":"short reason"}]')
      ..writeln('')
      ..writeln('Pick times that suit the *type* of task (reading → morning/evening, meetings → mid-day, gym → afternoon, etc.).');

    /* ----------  3.  call Gemini for times  ---------- */
    final resp = await gemini.generateContent([Content.text(buffer.toString())]);
    String jsonStr = (resp.text ?? '[]').trim()
        .replaceFirst(RegExp(r'^```json\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '');
    dev.log('🤖  GEMINI TIME REPLY:\n$jsonStr', name: 'AiScheduler');
    final List<dynamic> timeList = jsonDecode(jsonStr);

    /* ----------  4.  build a second prompt for reasons  ---------- */
    final reasonBuffer = StringBuffer()
      ..writeln('For each task below give ONE short reason (≤12 words) why its time was chosen.')
      ..writeln('Reply **ONLY** in JSON: {"taskId":"reason"}');
    for (final t in timeList) {
      final task = tasksToSchedule.firstWhere((tk) => tk.id == t['id']);
      reasonBuffer.writeln('- ${t['id']}: ${task.title} at ${t['start']}');
    }

    final reasonResp = await gemini.generateContent([Content.text(reasonBuffer.toString())]);
    String reasonJsonStr = (reasonResp.text ?? '{}').trim()
        .replaceFirst(RegExp(r'^```json\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '');
    dev.log('🤖  GEMINI REASON REPLY:\n$reasonJsonStr', name: 'AiScheduler');
    final Map<String, dynamic> reasons = jsonDecode(reasonJsonStr);

    /* ----------  5.  merge with existing schedule  ---------- */
    final existingSnap = await db
        .collection('schedules')
        .where('uid', isEqualTo: uid)
        .where('scheduleDate', isEqualTo: dateStr)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    List<dynamic> merged =
        existingSnap.docs.isEmpty ? [] : List.from(existingSnap.docs.first.data()['orderedTasks']);

    for (final t in timeList) {
      final start = DateFormat('HH:mm').parseUtc(t['start']).toLocal();
      final realStart = DateTime(today.year, today.month, today.day,
          start.hour, start.minute);
      final task = tasksToSchedule.firstWhere((tk) => tk.id == t['id']);

      merged.add({
        'id': t['id'],
        'title': task.title,
        'durationMin': task.durationMin,
        'start': DateFormat('HH:mm').format(realStart),
        'date': dateStr,
        'priority': task.priority.name,
        'reason': reasons[t['id']] ?? 'Optimised by AI', // ← NEW
      });
    }

    // sort by clock time
    merged.sort((a, b) =>
        DateFormat('HH:mm').parseUtc(a['start']).compareTo(DateFormat('HH:mm').parseUtc(b['start'])));

    /* ----------  6.  write back  ---------- */
    if (existingSnap.docs.isEmpty) {
      final doc = await db.collection('schedules').add({
        'uid': uid,
        'scheduleDate': dateStr,
        'orderedTasks': merged,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return doc.id;
    } else {
      final id = existingSnap.docs.first.id;
      await db.collection('schedules').doc(id).update({
        'orderedTasks': merged,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return id;
    }
  }
}

/* ----------  helper  ---------- */
class _BlockedSlot {
  final DateTime start;
  final DateTime end;
  _BlockedSlot({required this.start, required this.end});
}