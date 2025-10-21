import 'dart:convert';
import 'dart:developer' as dev;
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
      dev.log('🔍 Fetching user data for UID: $uid', name: 'AiScheduler');
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      
      if (userDoc.exists) {
        final data = userDoc.data();
        dev.log('✅ User data found:', name: 'AiScheduler');
        dev.log('   - Preferences: ${data?['preferences']}', name: 'AiScheduler');
        dev.log('   - Tags: ${data?['tags']}', name: 'AiScheduler');
        dev.log('   - Interests: ${data?['interests']}', name: 'AiScheduler');
        return {
          'preferences': data?['preferences'] as Map<String, dynamic>?,
          'tags': data?['tags'] as List<dynamic>?,
          'interests': data?['interests'] as List<dynamic>?,
        };
      } else {
        dev.log('❌ User document does not exist for UID: $uid', name: 'AiScheduler');
      }
    } catch (e) {
      dev.log('❌ Error fetching user data: $e', name: 'AiScheduler');
    }
    return null;
  }

  /* ----------------------------------------------------------
   * 2. Get task tags from Firestore
   * ---------------------------------------------------------- */
  static Future<List<String>?> _getTaskTags(String taskId, String uid) async {
    try {
      dev.log('🔍 Fetching task tags for task ID: $taskId', name: 'AiScheduler');
      final taskDoc = await FirebaseFirestore.instance
          .collection('tasks')
          .doc(taskId)
          .get();
      
      if (taskDoc.exists) {
        final data = taskDoc.data();
        final tags = data?['tags'] as List<dynamic>?;
        final tagList = tags?.map((tag) => tag.toString().toLowerCase()).toList();
        dev.log('✅ Task tags found: $tagList', name: 'AiScheduler');
        return tagList;
      } else {
        dev.log('❌ Task document does not exist for ID: $taskId', name: 'AiScheduler');
      }
    } catch (e) {
      dev.log('❌ Error fetching task tags: $e', name: 'AiScheduler');
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
      dev.log('🔍 Parsing time ranges from preferences: $prefs', name: 'AiScheduler');
      
      // Parse working hours
      if (prefs['workingHours'] != null && prefs['workingHours'] != 'Flexible') {
        final wh = prefs['workingHours'].toString();
        dev.log('   - Raw working hours: $wh', name: 'AiScheduler');
        final match = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)\s*–\s*(\d{1,2}):(\d{2})\s*(AM|PM)').firstMatch(wh);
        if (match != null) {
          workingHours = '${_to24Hour(match.group(1)!, match.group(3)!)}-${_to24Hour(match.group(4)!, match.group(6)!)}';
          dev.log('   - Parsed working hours: $workingHours', name: 'AiScheduler');
        } else {
          dev.log('   - Could not parse working hours format', name: 'AiScheduler');
        }
      } else {
        dev.log('   - Using default working hours: $workingHours', name: 'AiScheduler');
      }

      // Parse sleep schedule
      if (prefs['sleepSchedule'] != null && prefs['sleepSchedule'] != 'Not set') {
        final ss = prefs['sleepSchedule'].toString();
        dev.log('   - Raw sleep schedule: $ss', name: 'AiScheduler');
        final match = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)\s*–\s*(\d{1,2}):(\d{2})\s*(AM|PM)').firstMatch(ss);
        if (match != null) {
          sleepSchedule = '${_to24Hour(match.group(1)!, match.group(3)!)}-${_to24Hour(match.group(4)!, match.group(6)!)}';
          dev.log('   - Parsed sleep schedule: $sleepSchedule', name: 'AiScheduler');
        } else {
          dev.log('   - Could not parse sleep schedule format', name: 'AiScheduler');
        }
      } else {
        dev.log('   - Using default sleep schedule: $sleepSchedule', name: 'AiScheduler');
      }
    } else {
      dev.log('📋 Using default time ranges (no preferences)', name: 'AiScheduler');
      dev.log('   - Working hours: $workingHours', name: 'AiScheduler');
      dev.log('   - Sleep schedule: $sleepSchedule', name: 'AiScheduler');
    }

    return {
      'workingHours': workingHours,
      'sleepSchedule': sleepSchedule,
    };
  }

  static String _to24Hour(String hour, String period) {
    int h = int.parse(hour);
    if (period == 'PM' && h != 12) h += 12;
    if (period == 'AM' && h == 12) h = 0;
    final result = '${h.toString().padLeft(2, '0')}:00';
    dev.log('   - Converted $hour $period to $result', name: 'AiScheduler');
    return result;
  }

  /* ----------------------------------------------------------
   * 4. Check if task is work-related using task tags and user interests
   * ---------------------------------------------------------- */
  static Future<bool> _isWorkRelatedTask(Task task) async {
    dev.log('🔍 Checking if task is work-related:', name: 'AiScheduler');
    dev.log('   - Task ID: ${task.id}', name: 'AiScheduler');
    dev.log('   - Task Title: ${task.title}', name: 'AiScheduler');
    dev.log('   - Task Description: ${task.desc}', name: 'AiScheduler');
    dev.log('   - Task UID: ${task.uid}', name: 'AiScheduler');
    
    try {
      // Get task tags from Firestore
      final taskTags = await _getTaskTags(task.id, task.uid);
      
      dev.log('🔍 Work classification analysis:', name: 'AiScheduler');
      dev.log('   - Task tags: $taskTags', name: 'AiScheduler');

      // Check 1: Task has EXACT "work" tag (case-insensitive)
      if (taskTags != null && taskTags.isNotEmpty) {
        for (final tag in taskTags) {
          final tagStr = tag.toString().toLowerCase().trim();
          if (tagStr == 'work') {
            dev.log('✅ Task identified as WORK: Has exact "work" tag', name: 'AiScheduler');
            return true;
          }
        }
        dev.log('❌ No exact "work" tag found in task', name: 'AiScheduler');
      } else {
        dev.log('❌ No task tags found', name: 'AiScheduler');
      }

      dev.log('🎯 FINAL DECISION: Task identified as PERSONAL', name: 'AiScheduler');
      return false;
      
    } catch (e) {
      dev.log('❌ Error checking if task is work-related: $e', name: 'AiScheduler');
      return false;
    }
  }

  /* ----------------------------------------------------------
   * 5. Get scheduled slots for multiple days
   * ---------------------------------------------------------- */
  static Future<Map<DateTime, List<_TimeSlot>>> _getScheduledSlots({
    required String uid,
    required DateTime startDate,
    required int daysToCheck,
  }) async {
    dev.log('🔍 Fetching scheduled slots for $daysToCheck days starting from ${DateFormat('yyyy-MM-dd').format(startDate)}', name: 'AiScheduler');
    
    final scheduledSlots = <DateTime, List<_TimeSlot>>{};
    
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
        final slots = (snap.docs.first.data()['orderedTasks'] as List<dynamic>)
            .map((json) {
          final date = DateFormat('yyyy-MM-dd').parseUtc(json['date']).toLocal();
          final start = DateFormat('HH:mm').parseUtc(json['start']).toLocal();
          final realStart = DateTime(date.year, date.month, date.day, start.hour, start.minute);
          final dur = json['durationMin'] as int;
          final slot = _TimeSlot(
            start: realStart,
            end: realStart.add(Duration(minutes: dur)),
            taskId: json['id'] as String,
          );
          return slot;
        }).toList();
        
        scheduledSlots[currentDate] = slots;
        dev.log('   - ${dateStr}: ${slots.length} scheduled tasks', name: 'AiScheduler');
      } else {
        scheduledSlots[currentDate] = [];
        dev.log('   - ${dateStr}: No scheduled tasks', name: 'AiScheduler');
      }
    }

    return scheduledSlots;
  }

  /* ----------------------------------------------------------
   * 6. Get hour blocks that are already occupied
   * ---------------------------------------------------------- */
  static Set<int> _getOccupiedHourBlocks(List<_TimeSlot> scheduledSlots) {
    final occupiedHours = <int>{};
    
    for (final slot in scheduledSlots) {
      // Get the hour of the scheduled task
      final taskHour = slot.start.hour;
      
      // Mark this hour as occupied
      occupiedHours.add(taskHour);
      
      // If task spans across multiple hours, mark those hours too
      final endHour = slot.end.hour;
      if (endHour != taskHour) {
        // If task ends at exactly the hour (e.g., 6:00), don't mark that hour
        if (slot.end.minute > 0 || endHour != slot.end.hour) {
          for (int hour = taskHour + 1; hour <= endHour; hour++) {
            occupiedHours.add(hour);
          }
        }
      }
      
      dev.log('   - Task ${slot.taskId} occupies hours: $taskHour${endHour != taskHour ? ' to $endHour' : ''}', name: 'AiScheduler');
    }
    
    dev.log('   - Total occupied hour blocks: $occupiedHours', name: 'AiScheduler');
    return occupiedHours;
  }

  /* ----------------------------------------------------------
   * 7. Find available time slots considering existing schedule and hour blocks
   * ---------------------------------------------------------- */
  static List<_TimeSlot> _findAvailableSlots({
    required DateTime date,
    required List<_TimeSlot> scheduledSlots,
    required int taskDuration,
    required bool isWorkTask,
    required Map<String, String> timeRanges,
  }) {
    final availableSlots = <_TimeSlot>[];
    
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
    
    // Get occupied hour blocks
    final occupiedHourBlocks = _getOccupiedHourBlocks(scheduledSlots);
    
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
        occupiedHourBlocks,
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
        occupiedHourBlocks,
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
      occupiedHourBlocks,
    );
    
    return availableSlots;
  }

  static void _findSlotsInWindow(
    DateTime windowStart,
    DateTime windowEnd,
    List<_TimeSlot> scheduledSlots,
    int taskDuration,
    List<_TimeSlot> availableSlots,
    DateTime sleepStart,
    DateTime sleepEnd,
    Set<int> occupiedHourBlocks,
  ) {
    DateTime currentTime = windowStart;
    
    while (currentTime.add(Duration(minutes: taskDuration)).isBefore(windowEnd) || 
           currentTime.add(Duration(minutes: taskDuration)) == windowEnd) {
      
      final slotEnd = currentTime.add(Duration(minutes: taskDuration));
      
      // Get the hour blocks this slot would occupy
      final slotStartHour = currentTime.hour;
      final slotEndHour = slotEnd.hour;
      final slotHours = <int>{slotStartHour};
      
      // If slot spans multiple hours, add all hours it occupies
      if (slotEndHour != slotStartHour) {
        for (int hour = slotStartHour + 1; hour <= slotEndHour; hour++) {
          slotHours.add(hour);
        }
      }
      
      // Check if any of the slot hours are already occupied
      final hasHourBlockConflict = slotHours.any((hour) => occupiedHourBlocks.contains(hour));
      
      // Check if this slot overlaps with any scheduled slot
      final hasTimeConflict = scheduledSlots.any((scheduled) =>
          (currentTime.isBefore(scheduled.end) && slotEnd.isAfter(scheduled.start)));
      
      // Check if this slot overlaps with sleep time
      final overlapsSleep = (currentTime.isBefore(sleepEnd) && slotEnd.isAfter(sleepStart)) ||
                           (currentTime.isAfter(sleepStart) && currentTime.isBefore(sleepEnd));
      
      if (!hasHourBlockConflict && !hasTimeConflict && !overlapsSleep) {
        availableSlots.add(_TimeSlot(start: currentTime, end: slotEnd, taskId: ''));
        dev.log('   - Available slot: ${DateFormat('HH:mm').format(currentTime)}-${DateFormat('HH:mm').format(slotEnd)} (Hours: $slotHours)', name: 'AiScheduler');
      } else {
        if (hasHourBlockConflict) {
          dev.log('   - Skipped slot: ${DateFormat('HH:mm').format(currentTime)}-${DateFormat('HH:mm').format(slotEnd)} - Hour block conflict (Occupied hours: $occupiedHourBlocks)', name: 'AiScheduler');
        }
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
   * 8. Chat-like prompt for single task with available slots
   * ---------------------------------------------------------- */
  static Future<String> chatSchedule(Task task, {Map<String, dynamic>? userPreferences}) async {
    final today = DateTime.now();
    
    dev.log('🚀 STARTING SINGLE TASK SCHEDULING', name: 'AiScheduler');
    dev.log('📋 TASK DETAILS:', name: 'AiScheduler');
    dev.log('   - ID: ${task.id}', name: 'AiScheduler');
    dev.log('   - Title: ${task.title}', name: 'AiScheduler');
    dev.log('   - Duration: ${task.durationMin}min', name: 'AiScheduler');
    dev.log('   - Priority: ${task.priority.name}', name: 'AiScheduler');
    
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
    final availableSlotsByDay = <DateTime, List<_TimeSlot>>{};
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
        dev.log('✅ Available slots on ${DateFormat('EEE, MMM d').format(date)}: ${slots.length}', name: 'AiScheduler');
      } else {
        dev.log('❌ No available slots on ${DateFormat('EEE, MMM d').format(date)}', name: 'AiScheduler');
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
    
    dev.log('📤 SENDING PROMPT TO AI:', name: 'AiScheduler');
    dev.log('```\n$prompt\n```', name: 'AiScheduler');

    try {
      final resp = await gemini.generateContent([Content.text(prompt)]);
      final response = resp.text?.trim() ?? 'I need more information to schedule this task.';
      dev.log('📥 AI RESPONSE:', name: 'AiScheduler');
      dev.log('```\n$response\n```', name: 'AiScheduler');
      return response;
    } catch (e) {
      dev.log('❌ Error in chatSchedule: $e', name: 'AiScheduler');
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
    required Map<DateTime, List<_TimeSlot>> availableSlotsByDay,
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
      ..writeln('8. DO NOT schedule in hour blocks that already have tasks')
      ..writeln('')
      ..writeln('Reply with: "How about DATE at HH:MM-HH:MM? [Brief reason based on task type and preferences]"')
      ..writeln('Example: "How about ${DateFormat('EEE, MMM d').format(firstAvailableDay)} at 14:30-15:15? Perfect work hours slot for your project task."');

    return buffer.toString();
  }

  /* ----------------------------------------------------------
   * 9. Insert single slot
   * ---------------------------------------------------------- */
  static Future<void> insertSingleSlot(
    Task task, 
    DateTime startTime, 
    DateTime endTime, 
    {required String userId}
  ) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(startTime);

    dev.log('💾 INSERTING SCHEDULE SLOT:', name: 'AiScheduler');
    dev.log('   - User ID: $userId', name: 'AiScheduler');
    dev.log('   - Task: ${task.title}', name: 'AiScheduler');
    dev.log('   - Time: ${DateFormat('HH:mm').format(startTime)}-${DateFormat('HH:mm').format(endTime)}', name: 'AiScheduler');
    dev.log('   - Date: $dateStr', name: 'AiScheduler');

    // Read existing schedule
    final schedSnap = await FirebaseFirestore.instance
        .collection('schedules')
        .where('uid', isEqualTo: userId)
        .where('scheduleDate', isEqualTo: dateStr)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    dev.log('   - Existing schedules found: ${schedSnap.docs.length}', name: 'AiScheduler');

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
    dev.log('   - Added new slot: $newSlot', name: 'AiScheduler');

    // Sort by start time
    merged.sort((a, b) => DateFormat('HH:mm')
        .parseUtc(a['start'])
        .compareTo(DateFormat('HH:mm').parseUtc(b['start'])));

    dev.log('   - Final merged schedule has ${merged.length} tasks', name: 'AiScheduler');

    if (schedSnap.docs.isEmpty) {
      dev.log('   - Creating new schedule document', name: 'AiScheduler');
      await FirebaseFirestore.instance.collection('schedules').add({
        'uid': userId,
        'scheduleDate': dateStr,
        'orderedTasks': merged,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      dev.log('   - Updating existing schedule document: ${schedSnap.docs.first.id}', name: 'AiScheduler');
      await FirebaseFirestore.instance.collection('schedules').doc(schedSnap.docs.first.id).update({
        'orderedTasks': merged,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    dev.log('✅ Schedule saved successfully', name: 'AiScheduler');
  }

  /* ----------------------------------------------------------
   * 10. Check if task can be scheduled (for reschedule flow)
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

/* ---------- Helper class ---------- */
class _TimeSlot {
  final DateTime start;
  final DateTime end;
  final String taskId;
  
  _TimeSlot({required this.start, required this.end, required this.taskId});
}