import 'package:url_launcher/url_launcher.dart';
import 'package:taskhaura/models/task.dart';
import 'package:intl/intl.dart';
import 'dart:io' show Platform;

class DeepLinkCalendarService {
  
  Future<bool> addTaskToCalendar(Task task) async {
    try {
      final startTime = task.deadline;
      final endTime = startTime?.add(Duration(minutes: task.durationMin));
      
      // Format dates for Google Calendar
      final String start = _formatDateTimeForCalendar(startTime!);
      final String end = _formatDateTimeForCalendar(endTime!);
      
      // Create Google Calendar URL - use the simpler format that works
      final String url = 
          'https://calendar.google.com/calendar/render?'
          'action=TEMPLATE'
          '&text=${Uri.encodeComponent(task.title)}'
          '&details=${Uri.encodeComponent(_getDescription(task))}'
          '&dates=$start/$end';

      print('Opening Google Calendar URL: $url');
      
      // For emulator, use external application mode
      final LaunchMode launchMode = _isLikelyEmulator() ? 
          LaunchMode.externalApplication : 
          LaunchMode.platformDefault;
      
      final result = await launchUrl(
        Uri.parse(url),
        mode: launchMode,
      );
      
      if (!result) {
        print('Could not launch $url');
        return false;
      }
      return true;
      
    } catch (e) {
      print('Error occurred: $e');
      return false;
    }
  }

  // Check if we're likely running on an emulator
  bool _isLikelyEmulator() {
    // Simple check - emulators often have issues with platform default mode
    // So we force external application mode for better compatibility
    return Platform.isAndroid && 
           (Platform.environment['ANDROID_EMULATOR'] != null ||
            Platform.environment['QEMU'] != null ||
            _isProbablyEmulator());
  }

  bool _isProbablyEmulator() {
    // Additional checks for emulator
    final model = Platform.environment['MODEL'] ?? '';
    final brand = Platform.environment['BRAND'] ?? '';
    final hardware = Platform.environment['HARDWARE'] ?? '';
    
    return model.contains('sdk') || 
           model.contains('Emulator') ||
           brand.contains('generic') ||
           hardware.contains('goldfish');
  }

  String _getDescription(Task task) {
    String description = '';
    
    if (task.desc.isNotEmpty) {
      description += '${task.desc}\n\n';
    }
    
    description += 'Task Details:\n';
    description += '• Duration: ${task.durationMin} minutes\n';
    description += '• Priority: ${task.priority.name.toUpperCase()}\n';
    
    if (task.tag.isNotEmpty) {
      description += '• Tag: ${task.tag}\n';
    }
    
    description += '• Created via TaskHaura App';
    
    return description;
  }

  String _formatDateTimeForCalendar(DateTime date) {
    final year = date.year.toString();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    final second = '00';
    
    return '${year}${month}${day}T${hour}${minute}${second}Z';
  }
}