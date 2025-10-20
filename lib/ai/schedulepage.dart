import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskhaura/models/task.dart';
import 'package:taskhaura/services/aischeduler.dart';
import '../main.dart'; // for gemini instance

class AiSchedulePage extends StatefulWidget {
  final Task task;
  final List<Task> userTasks;
  final String? userWorkingHours;
  final String? userTags;

  const AiSchedulePage({
    super.key,
    required this.task,
    this.userTasks = const [],
    this.userWorkingHours,
    this.userTags,
  });

  @override
  State<AiSchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<AiSchedulePage> {
  final List<Map<String, dynamic>> _history = [];
  bool _thinking = false;
  String? _userId;

  /* ---------- life-cycle ---------- */
  @override
  void initState() {
    super.initState();
    _loadUserId();
    _addWelcome();
    _scheduleSingleTask();
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userId = prefs.getString('userId');
    });
  }

  void _addWelcome() {
    _history.add({
      'role': 'assistant',
      'text': 'Let\'s find the best schedule for your task!',
    });
  }

  /* ---------- task display ---------- */
  Widget _buildTaskHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _getPriorityIcon(widget.task.priority),
                color: _getPriorityColor(widget.task.priority),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.task.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (widget.task.desc.isNotEmpty) ...[
            Text(
              widget.task.desc,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              _buildTaskDetail(Icons.access_time, '${widget.task.durationMin} min'),
              const SizedBox(width: 16),
              _buildTaskDetail(Icons.flag, widget.task.priority.name),
              const SizedBox(width: 16),
              _buildTaskDetail(Icons.calendar_today, 
                DateFormat('MMM d').format(widget.task.deadline ?? DateTime.now())),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTaskDetail(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  // Helper methods for priority icons and colors
  IconData _getPriorityIcon(Priority priority) {
    switch (priority) {
      case Priority.high:
        return Icons.flag;
      case Priority.medium:
        return Icons.flag_outlined;
      case Priority.low:
        return Icons.outlined_flag;
    }
  }

  Color _getPriorityColor(Priority priority) {
    switch (priority) {
      case Priority.high:
        return Colors.red;
      case Priority.medium:
        return Colors.orange;
      case Priority.low:
        return Colors.green;
    }
  }

  /* ---------- ask backend ---------- */
  Future<void> _scheduleSingleTask() async {
    setState(() => _thinking = true);
    
    // Use the default AiScheduler prompt
    final raw = await AiScheduler.chatSchedule(widget.task);
    final reply = _to12(raw);
    _handleSlotReply(reply);
  }

  /* ---------- 12-hour helper ---------- */
  String _to12(String txt) {
    final reg24 = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?\b');
    return txt.replaceAllMapped(reg24, (m) {
      int h = int.parse(m.group(1)!);
      final min = m.group(2)!;
      final am = h < 12 ? 'AM' : 'PM';
      h = h > 12 ? h - 12 : (h == 0 ? 12 : h);
      return '$h:$min $am';
    });
  }

  /* ---------- parse & show ---------- */
  Map<String, DateTime>? _parseSlot(String raw) {
    final m = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)\s*[-–—]\s*(\d{1,2}):(\d{2})\s*(AM|PM)')
        .firstMatch(raw);
    if (m == null) return null;

    final now = DateTime.now();
    int sh = int.parse(m.group(1)!);
    int eh = int.parse(m.group(4)!);
    final smin = int.parse(m.group(2)!);
    final emin = int.parse(m.group(5)!);
    final sam = m.group(3)!;
    final eam = m.group(6)!;

    if (sam == 'PM' && sh != 12) sh += 12;
    if (sam == 'AM' && sh == 12) sh = 0;
    if (eam == 'PM' && eh != 12) eh += 12;
    if (eam == 'AM' && eh == 12) eh = 0;

    final start = DateTime(now.year, now.month, now.day, sh, smin);
    final end = DateTime(now.year, now.month, now.day, eh, emin);
    return {'start': start, 'end': end};
  }

  void _handleSlotReply(String reply) {
    final slot = _parseSlot(reply);
    if (slot != null) {
      setState(() {
        _history.add({'role': 'schedule', 'data': slot, 'text': reply});
        _thinking = false;
      });
    } else {
      _addBubble('assistant', reply);
      setState(() => _thinking = false);
    }
  }

  void _addBubble(String role, String txt) {
    if (txt.isEmpty) return;
    setState(() => _history.add({'role': role, 'text': txt}));
  }

  /* ---------- confirm ---------- */
  Future<void> _confirmSlot(Map<String, DateTime> slot) async {
    // Ensure userId is loaded before proceeding
    if (_userId == null) {
      await _loadUserId();
    }
    
    if (_userId != null) {
      await AiScheduler.insertSingleSlot(
        widget.task,
        slot['start']!,
        slot['end']!,
        userId: _userId!,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task scheduled successfully! ✅')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: User not found')),
      );
    }
  }

  /* ---------- UI ---------- */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Schedule Task'),
        backgroundColor: const Color(0xFF74EC7A),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Task Header
            _buildTaskHeader(),
            
            // AI Assistant Message
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: const Text(
                'Finding the best time slot for your task...',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            
            // Chat History
            Expanded(
              child: _historyList(),
            ),
            
            // Loading Indicator
            if (_thinking) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _historyList() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: _history.map((item) {
        if (item['role'] == 'schedule') return _slotCard(item);
        return _bubble(item['role'], item['text']);
      }).toList(),
    );
  }

  Widget _bubble(String role, String text) {
    final isMe = role == 'user';
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF74EC7A) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isMe ? Colors.white : Colors.black87,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _slotCard(Map<String, dynamic> item) {
    final slot = item['data'] as Map<String, DateTime>;
    final text = item['text'] as String;
    final fmt = DateFormat('hh:mm a');
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF74EC7A), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recommended Time Slot:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Color(0xFF74EC7A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.access_time, size: 18, color: Colors.grey[600]),
              const SizedBox(width: 6),
              Text(
                '${fmt.format(slot['start']!)} – ${fmt.format(slot['end']!)}',
                style: const TextStyle(fontSize: 14),
              ),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.check_circle, size: 18),
                label: const Text('CONFIRM'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF74EC7A),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _confirmSlot(slot),
              ),
            ],
          ),
        ],
      ),
    );
  }
}