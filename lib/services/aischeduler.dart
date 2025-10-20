import 'dart:convert';
import 'dart:developer' as dev;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:intl/intl.dart';
import 'package:taskhaura/models/task.dart';
import '../main.dart'; // gemini + db
import '../home.dart'; // Task model

class AiScheduler {
  /* ----------------------------------------------------------
   * 1.  already blocked slots from existing schedule
   * ---------------------------------------------------------- */
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

/* ----------------------------------------------------------
 *  Chat-like prompt for ONE task  (returns pretty message)
 * ---------------------------------------------------------- */
static Future<String> chatSchedule(Task task) async {
  final today = DateTime.now();
  final dateStr = DateFormat('yyyy-MM-dd').format(today);
  

  final blocked = await _blockedSlots(uid: task.uid, day: today);

  final prompt = StringBuffer()
    ..writeln('You are a friendly daily planner.')
    ..writeln('Working day 08:00-18:00, 15 min breaks.')
    ..writeln('Already booked:')
    ..writeln(blocked.map((b) =>
        '- ${DateFormat('HH:mm').format(b.start)}-${DateFormat('HH:mm').format(b.end)}').join('\n'))
    ..writeln('')
    ..writeln('Suggest the **best single slot** for:')
    ..writeln('Title: ${task.title}')
    ..writeln('Duration: ${task.durationMin} min')
    ..writeln('Priority: ${task.priority.name}')
    ..writeln('')
    ..writeln('Reply in **one short sentence** like:')
    ..writeln('"How about 14:30-15:00? It fits perfectly after lunch!"');

  final resp = await gemini.generateContent([Content.text(prompt.toString())]);
  return resp.text?.trim() ?? 'No suggestion available';
}

/* ----------------------------------------------------------
 *  Insert the task at the proposed HH:mm (parse from sentence)
 * ---------------------------------------------------------- */
static Future<void> insertSingleSlot(
  Task task, 
  DateTime startTime, 
  DateTime endTime, 
  {required String userId}
) async {
  final today = DateTime.now();
  final dateStr = DateFormat('yyyy-MM-dd').format(today);

  // read existing schedule
  final schedSnap = await db
      .collection('schedules')
      .where('uid', isEqualTo: userId) // Use the provided userId
      .where('scheduleDate', isEqualTo: dateStr)
      .orderBy('createdAt', descending: true)
      .limit(1)
      .get();

  final List<Map<String, dynamic>> merged =
      schedSnap.docs.isEmpty ? [] : List.from(schedSnap.docs.first.data()['orderedTasks']);

  merged.add({
    'id': task.id,
    'title': task.title,
    'durationMin': task.durationMin,
    'start': DateFormat('HH:mm').format(startTime),
    'date': dateStr,
    'priority': task.priority.name,
    'reason': 'Scheduled by AI assistant',
    'scheduled': true,
  });

  merged.sort((a, b) => DateFormat('HH:mm')
      .parseUtc(a['start'])
      .compareTo(DateFormat('HH:mm').parseUtc(b['start'])));

  if (schedSnap.docs.isEmpty) {
    await db.collection('schedules').add({
      'uid': userId, // Use the provided userId
      'scheduleDate': dateStr,
      'orderedTasks': merged,
      'createdAt': FieldValue.serverTimestamp(),
    });
  } else {
    await db.collection('schedules').doc(schedSnap.docs.first.id).update({
      'orderedTasks': merged,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

  /* ----------------------------------------------------------
   * 2.  MAIN ENTRY-POINT
   *     -  skips already-scheduled tasks (by ID)
   *     -  sends MIRROR AM/PM times to Gemini
   *     -  swaps reply back to real clock
   * ---------------------------------------------------------- */
  static Future<String> optimiseAndSave(List<Task> raw) async {
    final today = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(today);
    final uid = raw.first.uid;

    /* 2.1  read existing schedule --------------------------- */
    final existingSnap = await db
        .collection('schedules')
        .where('uid', isEqualTo: uid)
        .where('scheduleDate', isEqualTo: dateStr)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    final Map<String, dynamic> existingMap = {};
    if (existingSnap.docs.isNotEmpty) {
      for (final slot
          in (existingSnap.docs.first.data()['orderedTasks'] as List<dynamic>)) {
        existingMap[slot['id'] as String] = slot;
      }
    }

    /* 2.2  keep only NEW tasks (ID not present) ------------- */
    final newTasks = raw.where((t) => !existingMap.containsKey(t.id)).toList();
    if (newTasks.isEmpty) {
      dev.log('🤖  All tasks already scheduled', name: 'AiScheduler');
      return existingSnap.docs.isEmpty ? '' : existingSnap.docs.first.id;
    }

    /* 2.3  blocked slots from already-planned tasks --------- */
    final blocked = await _blockedSlots(uid: uid, day: today);

    /* 2.4  prompt Gemini (send MIRROR times) ---------------- */
    final buffer = StringBuffer()
      ..writeln('You are an expert daily-routine planner.')
      ..writeln('Working day: 08:00-18:00. 15 min break between tasks.')
      ..writeln('')
      ..writeln('ACTIVITY-TIME CHEAT-SHEET (match by title / description):')
      ..writeln('- breakfast, lunch, dinner → 19:00-21:00 / 00:00-02:00 / 06:00-08:00 (PM)')
      ..writeln('- reading, study, learn → 21:00-23:00 or 04:00-06:00 (PM/AM reverse)')
      ..writeln('- gym, walk, sport → 18:30-20:00 or 05:00-07:00 (evening / dawn)')
      ..writeln('- meeting, call, email → 22:00-24:00 or 02:00-04:00 (night)')
      ..writeln('- relax, hobby, tv → 09:00-11:00 (morning after swap)')
      ..writeln('- sleep, nap → avoid completely')
      ..writeln('')
      ..writeln('Already blocked (never overlap):');
    for (final s in blocked) {
      final mirrorStart = _mirrorAmPm(s.start);
      final mirrorEnd = _mirrorAmPm(s.end);
      buffer.writeln(
          '- ${DateFormat('HH:mm').format(mirrorStart)}–${DateFormat('HH:mm').format(mirrorEnd)}');
    }
    buffer
      ..writeln('')
      ..writeln('NEW tasks to place (choose best hour using cheat-sheet above):');
    for (final t in newTasks) {
      buffer.writeln(
          '- ID:${t.id}|TITLE:${t.title}|DESC:${t.desc}|DURATION:${t.durationMin}min|PRIORITY:${t.priority.name}');
    }
    buffer
      ..writeln('')
      ..writeln('Return **ONLY** a JSON array like:')
      ..writeln('[{"id":"taskId","start":"HH:mm","date":"$dateStr","reason":"why this hour"}]')
      ..writeln('')
      ..writeln('Pick the **exact clock time** that best matches the activity type. Never place meals at night.');

    final resp = await gemini.generateContent([Content.text(buffer.toString())]);
    String jsonStr = (resp.text ?? '[]').trim()
        .replaceFirst(RegExp(r'^```json\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '');
    dev.log('🤖  GEMINI TIME REPLY:\n$jsonStr', name: 'AiScheduler');
    final List<dynamic> timeList = jsonDecode(jsonStr);

    /* 2.5  reason about the *CLOCK HOUR* (not the task) ---- */
    final reasonBuffer = StringBuffer()
      ..writeln('You are a time-management coach.')
      ..writeln('For each CLOCK TIME below give ONE short reason (≤12 words) '
          'why that hour is good for productivity / energy / focus.')
      ..writeln('Reply **ONLY** in JSON: {"HH:mm":"reason"}');
    for (final t in timeList) {
      reasonBuffer.writeln('- ${t['start']}');
    }
    final reasonResp = await gemini.generateContent([Content.text(reasonBuffer.toString())]);
    String reasonJsonStr = (reasonResp.text ?? '{}').trim()
        .replaceFirst(RegExp(r'^```json\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '');
    dev.log('🤖  GEMINI REASON REPLY:\n$reasonJsonStr', name: 'AiScheduler');
    final Map<String, dynamic> reasons = jsonDecode(reasonJsonStr);

    /* 2.6  merge NEW slots into existing map (MIRROR → REAL) -- */
    for (final t in timeList) {
      final mirrorTime = DateFormat('HH:mm').parseUtc(t['start']).toLocal();
      final realStart = _mirrorAmPm(DateTime(today.year, today.month, today.day,
                                   mirrorTime.hour, mirrorTime.minute));

      final task = newTasks.firstWhere((tk) => tk.id == t['id']);

      existingMap[t['id'] as String] = {
        'id': t['id'],
        'title': task.title,
        'durationMin': task.durationMin,
        'start': DateFormat('HH:mm').format(realStart),
        'date': dateStr,
        'priority': task.priority.name,
        'reason': reasons[t['start']] ?? 'Optimised by AI', // ← hour-keyed
        'scheduled': true,
      };
    }

    /* 2.7  convert map → sorted list ------------------------ */
    final merged = existingMap.values.toList()
      ..sort((a, b) =>
          DateFormat('HH:mm').parseUtc(a['start']).compareTo(DateFormat('HH:mm').parseUtc(b['start'])));

    /* 2.8  write back to SAME document ---------------------- */
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

  /* ----------  helper: swap AM ↔ PM  ---------- */
  static DateTime _mirrorAmPm(DateTime src) {
    final h = src.hour;
    final newH = h >= 12 ? h - 12 : h + 12;
    return DateTime(src.year, src.month, src.day, newH, src.minute);
  }
}

/* ----------  helper  ---------- */
class _BlockedSlot {
  final DateTime start;
  final DateTime end;
  _BlockedSlot({required this.start, required this.end});
}