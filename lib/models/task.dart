import 'package:cloud_firestore/cloud_firestore.dart';

enum Priority { low, medium, high }
enum TaskStatus { toStart, onDoing, done, skipped }

class Task {
  final String        id;
  final String        title;
  final String        desc;
  final int           durationMin;
  final DateTime?     deadline;
  final Priority      priority;
  final String        uid;
  final TaskStatus    status;
  final String        tag;
  final DateTime?     createdAt;          // ← creation time

  const Task({
    this.id          = '',
    required this.title,
    required this.desc,
    required this.durationMin,
    required this.deadline,
    required this.priority,
    required this.uid,
    this.status      = TaskStatus.toStart,
    this.tag         = '',
    this.createdAt,
  });

  /* ----------------------------------------------------------------- */
  /*  Firestore → Dart                                                 */
  /* ----------------------------------------------------------------- */
  factory Task.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Task(
      id:          doc.id,
      title:       data['title']   ?? '',
      desc:        data['desc']    ?? '',
      durationMin: data['durationMin'] ?? 0,
      deadline:    (data['deadline']  as Timestamp?)?.toDate(),
      priority:    Priority.values.byName(data['priority'] ?? 'medium'),
      uid:         data['uid']     ?? '',
      status:      TaskStatus.values.byName(data['status'] ?? 'toStart'),
      tag:         data['tag']     ?? '',
      createdAt:   (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  /* ----------------------------------------------------------------- */
  /*  Dart → Firestore                                                 */
  /* ----------------------------------------------------------------- */
  Map<String, dynamic> toJson() {
    return {
      'title':      title,
      'desc':       desc,
      'durationMin': durationMin,
      'deadline':   deadline == null ? null : Timestamp.fromDate(deadline!),
      'priority':   priority.name,
      'uid':        uid,
      'status':     status.name,
      'tag':        tag,
      'createdAt':  FieldValue.serverTimestamp(),   // ← server time
    };
  }
}