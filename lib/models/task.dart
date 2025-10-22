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
  final bool          repeatingTask;      // ← NEW FIELD

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
    this.repeatingTask = false,           // ← NEW FIELD with default value
  });

  /* ----------------------------------------------------------------- */
  /*  CopyWith Method                                                  */
  /* ----------------------------------------------------------------- */
  Task copyWith({
    String? id,
    String? title,
    String? desc,
    int? durationMin,
    DateTime? deadline,
    Priority? priority,
    String? uid,
    TaskStatus? status,
    String? tag,
    DateTime? createdAt,
    bool? repeatingTask,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      desc: desc ?? this.desc,
      durationMin: durationMin ?? this.durationMin,
      deadline: deadline ?? this.deadline,
      priority: priority ?? this.priority,
      uid: uid ?? this.uid,
      status: status ?? this.status,
      tag: tag ?? this.tag,
      createdAt: createdAt ?? this.createdAt,
      repeatingTask: repeatingTask ?? this.repeatingTask,
    );
  }

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
      repeatingTask: data['repeatingTask'] ?? false,  // ← NEW FIELD
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
      'createdAt':  FieldValue.serverTimestamp(),
      'repeatingTask': repeatingTask,  // ← NEW FIELD
    };
  }
}