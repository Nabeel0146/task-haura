import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:taskhaura/models/task.dart';
import 'package:taskhaura/ai/ai_chatscreen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taskhaura/services/calendar_deeplink.dart';


class TaskDetailScreen extends StatefulWidget {
  final Task task;
  final VoidCallback? onTaskUpdated;

  const TaskDetailScreen({
    super.key,
    required this.task,
    this.onTaskUpdated,
  });

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  late Task _currentTask;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DeepLinkCalendarService _calendarService = DeepLinkCalendarService();
  bool _isUpdating = false;
  bool _isAddingToCalendar = false;

  @override
  void initState() {
    super.initState();
    _currentTask = widget.task;
    _checkAndUpdateOverdueStatus();
  }
/* --------------------------------------------------------------- */
/*  Add to Google Calendar Functionality                           */
/* --------------------------------------------------------------- */
Future<void> _addToGoogleCalendar() async {
  if (_isAddingToCalendar) return;
  
  setState(() {
    _isAddingToCalendar = true;
  });

  try {
    if (!await _calendarService.addTaskToCalendar(_currentTask)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open Google Calendar'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  } catch (e) {
    print('Calendar error: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Error opening Google Calendar'),
        duration: Duration(seconds: 2),
      ),
    );
  } finally {
    setState(() {
      _isAddingToCalendar = false;
    });
  }
}
  /* --------------------------------------------------------------- */
  /*  Update Task in Firebase                                        */
  /* --------------------------------------------------------------- */
  Future<void> _updateTaskInFirebase(Task updatedTask) async {
    if (_isUpdating) return;
    
    setState(() {
      _isUpdating = true;
    });

    try {
      await _firestore
          .collection('tasks')
          .doc(updatedTask.id)
          .update({'status': updatedTask.status.name});

      setState(() {
        _currentTask = updatedTask;
      });

      widget.onTaskUpdated?.call();

      _showStatusUpdateSnackbar(updatedTask.status);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update task: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      setState(() {
        _isUpdating = false;
      });
    }
  }

  /* --------------------------------------------------------------- */
  /*  Check and update overdue status automatically                  */
  /* --------------------------------------------------------------- */
  void _checkAndUpdateOverdueStatus() {
    if (_isOverdue && _currentTask.status != TaskStatus.done) {
      _updateTaskInFirebase(_currentTask.copyWith(status: TaskStatus.skipped));
    }
  }

  /* --------------------------------------------------------------- */
  /*  Status Update Logic                                            */
  /* --------------------------------------------------------------- */
  void _handleStatusUpdate() {
    if (_isUpdating) return;

    TaskStatus newStatus;
    
    switch (_currentTask.status) {
      case TaskStatus.toStart:
        newStatus = TaskStatus.onDoing;
        break;
      case TaskStatus.onDoing:
        newStatus = TaskStatus.done;
        break;
      case TaskStatus.done:
        return;
      case TaskStatus.skipped:
        newStatus = TaskStatus.toStart;
        break;
    }

    _updateTaskInFirebase(_currentTask.copyWith(status: newStatus));
  }

  /* --------------------------------------------------------------- */
  /*  Show status update snackbar                                    */
  /* --------------------------------------------------------------- */
  void _showStatusUpdateSnackbar(TaskStatus newStatus) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _getStatusUpdateMessage(newStatus),
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  String _getStatusUpdateMessage(TaskStatus status) {
    switch (status) {
      case TaskStatus.toStart:
        return 'Task restarted!';
      case TaskStatus.onDoing:
        return 'Task started! Keep going!';
      case TaskStatus.done:
        return 'Task completed! Great job! 🎉';
      case TaskStatus.skipped:
        return 'Task marked as skipped';
    }
  }

  /* --------------------------------------------------------------- */
  /*  Check if task is overdue                                       */
  /* --------------------------------------------------------------- */
  bool get _isOverdue {
    final now = DateTime.now();
    final deadline = _currentTask.deadline;
    return deadline != null && 
           deadline.isBefore(DateTime(now.year, now.month, now.day)) &&
           _currentTask.status != TaskStatus.done;
  }

  /* --------------------------------------------------------------- */
  /*  Edit Task Functionality                                        */
  /* --------------------------------------------------------------- */
  void _handleEdit() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Edit functionality coming soon!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /* --------------------------------------------------------------- */
  /*  Delete Task Functionality                                      */
  /* --------------------------------------------------------------- */
  void _handleDelete() {
    showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Task?'),
        content: const Text('This action cannot be undone.'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(true);
              _performDelete();
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _performDelete() async {
    try {
      await _firestore.collection('tasks').doc(_currentTask.id).delete();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Task deleted successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
      
      Future.delayed(const Duration(milliseconds: 500), () {
        Navigator.of(context).pop();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete task: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /* --------------------------------------------------------------- */
  /*  TAG COLOR MAPPING                                              */
  /* --------------------------------------------------------------- */
  Map<String, Color> get _tagColors => const {
    'Work': Color(0xFFFFF2E6),
    'Study': Color(0xFFE6F3FF),
    'Freelancing': Color(0xFFF0E6FF),
    'Kitchen': Color(0xFFFFF0F0),
    'Parenting': Color(0xFFE6FFE6),
    'Family': Color(0xFFFFF8E6),
    'Personal': Color(0xFFE6F7FF),
  };

  Map<String, Color> get _tagTextColors => const {
    'Work': Color(0xFFCC6600),
    'Study': Color(0xFF0066CC),
    'Freelancing': Color(0xFF6633CC),
    'Kitchen': Color(0xFFCC3366),
    'Parenting': Color(0xFF339933),
    'Family': Color(0xFFCC9900),
    'Personal': Color(0xFF0099CC),
  };

  /* --------------------------------------------------------------- */
  /*  Priority Chip                                                  */
  /* --------------------------------------------------------------- */
  Widget _priorityChip() {
    Color bg = Colors.grey;
    String text = 'Low';
    
    if (_currentTask.priority == Priority.high) {
      bg = Colors.red;
      text = 'High';
    } else if (_currentTask.priority == Priority.medium) {
      bg = Colors.orange;
      text = 'Medium';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: bg.withOpacity(.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: bg.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          color: bg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /* --------------------------------------------------------------- */
  /*  Status Chip                                                    */
  /* --------------------------------------------------------------- */
  Widget _statusChip() {
    Color bg;
    String text;
    
    switch (_currentTask.status) {
      case TaskStatus.toStart:
        bg = Colors.blue;
        text = 'To Start';
      case TaskStatus.onDoing:
        bg = Colors.orange;
        text = 'In Progress';
      case TaskStatus.done:
        bg = Colors.green;
        text = 'Completed';
      case TaskStatus.skipped:
        bg = Colors.grey;
        text = 'Skipped';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: bg.withOpacity(.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: bg.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          color: bg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /* --------------------------------------------------------------- */
  /*  Get Next Status Button Text                                    */
  /* --------------------------------------------------------------- */
  String get _nextStatusButtonText {
    switch (_currentTask.status) {
      case TaskStatus.toStart:
        return 'Start Task';
      case TaskStatus.onDoing:
        return 'Mark as Completed';
      case TaskStatus.done:
        return 'Task Completed';
      case TaskStatus.skipped:
        return 'Restart Task';
    }
  }

  /* --------------------------------------------------------------- */
  /*  Check if status can be updated                                 */
  /* --------------------------------------------------------------- */
  bool get _canUpdateStatus {
    return _currentTask.status != TaskStatus.done && !_isUpdating;
  }

  /* --------------------------------------------------------------- */
  /*  Get appropriate icon for status button                         */
  /* --------------------------------------------------------------- */
  IconData get _statusButtonIcon {
    switch (_currentTask.status) {
      case TaskStatus.toStart:
        return Icons.play_arrow;
      case TaskStatus.onDoing:
        return Icons.check_circle;
      case TaskStatus.done:
        return Icons.done_all;
      case TaskStatus.skipped:
        return Icons.replay;
    }
  }

  /* --------------------------------------------------------------- */
  /*  Get button color based on status                               */
  /* --------------------------------------------------------------- */
  Color get _statusButtonColor {
    if (_isUpdating) return Colors.grey;
    
    switch (_currentTask.status) {
      case TaskStatus.toStart:
        return const Color(0xFF74EC7A);
      case TaskStatus.onDoing:
        return const Color(0xFF74EC7A);
      case TaskStatus.done:
        return Colors.grey;
      case TaskStatus.skipped:
        return Colors.orange;
    }
  }

  /* --------------------------------------------------------------- */
  /*  Open AI Assistant                                              */
  /* --------------------------------------------------------------- */
  void _openAiChat() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AiChatSheet(task: _currentTask),
    );
  }

  /* --------------------------------------------------------------- */
  /*  Info Card Widget                                               */
  /* --------------------------------------------------------------- */
  Widget _infoCard(IconData icon, String title, String value, {Color? iconColor}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (iconColor ?? Colors.blue).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: iconColor ?? Colors.blue[700]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /* --------------------------------------------------------------- */
  /*  Overdue Warning Widget                                         */
  /* --------------------------------------------------------------- */
  Widget _buildOverdueWarning() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: Colors.red[700], size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Overdue Task',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.red[800],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This task was due on ${DateFormat('MMM d, yyyy').format(_currentTask.deadline!)}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.red[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Task Details',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          if (_isUpdating)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.edit, size: 22),
            onPressed: _isUpdating ? null : _handleEdit,
            tooltip: 'Edit Task',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /* ----------------------------------------------------- */
            /*  OVERDUE WARNING (if applicable)                     */
            /* ----------------------------------------------------- */
            if (_isOverdue) ...[
              _buildOverdueWarning(),
              const SizedBox(height: 16),
            ],

            /* ----------------------------------------------------- */
            /*  HEADER SECTION                                       */
            /* ----------------------------------------------------- */
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.blue[50]!,
                    Colors.purple[50]!,
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tag and Priority
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _tagColors[_currentTask.tag] ?? Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _currentTask.tag,
                          style: TextStyle(
                            fontSize: 12,
                            color: _tagTextColors[_currentTask.tag] ?? Colors.grey[600],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      _priorityChip(),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Title
                  Text(
                    _currentTask.title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Description
                  Text(
                    _currentTask.desc,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[700],
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            /* ----------------------------------------------------- */
            /*  STATUS UPDATE BUTTON                                 */
            /* ----------------------------------------------------- */
            if (_canUpdateStatus)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isUpdating ? null : _handleStatusUpdate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _statusButtonColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: _isUpdating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_statusButtonIcon, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              _nextStatusButtonText,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
              ),

            if (_canUpdateStatus) const SizedBox(height: 20),

            /* ----------------------------------------------------- */
            /*  TASK INFORMATION CARDS                               */
            /* ----------------------------------------------------- */
            const Text(
              'Task Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),

            Column(
              children: [
                _infoCard(
                  Icons.calendar_today,
                  'Deadline',
                  DateFormat('MMM d, yyyy - h:mm a').format(_currentTask.deadline ?? DateTime.now()),
                  iconColor: _isOverdue ? Colors.red : Colors.blue,
                ),
                const SizedBox(height: 12),
                _infoCard(
                  Icons.schedule,
                  'Duration',
                  '${_currentTask.durationMin} minutes',
                  iconColor: Colors.orange,
                ),
                const SizedBox(height: 12),
                _infoCard(
                  Icons.autorenew,
                  'Repeat',
                  _currentTask.repeatingTask ? 'Daily Habit' : 'One-time Task',
                  iconColor: Colors.green,
                ),
              ],
            ),

            const SizedBox(height: 24),

            /* ----------------------------------------------------- */
            /*  STATUS & ACTIONS SECTION                             */
            /* ----------------------------------------------------- */
            const Text(
              'Status & Actions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),

            // Status Display
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                children: [
                  const Text(
                    'Current Status',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _statusChip(),
                ],
              ),
            ),

            const SizedBox(height: 20),

            /* ----------------------------------------------------- */
            /*  ACTION BUTTONS - UPDATED WITH CALENDAR              */
            /* ----------------------------------------------------- */
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.smart_toy,
                    label: 'AI Schedule',
                    color: const Color(0xFF74EC7A),
                    onTap: _isUpdating ? null : _openAiChat,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.calendar_today,
                    label: _isAddingToCalendar ? 'Adding...' : 'Add to Calendar',
                    color: Colors.purple,
                    onTap: _isUpdating || _isAddingToCalendar ? null : _addToGoogleCalendar,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.edit,
                    label: 'Edit',
                    color: Colors.blue,
                    onTap: _isUpdating ? null : _handleEdit,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.delete,
                    label: 'Delete',
                    color: Colors.red,
                    onTap: _isUpdating ? null : _handleDelete,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            /* ----------------------------------------------------- */
            /*  HABIT INDICATOR (if repeating task)                  */
            /* ----------------------------------------------------- */
            if (_currentTask.repeatingTask)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
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
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green[500],
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.autorenew, size: 20, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Daily Habit',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.green[800],
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'This task repeats regularly every day',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/* ----------------------------------------------------------------- */
/*  ACTION BUTTON COMPONENT                                          */
/* ----------------------------------------------------------------- */
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 24, color: color.withOpacity(onTap == null ? 0.3 : 1.0)),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color.withOpacity(onTap == null ? 0.3 : 1.0),
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}