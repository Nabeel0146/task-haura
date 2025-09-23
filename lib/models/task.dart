import 'package:cloud_firestore/cloud_firestore.dart';

enum Priority { low, medium, high }

class Task {
  final String title;
  final String desc;
  final int durationMin;
  final DateTime deadline;
  final Priority priority;
  final String uid; // ← NEW

  Task({
    required this.title,
    required this.desc,
    required this.durationMin,
    required this.deadline,
    required this.priority,
    required this.uid, // ← NEW
  });

factory Task.fromJson(Map<String, dynamic> json) => Task(
      title: json['title'],
      desc: json['desc'],
      durationMin: json['durationMin'],
      deadline: (json['deadline'] as Timestamp).toDate(),
      priority: Priority.values.byName(json['priority']),
      uid: json['uid'] ?? '', // ← HANDLE MISSING FIELD
    );

  Map<String, dynamic> toJson() => {
        'title': title,
        'desc': desc,
        'durationMin': durationMin,
        'deadline': Timestamp.fromDate(deadline),
        'priority': priority.name,
        'uid': uid, // ← NEW
      };
}