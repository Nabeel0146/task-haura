import 'package:flutter/material.dart';
import 'package:taskhaura/ai/chatpage.dart';
import 'package:taskhaura/ai/schedulepage.dart';
import 'package:taskhaura/models/task.dart';



/// Entry bottom-sheet.
/// If a concrete [task] is supplied we open the scheduling flow,
/// otherwise the free-form chat flow.
class AiChatSheet extends StatelessWidget {
  final Task? task;
  final List<Task> userTasks;

  const AiChatSheet({super.key, this.task, this.userTasks = const []});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: task == null
          ? ChatPage(userTasks: userTasks)
          : AiSchedulePage(task: task!, userTasks: userTasks),
    );
  }
}