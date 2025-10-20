import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:taskhaura/main.dart';
import 'package:taskhaura/models/task.dart';
import 'package:taskhaura/services/aischeduler.dart';

/// Bottom-sheet AI assistant.
/// - If [task] is given → schedule only that task.
/// - If [task] is null → general chat (no pre-filled prompt).
class AiChatSheet extends StatefulWidget {
  final Task? task;
  final List<Task> userTasks;

  const AiChatSheet({super.key, this.task, this.userTasks = const []});

  @override
  State<AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends State<AiChatSheet> {
  final TextEditingController _controller = TextEditingController();

  /* history :  bubble  OR  schedule-block  */
  final List<Map<String, dynamic>> _history = [];
  bool _thinking = false;

  @override
  void initState() {
    super.initState();
    _addWelcome();
    if (widget.task != null) _scheduleSingleTask(); // slot mode
  }

  /* ---------------------------------------------------------- */
  /*  welcome bubble                                            */
  /* ---------------------------------------------------------- */
  void _addWelcome() {
    _history.add({
      'role': 'assistant',
      'text': widget.task == null
          ? 'Hi 👋  Ask me anything about your day!'
          : 'I\'ll find the best slot for "${widget.task!.title}" (${widget.task!.durationMin} min).',
    });
  }

  /* ---------------------------------------------------------- */
  /*  12-hour helper  –  converts 24 h only                     */
  /* ---------------------------------------------------------- */
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

  /* ---------------------------------------------------------- */
  /*  SINGLE-TASK MODE  –  ask for a slot                       */
  /* ---------------------------------------------------------- */
  Future<void> _scheduleSingleTask() async {
    setState(() => _thinking = true);
    final raw = await AiScheduler.chatSchedule(widget.task!);
    final reply = _to12(raw);
    _handleSlotReply(reply);
  }

  /* ---------------------------------------------------------- */
  /*  GENERAL CHAT  –  plain conversation, no slot              */
  /* ---------------------------------------------------------- */
  Future<void> _sendChatMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _addBubble('user', text);
    _controller.clear();
    setState(() => _thinking = true);

    final buffer = StringBuffer()
      ..writeln('You are a helpful daily-planner assistant.')
      ..writeln('Reply in one short sentence. Do not suggest a time slot.')
      ..writeln('')
      ..writeln('User: $text');

    final resp = await gemini.generateContent([Content.text(buffer.toString())]);
    final reply = _to12(resp.text?.trim() ?? 'Sorry, I didn’t understand.');
    _addBubble('assistant', reply);
    setState(() => _thinking = false);
  }

  /* ---------------------------------------------------------- */
  /*  quick chip tapped (general chat)                          */
  /* ---------------------------------------------------------- */
  void _handleChip(Task t) {
    _controller.text = 'Tell me about "${t.title}".';
    _sendChatMessage();
  }

  /* ---------------------------------------------------------- */
  /*  helper – add simple bubble                                */
  /* ---------------------------------------------------------- */
  void _addBubble(String role, String txt) {
    if (txt.isEmpty) return;
    setState(() => _history.add({'role': role, 'text': txt}));
  }

  /* ---------------------------------------------------------- */
  /*  try to parse  “2:30 PM – 3:15 PM”   (single-task only)    */
  /* ---------------------------------------------------------- */
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
    final end   = DateTime(now.year, now.month, now.day, eh, emin);
    return {'start': start, 'end': end};
  }

  /* ---------------------------------------------------------- */
  /*  handle reply in single-task mode                          */
  /* ---------------------------------------------------------- */
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

  /* ---------------------------------------------------------- */
  /*  user taps CONFIRM on schedule card                        */
  /* ---------------------------------------------------------- */
/* ---------------------------------------------------------- */
/*  user taps CONFIRM on schedule card                        */
/* ---------------------------------------------------------- */
Future<void> _confirmSlot(Map<String, DateTime> slot) async {
  if (widget.task == null) return;

  await AiScheduler.insertSingleSlot(
    widget.task!,
    slot['start']! as String, // DateTime
    slot['end']!,   // DateTime
  );

  if (!mounted) return;
  Navigator.pop(context);
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Task scheduled ✅')),
  );
}

  /* ========================================================== */
  /*  UI                                                        */
  /* ========================================================== */
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          /* header */
          ListTile(
            leading: const Icon(Icons.smart_toy, color: Color(0xFF74EC7A)),
            title: Text(widget.task == null ? 'AI Assistant' : 'Schedule Task'),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: Navigator.of(context).pop,
            ),
          ),
          const Divider(),

          /* quick chips (general chat only) */
          if (widget.task == null && widget.userTasks.isNotEmpty) ...[
            SizedBox(
              height: 60,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: widget.userTasks
                    .map((t) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            label: Text(t.title,
                                style: const TextStyle(
                                    color: Colors.black87, fontSize: 12)),
                            backgroundColor: Colors.white,
                            onPressed: () => _handleChip(t),
                          ),
                        ))
                    .toList(),
              ),
            ),
            const Divider(),
          ],

          /* history list (bubbles OR schedule card) */
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: _history.map((item) {
                if (item['role'] == 'schedule') return _slotCard(item);
                return _bubble(item['role'], item['text']);
              }).toList(),
            ),
          ),

          if (_thinking) const LinearProgressIndicator(),

          /* input bar */
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Ask or tap a task…',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      onSubmitted: (_) => widget.task == null
                          ? _sendChatMessage()
                          : _scheduleSingleTask(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton(
                    mini: true,
                    backgroundColor: const Color(0xFF74EC7A),
                    onPressed: widget.task == null
                        ? _sendChatMessage
                        : () {}, // single-task mode is automatic
                    child: const Icon(Icons.send, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /* ---------------------------------------------------------- */
  /*  chat bubble                                               */
  /* ---------------------------------------------------------- */
  Widget _bubble(String role, String text) {
    final isMe = role == 'user';
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF74EC7A) : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(text,
            style: TextStyle(color: isMe ? Colors.white : Colors.black87)),
      ),
    );
  }

  /* ---------------------------------------------------------- */
  /*  schedule card  (single-task mode only)                    */
  /* ---------------------------------------------------------- */
  Widget _slotCard(Map<String, dynamic> item) {
    final slot = item['data'] as Map<String, DateTime>;
    final text = item['text'] as String;
    final fmt = DateFormat('hh:mm a');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF74EC7A), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text('${fmt.format(slot['start']!)} – ${fmt.format(slot['end']!)}'),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('CONFIRM'),
                onPressed: () => _confirmSlot(slot),
              ),
            ],
          ),
        ],
      ),
    );
  }
}