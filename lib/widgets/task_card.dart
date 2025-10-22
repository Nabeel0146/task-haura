/* =========================================================================
   TASK CARD  –  DYNAMIC HEIGHT + BOTTOM ACTION BAR + CHECKBOX
   ========================================================================= */
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:taskhaura/models/task.dart';
import 'package:taskhaura/ai/ai_chatscreen.dart';
import 'package:taskhaura/screens/taskdetail.dart'; // Import your task detail page

class TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onCheck;

  const TaskCard({
    super.key,
    required this.task,
    required this.onEdit,
    required this.onDelete,
    required this.onCheck,
  });

  /* --------------------------------------------------------------- */
  /*  Navigate to Task Detail Page                                  */
  /* --------------------------------------------------------------- */
  void _navigateToDetail(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TaskDetailScreen(task: task),
      ),
    );
  }

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
  /*  TAG COLOR MAPPING                                              */
  /* --------------------------------------------------------------- */
  Map<String, Color> get _tagColors => const {
    'Work': Color(0xFFFFF2E6),        // Soft orange
    'Study': Color(0xFFE6F3FF),       // Soft blue
    'Freelancing': Color(0xFFF0E6FF), // Soft purple
    'Kitchen': Color(0xFFFFF0F0),     // Soft pink
    'Parenting': Color(0xFFE6FFE6),   // Soft green
    'Family': Color(0xFFFFF8E6),      // Soft peach
    'Personal': Color(0xFFE6F7FF),    // Soft light blue
  };

  Map<String, Color> get _tagTextColors => const {
    'Work': Color(0xFFCC6600),        // Dark orange
    'Study': Color(0xFF0066CC),       // Dark blue
    'Freelancing': Color(0xFF6633CC), // Dark purple
    'Kitchen': Color(0xFFCC3366),     // Dark pink
    'Parenting': Color(0xFF339933),   // Dark green
    'Family': Color(0xFFCC9900),      // Dark peach
    'Personal': Color(0xFF0099CC),    // Dark light blue
  };

  /* --------------------------------------------------------------- */
  /*  TAG CHIP WITH COLOR                                            */
  /* --------------------------------------------------------------- */
  Widget _tagChip() {
    final backgroundColor = _tagColors[task.tag] ?? Colors.grey[100]!;
    final textColor = _tagTextColors[task.tag] ?? Colors.grey[600]!;

    return Chip(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: backgroundColor,
      side: BorderSide.none,
      label: Text(
        task.tag,
        style: TextStyle(
          fontSize: 12, 
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
      ),
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

  Widget _habitIndicator() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.green[50]!,
            Colors.green[100]!,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.green[100]!.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.green[500],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.autorenew, size: 14, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Daily Habit',
                style: TextStyle(
                  fontSize: 13, 
                  color: Colors.green[800], 
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                'This task repeats regularly',
                style: TextStyle(
                  fontSize: 11, 
                  color: Colors.green[600], 
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green[500]!.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'HABIT',
              style: TextStyle(
                fontSize: 10,
                color: Colors.green[700],
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /* --------------------------------------------------------------- */
  /*  CUSTOM CHECKBOX WIDGET                                         */
  /* --------------------------------------------------------------- */
  Widget _buildCheckbox() {
    final bool isCheckable = task.status == TaskStatus.toStart || task.status == TaskStatus.onDoing;
    
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Colors.grey[400]!,
          width: 2,
        ),
      ),
      child: Theme(
        data: ThemeData(
          unselectedWidgetColor: Colors.transparent,
        ),
        child: Checkbox(
          value: task.status == TaskStatus.done,
          onChanged: isCheckable ? (value) => onCheck() : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
          side: BorderSide.none,
          checkColor: const Color(0xFF74EC7A),
          fillColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.selected)) {
              return Colors.white;
            }
            return Colors.transparent;
          }),
        ),
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
        child: InkWell(
          onTap: () => _navigateToDetail(context),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                /* ----------------------------------------------------- */
                /*  TAG CHIP WITH COLOR                                  */
                /* ----------------------------------------------------- */
                if (task.tag.isNotEmpty) ...[
                  _tagChip(),
                  const SizedBox(height: 6),
                ],

                /* ----------------------------------------------------- */
                /*  TITLE ROW WITH CHECKBOX                             */
                /* ----------------------------------------------------- */
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Checkbox with gesture detector to prevent navigation when tapping checkbox
                    GestureDetector(
                      onTap: () {
                        // Only handle checkbox tap, don't navigate to detail
                        final bool isCheckable = task.status == TaskStatus.toStart || task.status == TaskStatus.onDoing;
                        if (isCheckable) {
                          onCheck();
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12, top: 2),
                        child: _buildCheckbox(),
                      ),
                    ),
                    // Title (takes remaining space)
                    Expanded(
                      child: Text(
                        task.title,
                        maxLines: null, // allow any number of lines
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                /* ----------------------------------------------------- */
                /*  DESCRIPTION                                          */
                /* ----------------------------------------------------- */
                Padding(
                  padding: const EdgeInsets.only(left: 36), // Align with title text (checkbox width + padding)
                  child: Text(
                    task.desc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                ),
                const SizedBox(height: 10),

                /* ----------------------------------------------------- */
                /*  BOTTOM BAR :  due-date + actions                     */
                /* ----------------------------------------------------- */
                Padding(
                  padding: const EdgeInsets.only(left: 36), // Align with title text
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      /* due date & duration */
                      Icon(Icons.calendar_today, size: 11, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(DateFormat('MMM d').format(task.deadline ?? DateTime.now())),
                      const SizedBox(width: 12),
                      
                      /* duration */
                      Icon(Icons.schedule, size: 11, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text('${task.durationMin}m'),
                      const SizedBox(width: 12),

                      /* priority chip */
                      _priorityChip(),
                      const SizedBox(width: 8),

                      /* action buttons */
                      Row(
                        children: [
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
                      )
                    ],
                  ),
                ),

                /* ----------------------------------------------------- */
                /*  HABIT INDICATOR - FULL WIDTH AT BOTTOM              */
                /* ----------------------------------------------------- */
                if (task.repeatingTask) ...[
                  const SizedBox(height: 10),
                  _habitIndicator(),
                ],
              ],
            ),
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