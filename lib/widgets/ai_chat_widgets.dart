import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/* ----------------  HEADER  ---------------- */
Widget aiHeader(BuildContext ctx, {required bool isSlotMode, VoidCallback? onClose}) =>
    Column(children: [
      ListTile(
        leading: const Icon(Icons.smart_toy, color: Color(0xFF74EC7A)),
        title: Text(isSlotMode ? 'Schedule Task' : 'AI Assistant'),
        trailing:
            IconButton(icon: const Icon(Icons.close), onPressed: onClose ?? () => Navigator.pop(ctx)),
      ),
      const Divider(),
    ]);

/* ----------------  QUICK CHIPS  ---------------- */
Widget quickChips(List<dynamic> tasks, void Function(dynamic) onTap) => Column(children: [
      SizedBox(
        height: 60,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: tasks
              .map((t) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text(t.title,
                          style: const TextStyle(color: Colors.black87, fontSize: 12)),
                      backgroundColor: Colors.white,
                      onPressed: () => onTap(t),
                    ),
                  ))
              .toList(),
        ),
      ),
      const Divider(),
    ]);

/* ----------------  BUBBLE  ---------------- */
Widget chatBubble(String role, String text) {
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

/* ----------------  SLOT CARD  ---------------- */
Widget slotCard(Map<String, dynamic> item, VoidCallback onConfirm) {
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
              onPressed: onConfirm,
            ),
          ],
        ),
      ],
    ),
  );
}

/* ----------------  INPUT BAR  ---------------- */
Widget inputBar(
  TextEditingController controller,
  bool isSlotMode,
  VoidCallback onSend,
  VoidCallback onSubmit,
) {
  return SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Ask or tap a task…',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              onSubmitted: (_) => onSubmit(),
            ),
          ),
          const SizedBox(width: 8),
          FloatingActionButton(
            mini: true,
            backgroundColor: const Color(0xFF74EC7A),
            onPressed: isSlotMode ? () {} : onSend,
            child: const Icon(Icons.send, color: Colors.white),
          ),
        ],
      ),
    ),
  );
}