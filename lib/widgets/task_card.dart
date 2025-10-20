/* =========================================================================
   TASK CARD  –  DYNAMIC HEIGHT + BOTTOM ACTION BAR
   ========================================================================= */
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:taskhaura/models/task.dart';
import 'package:taskhaura/screens/ai_chatscreen.dart';

class TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const TaskCard({
    super.key,
    required this.task,
    required this.onEdit,
    required this.onDelete,
  });

  /* --------------------------------------------------------------- */
  /*  open AI assistant for this task                                */
  /* --------------------------------------------------------------- */
  void _openAiChat(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AiChatSheet(task: task),
    );
  }

  /* --------------------------------------------------------------- */
  /*  priority colour chip                                           */
  /* --------------------------------------------------------------- */
  Widget _priorityChip() {
    Color bg = Colors.grey;
    if (task.priority == Priority.high) bg = Colors.red;
    if (task.priority == Priority.medium) bg = Colors.orange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg.withOpacity(.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        task.priority.name.toUpperCase(),
        style: TextStyle(fontSize: 11, color: bg, fontWeight: FontWeight.w600),
      ),
    );
  }

  /* --------------------------------------------------------------- */
  /*  delete confirmation                                            */
  /* --------------------------------------------------------------- */
  void _confirmDelete(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete task?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: Navigator.of(context).pop, child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(true);
              onDelete();
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /* =============================================================== */
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withOpacity(.95),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              /* ----------------------------------------------------- */
              /*  TAG CHIP                                             */
              /* ----------------------------------------------------- */
              if (task.tag.isNotEmpty) ...[
                Chip(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: Colors.white,
                  label: Text(
                    task.tag,
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ),
                const SizedBox(height: 6),
              ],

              /* ----------------------------------------------------- */
              /*  TITLE  (unconstrained height)                        */
              /* ----------------------------------------------------- */
              Text(
                task.title,
                maxLines: null, // allow any number of lines
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 6),

              /* ----------------------------------------------------- */
              /*  DESCRIPTION                                          */
              /* ----------------------------------------------------- */
              Text(
                task.desc,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              const SizedBox(height: 10),

              /* ----------------------------------------------------- */
              /*  BOTTOM BAR :  due-date + actions                     */
              /* ----------------------------------------------------- */
              Row(
                children: [
                  /* due date & duration */
                  Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(DateFormat('MMM d').format(task.deadline ?? DateTime.now())),
                  const SizedBox(width: 12),
                  Icon(Icons.schedule, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text('${task.durationMin} min'),
                  const Spacer(),

                  /* priority chip */
                  _priorityChip(),
                  const SizedBox(width: 8),

                  /* action buttons */
                  _IconBtn(
                    icon: Icons.smart_toy,
                    color: const Color(0xFF74EC7A),
                    onTap: () => _openAiChat(context),
                  ),
                  const SizedBox(width: 4),
                  _IconBtn(icon: Icons.edit_outlined, onTap: onEdit),
                  const SizedBox(width: 4),
                  _IconBtn(
                    icon: Icons.delete_outline,
                    color: Colors.red,
                    onTap: () => _confirmDelete(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ----------------------------------------------------------------- */
/*  tiny reusable icon button                                        */
/* ----------------------------------------------------------------- */
class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final VoidCallback onTap;

  const _IconBtn({required this.icon, this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}