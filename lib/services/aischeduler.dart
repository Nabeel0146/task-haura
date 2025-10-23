import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:intl/intl.dart';
import 'package:taskhaura/main.dart';
import 'package:taskhaura/models/task.dart';

class AiScheduler {
  /* ----------------------------------------------------------
   * 1. Get user preferences, tags, and interests from Firestore
   * ---------------------------------------------------------- */
  static Future<Map<String, dynamic>?> _getUserData(String uid) async {
    try {
      print('🔍 Fetching user data for UID: $uid');
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(); //d
      
      if (userDoc.exists) {
        final data = userDoc.data();
        print('✅ User data found:');
        print('   - Preferences: ${data?['preferences']}');
        print('   - Tags: ${data?['tag']}');
        print('   - Interests: ${data?['interests']}');
        return {
          'preferences': data?['preferences'] as Map<String, dynamic>?,
          'tag': data?['tag'] as List<dynamic>?,
          'interests': data?['interests'] as List<dynamic>?,
        };
      } else {
        print('❌ User document does not exist for UID: $uid');
      }
    } catch (e) {
      print('❌ Error fetching user data: $e');
    }
    return null;
  }

 /* ----------------------------------------------------------
 * 2. Get task tags from Firestore
 * ---------------------------------------------------------- */
static Future<List<String>?> _getTaskTags(String taskId, String uid) async {
  try {
    print('🔍 Fetching task tags for task ID: $taskId');
    final taskDoc = await FirebaseFirestore.instance
        .collection('tasks')
        .doc(taskId)
        .get();
    
    if (taskDoc.exists) {
      final data = taskDoc.data();
      print('📋 Task document data: $data');
      
      // Check for the tag field (singular)
      final tag = data?['tag'];
      
      if (tag != null) {
        List<String> tagList = [];
        
        // Handle different tag data structures
        if (tag is List) {
          // It's a list of tags
          tagList = tag.map((t) => t.toString().toLowerCase().trim()).toList();
        } else if (tag is String) {
          // It's a single string tag
          tagList = [tag.toLowerCase().trim()];
        }
        
        // Filter out empty tags
        tagList = tagList.where((t) => t.isNotEmpty).toList();
        
        print('✅ Task tags found: $tagList');
        return tagList;
      } else {
        print('❌ No tag field found in task document');
        print('   Available fields: ${data?.keys.toList()}');
      }
    } else {
      print('❌ Task document does not exist for ID: $taskId');
    }
  } catch (e) {
    print('❌ Error fetching task tags: $e');
  }
  return null;
}

  /* ----------------------------------------------------------
   * 3. Parse working hours and sleep schedule
   * ---------------------------------------------------------- */
  static Map<String, String> _parseTimeRanges(Map<String, dynamic>? prefs) {
    String workingHours = '09:00-17:00'; // Default
    String sleepSchedule = '22:00-06:00'; // Default

    if (prefs != null) {
      print('🔍 Parsing time ranges from preferences: $prefs');
      
      // Parse working hours
      if (prefs['workingHours'] != null && prefs['workingHours'] != 'Flexible') {
        final wh = prefs['workingHours'].toString();
        print('   - Raw working hours: $wh');
        final match = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)\s*–\s*(\d{1,2}):(\d{2})\s*(AM|PM)').firstMatch(wh);
        if (match != null) {
          workingHours = '${_to24Hour(match.group(1)!, match.group(3)!)}-${_to24Hour(match.group(4)!, match.group(6)!)}';
          print('   - Parsed working hours: $workingHours');
        } else {
          print('   - Could not parse working hours format');
        }
      } else {
        print('   - Using default working hours: $workingHours');
      }

      // Parse sleep schedule
      if (prefs['sleepSchedule'] != null && prefs['sleepSchedule'] != 'Not set') {
        final ss = prefs['sleepSchedule'].toString();
        print('   - Raw sleep schedule: $ss');
        final match = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)\s*–\s*(\d{1,2}):(\d{2})\s*(AM|PM)').firstMatch(ss);
        if (match != null) {
          sleepSchedule = '${_to24Hour(match.group(1)!, match.group(3)!)}-${_to24Hour(match.group(4)!, match.group(6)!)}';
          print('   - Parsed sleep schedule: $sleepSchedule');
        } else {
          print('   - Could not parse sleep schedule format');
        }
      } else {
        print('   - Using default sleep schedule: $sleepSchedule');
      }
    } else {
      print('📋 Using default time ranges (no preferences)');
      print('   - Working hours: $workingHours');
      print('   - Sleep schedule: $sleepSchedule');
    }

    return {
      'workingHours': workingHours,
      'sleepSchedule': sleepSchedule,
    };
  }

  static Set<String> _getBlockedHours(List<dynamic> orderedTasks) {
  final blocked = <String>{};
  for (final task in orderedTasks) {
    final start = task['start'] as String?; // "HH:mm"
    if (start != null && start.contains(':')) {
      final hour = start.split(':').first.padLeft(2, '0');
      blocked.add(hour);
    }
  }
  return blocked;
}

  static String _to24Hour(String hour, String period) {
    int h = int.parse(hour);
    if (period == 'PM' && h != 12) h += 12;
    if (period == 'AM' && h == 12) h = 0;
    final result = '${h.toString().padLeft(2, '0')}:00';
    print('   - Converted $hour $period to $result');
    return result;
  }

  /* ----------------------------------------------------------
   * 4. Check if task is work-related using task tags and user interests
   * ---------------------------------------------------------- */
  static Future<bool> _isWorkRelatedTask(Task task) async {
    print('🔍 Checking if task is work-related:');
    print('   - Task ID: ${task.id}');
    print('   - Task Title: ${task.title}');
    print('   - Task Description: ${task.desc}');
    print('   - Task UID: ${task.uid}');
    
    try {
      // Get task tags from Firestore
      final taskTags = await _getTaskTags(task.id, task.uid);
      
      print('🔍 Work classification analysis:');
      print('   - Task tags: $taskTags');

      // Check 1: Task has EXACT "work" tag (case-insensitive)
      if (taskTags != null && taskTags.isNotEmpty) {
        for (final tag in taskTags) {
          final tagStr = tag.toString().toLowerCase().trim();
          if (tagStr == 'work') {
            print('✅ Task identified as WORK: Has exact "work" tag');
            return true;
          }
        }
        print('❌ No exact "work" tag found in task');
      } else {
        print('❌ No task tags found');
      }

      print('🎯 FINAL DECISION: Task identified as PERSONAL');
      return false;
      
    } catch (e) {
      print('❌ Error checking if task is work-related: $e');
      return false;
    }
  }

  /* ----------------------------------------------------------
   * 5. Get scheduled slots for multiple days
   * ---------------------------------------------------------- */
  static Future<Map<DateTime, List<ScheduledTask>>> _getScheduledSlots({
    required String uid,
    required DateTime startDate,
    required int daysToCheck,
  }) async {
    print('🔍 Fetching scheduled slots for $daysToCheck days starting from ${DateFormat('yyyy-MM-dd').format(startDate)}');
    
    final scheduledSlots = <DateTime, List<ScheduledTask>>{};
    
    for (int i = 0; i < daysToCheck; i++) {
      final currentDate = startDate.add(Duration(days: i));
      final dateStr = DateFormat('yyyy-MM-dd').format(currentDate);
      
      final snap = await FirebaseFirestore.instance
          .collection('schedules')
          .where('uid', isEqualTo: uid)
          .where('scheduleDate', isEqualTo: dateStr)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        final orderedTasks = data['orderedTasks'] as List<dynamic>? ?? [];
        
        final slots = orderedTasks.map((taskData) {
          final taskMap = taskData as Map<String, dynamic>;
          final startTimeStr = taskMap['start'] as String;
          final durationMin = taskMap['durationMin'] as int;
          
          // Parse the start time
          final startTime = DateFormat('HH:mm').parse(startTimeStr);
          final taskStart = DateTime(
            currentDate.year, 
            currentDate.month, 
            currentDate.day, 
            startTime.hour, 
            startTime.minute
          );
          final taskEnd = taskStart.add(Duration(minutes: durationMin));
          
          return ScheduledTask(
            start: taskStart,
            end: taskEnd,
            durationMin: durationMin,
            taskId: taskMap['id'] as String? ?? '',
          );
        }).toList();
        
        scheduledSlots[currentDate] = slots;
        print('   - ${dateStr}: ${slots.length} scheduled tasks');
        for (final slot in slots) {
          print('     - ${DateFormat('HH:mm').format(slot.start)}-${DateFormat('HH:mm').format(slot.end)} (${slot.durationMin}min)');
        }
      } else {
        scheduledSlots[currentDate] = [];
        print('   - ${dateStr}: No scheduled tasks');
      }
    }

    return scheduledSlots;
  }

  /* ----------------------------------------------------------
   * 6. Find available time slots considering existing schedule
   * ---------------------------------------------------------- */
  static List<TimeSlot> _findAvailableSlots({
    required DateTime date,
    required List<ScheduledTask> scheduledSlots,
    required int taskDuration,
    required bool isWorkTask,
    required Map<String, String> timeRanges,
  }) {
    final availableSlots = <TimeSlot>[];
    
    // Parse time ranges
    final workStart = timeRanges['workingHours']!.split('-')[0];
    final workEnd = timeRanges['workingHours']!.split('-')[1];
    final sleepStart = timeRanges['sleepSchedule']!.split('-')[0];
    final sleepEnd = timeRanges['sleepSchedule']!.split('-')[1];
    
    // Convert to DateTime objects for the current date
    final workStartTime = _parseTimeString(workStart, date);
    final workEndTime = _parseTimeString(workEnd, date);
    final sleepStartTime = _parseTimeString(sleepStart, date);
    final sleepEndTime = _parseTimeString(sleepEnd, date);
    
    // Determine scheduling window based on task type
    final DateTime schedulingStart, schedulingEnd;
    
    if (isWorkTask) {
      schedulingStart = workStartTime;
      schedulingEnd = workEndTime;
    } else {
      // Personal tasks: before work hours or after work hours
      schedulingStart = _parseTimeString('00:00', date);
      schedulingEnd = workStartTime;
      // Also consider after work hours
      final eveningStart = workEndTime;
      final eveningEnd = _parseTimeString('23:59', date);
      
      // Check morning slots
      _findSlotsInWindow(
        schedulingStart,
        schedulingEnd,
        scheduledSlots,
        taskDuration,
        availableSlots,
        sleepStartTime,
        sleepEndTime,
      );
      
      // Check evening slots
      _findSlotsInWindow(
        eveningStart,
        eveningEnd,
        scheduledSlots,
        taskDuration,
        availableSlots,
        sleepStartTime,
        sleepEndTime,
      );
      
      return availableSlots;
    }
    
    // For work tasks, only check during work hours
    _findSlotsInWindow(
      schedulingStart,
      schedulingEnd,
      scheduledSlots,
      taskDuration,
      availableSlots,
      sleepStartTime,
      sleepEndTime,
    );
    
    return availableSlots;
  }

  static void _findSlotsInWindow(
    DateTime windowStart,
    DateTime windowEnd,
    List<ScheduledTask> scheduledSlots,
    int taskDuration,
    List<TimeSlot> availableSlots,
    DateTime sleepStart,
    DateTime sleepEnd,
  ) {
    DateTime currentTime = windowStart;
    
    while (currentTime.add(Duration(minutes: taskDuration)).isBefore(windowEnd) || 
           currentTime.add(Duration(minutes: taskDuration)) == windowEnd) {
      
      final slotEnd = currentTime.add(Duration(minutes: taskDuration));
      
      // Check if this slot overlaps with any scheduled slot
      final hasTimeConflict = scheduledSlots.any((scheduled) {
        final scheduledStart = scheduled.start;
        final scheduledEnd = scheduled.end;
        
        // Check for time overlap
        final overlaps = (currentTime.isBefore(scheduledEnd) && slotEnd.isAfter(scheduledStart));
        
        if (overlaps) {
          print('   - Time conflict: ${DateFormat('HH:mm').format(currentTime)}-${DateFormat('HH:mm').format(slotEnd)} overlaps with ${DateFormat('HH:mm').format(scheduledStart)}-${DateFormat('HH:mm').format(scheduledEnd)}');
        }
        
        return overlaps;
      });
      
      // Check if this slot overlaps with sleep time
      final overlapsSleep = (currentTime.isBefore(sleepEnd) && slotEnd.isAfter(sleepStart)) ||
                           (currentTime.isAfter(sleepStart) && currentTime.isBefore(sleepEnd));
      
      if (!hasTimeConflict && !overlapsSleep) {
        availableSlots.add(TimeSlot(start: currentTime, end: slotEnd));
        print('   - ✅ Available slot: ${DateFormat('HH:mm').format(currentTime)}-${DateFormat('HH:mm').format(slotEnd)}');
      }
      
      // Move to next potential slot (15-minute increments)
      currentTime = currentTime.add(const Duration(minutes: 15));
    }
  }

  static DateTime _parseTimeString(String timeStr, DateTime date) {
    final parts = timeStr.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  /* ----------------------------------------------------------
   * 7. Chat-like prompt for single task with available slots
   * ---------------------------------------------------------- */
  static Future<String> chatSchedule(Task task, {Map<String, dynamic>? userPreferences}) async {
    final today = DateTime.now();
    
    print('🚀 STARTING SINGLE TASK SCHEDULING');
    print('📋 TASK DETAILS:');
    print('   - ID: ${task.id}');
    print('   - Title: ${task.title}');
    print('   - Duration: ${task.durationMin}min');
    print('   - Priority: ${task.priority.name}');
    
    // Get user data
    final userData = userPreferences != null ? 
        {'preferences': userPreferences} : await _getUserData(task.uid);
    final prefs = userData?['preferences'];
    final timeRanges = _parseTimeRanges(prefs);
    
    // Determine if task is work-related
    final isWorkTask = await _isWorkRelatedTask(task);
    
    // Check available slots for the next 7 days or until deadline
    final daysToCheck = _calculateDaysToCheck(today, task.deadline!);
    final scheduledSlots = await _getScheduledSlots(
      uid: task.uid,
      startDate: today,
      daysToCheck: daysToCheck,
    );
    
    // Find available slots for each day
    final availableSlotsByDay = <DateTime, List<TimeSlot>>{};
    DateTime? firstAvailableDay;
    
    for (final entry in scheduledSlots.entries) {
      final date = entry.key;
      final slots = _findAvailableSlots(
        date: date,
        scheduledSlots: entry.value,
        taskDuration: task.durationMin,
        isWorkTask: isWorkTask,
        timeRanges: timeRanges,
      );
      
      if (slots.isNotEmpty) {
        availableSlotsByDay[date] = slots;
        firstAvailableDay ??= date;
        print('✅ Available slots on ${DateFormat('EEE, MMM d').format(date)}: ${slots.length}');
      } else {
        print('❌ No available slots on ${DateFormat('EEE, MMM d').format(date)}');
      }
    }
    
    // If no slots available within deadline, return error
    if (availableSlotsByDay.isEmpty) {
      return 'SCHEDULING_ERROR: No available time slots found before the task deadline. Please consider extending the deadline or rescheduling other tasks.';
    }
    
    // Build prompt with available slots
    final prompt = _buildSchedulingPrompt(
      task: task,
      prefs: prefs,
      timeRanges: timeRanges,
      isWorkTask: isWorkTask,
      availableSlotsByDay: availableSlotsByDay,
      firstAvailableDay: firstAvailableDay!,
    );
    
    print('📤 SENDING PROMPT TO AI:');
    print('```\n$prompt\n```');

    try {
      final resp = await gemini.generateContent([Content.text(prompt)]);
      final response = resp.text?.trim() ?? 'I need more information to schedule this task.';
      print('📥 AI RESPONSE:');
      print('```\n$response\n```');
      return response;
    } catch (e) {
      print('❌ Error in chatSchedule: $e');
      return 'I encountered an error while scheduling. Please try again.';
    }
  }

  static int _calculateDaysToCheck(DateTime startDate, DateTime deadline) {
    final daysUntilDeadline = deadline.difference(startDate).inDays;
    // Check up to 7 days or until deadline, whichever is smaller
    return daysUntilDeadline < 7 ? daysUntilDeadline + 1 : 7;
  }

  static String _buildSchedulingPrompt({
    required Task task,
    required Map<String, dynamic>? prefs,
    required Map<String, String> timeRanges,
    required bool isWorkTask,
    required Map<DateTime, List<TimeSlot>> availableSlotsByDay,
    required DateTime firstAvailableDay,
  }) {
    final buffer = StringBuffer()
      ..writeln('You are an intelligent daily planner that respects user preferences and available time slots.')
      ..writeln('')
      ..writeln('USER PREFERENCES:')
      ..writeln('- Work Type: ${prefs?['workType'] ?? "Flexible"}')
      ..writeln('- Focus Style: ${prefs?['focusStyle'] ?? "Flexible"}')
      ..writeln('- Productivity Goal: ${prefs?['productivityGoal'] ?? "General productivity"}')
      ..writeln('- Working Hours: ${timeRanges['workingHours']}')
      ..writeln('- Sleep Schedule: ${timeRanges['sleepSchedule']} (NEVER schedule during sleep)')
      ..writeln('')
      ..writeln('TASK TO SCHEDULE:')
      ..writeln('- Title: ${task.title}')
      ..writeln('- Description: ${task.desc}')
      ..writeln('- Duration: ${task.durationMin} minutes')
      ..writeln('- Priority: ${task.priority.name}')
      ..writeln('- Type: ${isWorkTask ? "WORK-RELATED" : "PERSONAL"}')
      ..writeln('- Deadline: ${DateFormat('EEE, MMM d, yyyy').format(task.deadline!)}')
      ..writeln('')
      ..writeln('AVAILABLE TIME SLOTS (choose from these only):');

    availableSlotsByDay.forEach((date, slots) {
      buffer.writeln('- ${DateFormat('EEE, MMM d').format(date)}:');
      if (slots.isEmpty) {
        buffer.writeln('  No available slots');
      } else {
        for (final slot in slots.take(10)) { // Limit to first 10 slots per day
          buffer.writeln('  ${DateFormat('HH:mm').format(slot.start)}-${DateFormat('HH:mm').format(slot.end)}');
        }
        if (slots.length > 10) {
          buffer.writeln('  ... and ${slots.length - 10} more slots');
        }
      }
    });

    buffer
      ..writeln('')
      ..writeln('CRITICAL SCHEDULING RULES:')
      ..writeln('1. WORK TASKS: Schedule ONLY during working hours (${timeRanges['workingHours']})')
      ..writeln('2. PERSONAL TASKS: Schedule ONLY outside working hours')
      ..writeln('3. NEVER during sleep hours (${timeRanges['sleepSchedule']})')
      ..writeln('4. Choose ONLY from the available slots listed above')
      ..writeln('5. Prefer earlier dates to meet the deadline')
      ..writeln('6. High priority tasks should get optimal focus hours')
      ..writeln('7. Consider user focus style: ${prefs?['focusStyle'] ?? "Flexible"}')
      ..writeln('')
      ..writeln('Reply with: "How about DATE at HH:MM-HH:MM? [Brief reason based on task type and preferences]"')
      ..writeln('Example: "How about ${DateFormat('EEE, MMM d').format(firstAvailableDay)} at 14:30-15:15? Perfect work hours slot for your project task."');

    return buffer.toString();
  }

  /* ----------------------------------------------------------
   * 8. Insert single slot
   * ---------------------------------------------------------- */
  static Future<void> insertSingleSlot(
    Task task, 
    DateTime startTime, 
    DateTime endTime, 
    {required String userId}
  ) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(startTime);

    print('💾 INSERTING SCHEDULE SLOT:');
    print('   - User ID: $userId');
    print('   - Task: ${task.title}');
    print('   - Time: ${DateFormat('HH:mm').format(startTime)}-${DateFormat('HH:mm').format(endTime)}');
    print('   - Date: $dateStr');

    // Read existing schedule
    final schedSnap = await FirebaseFirestore.instance
        .collection('schedules')
        .where('uid', isEqualTo: userId)
        .where('scheduleDate', isEqualTo: dateStr)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    print('   - Existing schedules found: ${schedSnap.docs.length}');

    final List<Map<String, dynamic>> merged =
        schedSnap.docs.isEmpty ? [] : List.from(schedSnap.docs.first.data()['orderedTasks']);

    // Determine task type for the reason
    final isWorkTask = await _isWorkRelatedTask(task);
    final taskType = isWorkTask ? 'work' : 'personal';

    final newSlot = {
      'id': task.id,
      'title': task.title,
      'durationMin': task.durationMin,
      'start': DateFormat('HH:mm').format(startTime),
      'date': dateStr,
      'priority': task.priority.name,
      'reason': 'Scheduled during ${taskType} hours considering your preferences',
      'scheduled': true,
      'taskType': taskType,
    };

    merged.add(newSlot);
    print('   - Added new slot: $newSlot');

    // Sort by start time
    merged.sort((a, b) => DateFormat('HH:mm')
        .parseUtc(a['start'])
        .compareTo(DateFormat('HH:mm').parseUtc(b['start'])));

    print('   - Final merged schedule has ${merged.length} tasks');

    if (schedSnap.docs.isEmpty) {
      print('   - Creating new schedule document');
      await FirebaseFirestore.instance.collection('schedules').add({
        'uid': userId,
        'scheduleDate': dateStr,
        'orderedTasks': merged,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      print('   - Updating existing schedule document: ${schedSnap.docs.first.id}');
      await FirebaseFirestore.instance.collection('schedules').doc(schedSnap.docs.first.id).update({
        'orderedTasks': merged,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    print('✅ Schedule saved successfully');
  }

  /* ----------------------------------------------------------
   * 9. Check if task can be scheduled (for reschedule flow)
   * ---------------------------------------------------------- */
  static Future<Map<String, dynamic>> checkSchedulingAvailability(Task task) async {
    final today = DateTime.now();
    
    // Get user data
    final userData = await _getUserData(task.uid);
    final prefs = userData?['preferences'];
    final timeRanges = _parseTimeRanges(prefs);
    
    // Determine if task is work-related
    final isWorkTask = await _isWorkRelatedTask(task);
    
    // Check available slots for the next 7 days or until deadline
    final daysToCheck = _calculateDaysToCheck(today, task.deadline!);
    final scheduledSlots = await _getScheduledSlots(
      uid: task.uid,
      startDate: today,
      daysToCheck: daysToCheck,
    );
    
    // Find first available slot
    for (final entry in scheduledSlots.entries) {
      final date = entry.key;
      final slots = _findAvailableSlots(
        date: date,
        scheduledSlots: entry.value,
        taskDuration: task.durationMin,
        isWorkTask: isWorkTask,
        timeRanges: timeRanges,
      );
      
      if (slots.isNotEmpty) {
        return {
          'canSchedule': true,
          'firstAvailableDate': date,
          'availableSlots': slots,
        };
      }
    }
    
    return {
      'canSchedule': false,
      'reason': 'No available time slots found before the task deadline. Please consider extending the deadline or rescheduling other tasks.',
    };
  }
}

/* ---------- Helper classes ---------- */
class ScheduledTask {
  final DateTime start;
  final DateTime end;
  final int durationMin;
  final String taskId;
  
  ScheduledTask({
    required this.start,
    required this.end,
    required this.durationMin,
    required this.taskId,
  });
}

class TimeSlot {
  final DateTime start;
  final DateTime end;
  
  TimeSlot({required this.start, required this.end});
}