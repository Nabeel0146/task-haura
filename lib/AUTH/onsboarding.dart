import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:taskhaura/screens/mainscreen.dart';

class OnboardingPage extends StatefulWidget {
  final String uid;
  const OnboardingPage({super.key, required this.uid});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isLoading = false;

  // User data to collect
  String _workType = '';
  TimeOfDay? _workStartTime;
  TimeOfDay? _workEndTime;
  TimeOfDay? _sleepTime; // Bedtime
  TimeOfDay? _wakeUpTime; // Wake-up time
  String _focusStyle = '';
  List<String> _interests = [];
  String _productivityGoal = '';

  // Available options
  final List<String> _workTypes = [
    'Full-time Employee',
    'Freelancer',
    'Student',
    'Entrepreneur',
    'Part-time Worker',
    'Remote Worker',
    'Other'
  ];

  final List<String> _focusStyles = [
    'Deep Focus (2-4 hour blocks)',
    'Pomodoro (25min work/5min break)',
    'Time Blocking (60-90min sessions)',
    'Flexible (Adapt as needed)',
    'Frequent Breaks (15-20min work cycles)'
  ];

  final List<String> _interestOptions = [
    'Work Projects',
    'Personal Development',
    'Health & Fitness',
    'Creative Work',
    'Learning & Education',
    'Household Tasks',
    'Social & Family',
    'Financial Planning',
    'Side Projects',
    'Self Care'
  ];

  final List<String> _goalOptions = [
    'Increase Daily Productivity',
    'Better Work-Life Balance',
    'Reduce Procrastination',
    'Complete Specific Projects',
    'Build Better Habits',
    'Manage Multiple Responsibilities',
    'Improve Time Management'
  ];

  /* ---------- Navigation ---------- */
  void _nextPage() {
    if (_currentPage < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  /* ---------- Work Type Selection Handler ---------- */
  void _handleWorkTypeSelection(String type) {
    setState(() {
      _workType = type;
      
      // Set default working hours based on work type
      switch (type) {
        case 'Full-time Employee':
          _workStartTime = const TimeOfDay(hour: 9, minute: 0);
          _workEndTime = const TimeOfDay(hour: 17, minute: 0);
          break;
        case 'Student':
          _workStartTime = const TimeOfDay(hour: 9, minute: 0);
          _workEndTime = const TimeOfDay(hour: 17, minute: 0);
          break;
        case 'Part-time Worker':
          _workStartTime = const TimeOfDay(hour: 12, minute: 0);
          _workEndTime = const TimeOfDay(hour: 17, minute: 0);
          break;
        case 'Freelancer':
        case 'Entrepreneur':
        case 'Remote Worker':
        case 'Other':
          // Keep existing times if already set, otherwise leave as null for flexible
          break;
      }
    });
  }

  /* ---------- Time Picker ---------- */
  Future<void> _pickTime(bool isStart, bool isWorkTime) async {
    TimeOfDay? initialTime;
    
    if (isWorkTime) {
      initialTime = isStart
          ? (_workStartTime ?? const TimeOfDay(hour: 9, minute: 0))
          : (_workEndTime ?? const TimeOfDay(hour: 17, minute: 0));
    } else {
      initialTime = isStart
          ? (_sleepTime ?? const TimeOfDay(hour: 22, minute: 0)) // Default bedtime 10 PM
          : (_wakeUpTime ?? const TimeOfDay(hour: 6, minute: 0)); // Default wake-up 6 AM
    }
    
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF74EC7A),
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() {
        if (isWorkTime) {
          if (isStart) {
            _workStartTime = picked;
          } else {
            _workEndTime = picked;
          }
        } else {
          if (isStart) {
            _sleepTime = picked;
          } else {
            _wakeUpTime = picked;
          }
        }
      });
    }
  }

  /* ---------- Save Data ---------- */
  Future<void> _completeOnboarding() async {
    setState(() => _isLoading = true);

    try {
      final workingHours = _workStartTime != null && _workEndTime != null
          ? '${_formatTime(_workStartTime!)} – ${_formatTime(_workEndTime!)}'
          : 'Flexible';

      final sleepSchedule = _sleepTime != null && _wakeUpTime != null
          ? '${_formatTime(_sleepTime!)} – ${_formatTime(_wakeUpTime!)}'
          : 'Not set';

      // Store all user preferences in Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .update({
        'workType': _workType,
        'workingHours': workingHours,
        'sleepSchedule': sleepSchedule, // Add sleep schedule to Firestore
        'focusStyle': _focusStyle,
        'interests': _interests,
        'productivityGoal': _productivityGoal,
        'onboardingCompleted': true,
        'tags': _interests,
        'preferences': {
          'workType': _workType,
          'workingHours': workingHours,
          'sleepSchedule': sleepSchedule, // Add sleep schedule to preferences
          'focusStyle': _focusStyle,
          'productivityGoal': _productivityGoal,
          'interests': _interests,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    
    if (hour == 0) {
      return '12:$minute AM';
    } else if (hour < 12) {
      return '$hour:$minute AM';
    } else if (hour == 12) {
      return '12:$minute PM';
    } else {
      return '${hour - 12}:$minute PM';
    }
  }

  /* ---------- Page Content ---------- */
  Widget _buildPage1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          _buildProgressIndicator(),
          const SizedBox(height: 40),
          const Text(
            'How do you primarily work?',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This helps us tailor your task management experience',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 40),
          
          // Work Type Selection
          Column(
            children: _workTypes.map((type) {
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _workType == type ? Colors.white : const Color(0xFF74EC7A),
                    backgroundColor: _workType == type ? const Color(0xFF74EC7A) : Colors.transparent,
                    side: BorderSide(
                      color: _workType == type ? const Color(0xFF74EC7A) : Colors.grey[300]!,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _handleWorkTypeSelection(type),
                  child: Text(
                    type,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              );
            }).toList(),
          ),
          
          // Show selected working hours if applicable
          if (_workType.isNotEmpty && _workStartTime != null && _workEndTime != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF74EC7A).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.access_time,
                    color: const Color(0xFF74EC7A),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Default working hours set for $_workType',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          '${_formatTime(_workStartTime!)} – ${_formatTime(_workEndTime!)}',
                          style: const TextStyle(
                            color: Color(0xFF74EC7A),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPage2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          _buildProgressIndicator(),
          const SizedBox(height: 40),
          const Text(
            'What\'s your typical sleep schedule?',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This helps us respect your rest time and optimize your waking hours',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 40),
          
          // Sleep Schedule
          Column(
            children: [
              // Sleep Time Selection
              Row(
                children: [
                  Expanded(
                    child: _buildSleepTimeCard('Bedtime', _sleepTime, true),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildSleepTimeCard('Wake-up Time', _wakeUpTime, false),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Sleep Quality Note
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF74EC7A).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF74EC7A).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.nightlight_round,
                      color: const Color(0xFF74EC7A),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'We\'ll avoid scheduling tasks during your sleep hours to protect your rest',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              
              // Focus Style
              const Text(
                'How do you prefer to work?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This helps us structure your tasks effectively',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 16),
              
              Column(
                children: _focusStyles.map((style) {
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _focusStyle == style ? Colors.white : const Color(0xFF74EC7A),
                        backgroundColor: _focusStyle == style ? const Color(0xFF74EC7A) : Colors.transparent,
                        side: BorderSide(
                          color: _focusStyle == style ? const Color(0xFF74EC7A) : Colors.grey[300]!,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => setState(() => _focusStyle = style),
                      child: Text(
                        style,
                        style: const TextStyle(fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSleepTimeCard(String label, TimeOfDay? time, bool isBedtime) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _pickTime(isBedtime, false), // false = sleep time, not work time
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isBedtime ? Icons.nightlight_round : Icons.wb_sunny_outlined,
                    color: const Color(0xFF74EC7A),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF74EC7A).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.access_time,
                      color: Color(0xFF74EC7A),
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                time != null ? _formatTime(time) : 'Tap to set time',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: time != null ? const Color(0xFF74EC7A) : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ... Rest of the code (_buildPage3, _buildPage4, etc. remains the same)
  Widget _buildPage3() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          _buildProgressIndicator(),
          const SizedBox(height: 40),
          const Text(
            'What matters to you?',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select areas you\'d like to focus on (choose 2-4)',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 32),
          
          // Interests Selection
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _interestOptions.map((interest) {
              final isSelected = _interests.contains(interest);
              return FilterChip(
                label: Text(interest),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      if (_interests.length < 4) {
                        _interests.add(interest);
                      }
                    } else {
                      _interests.remove(interest);
                    }
                  });
                },
                selectedColor: const Color(0xFF74EC7A),
                checkmarkColor: Colors.white,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              );
            }).toList(),
          ),
          
          if (_interests.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Selected: ${_interests.length}/4',
              style: const TextStyle(
                color: Color(0xFF74EC7A),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildPage4() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          _buildProgressIndicator(),
          const SizedBox(height: 40),
          const Text(
            'What\'s your main goal?',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This helps us prioritize what\'s important to you',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 40),
          
          // Goal Selection
          Column(
            children: _goalOptions.map((goal) {
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: _productivityGoal == goal 
                          ? const Color(0xFF74EC7A) 
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    leading: Icon(
                      Icons.flag_outlined,
                      color: _productivityGoal == goal 
                          ? const Color(0xFF74EC7A)
                          : Colors.grey,
                    ),
                    title: Text(
                      goal,
                      style: TextStyle(
                        fontWeight: _productivityGoal == goal 
                            ? FontWeight.w600 
                            : FontWeight.normal,
                        color: _productivityGoal == goal 
                            ? const Color(0xFF74EC7A)
                            : Colors.black87,
                      ),
                    ),
                    onTap: () => setState(() => _productivityGoal = goal),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Column(
      children: [
        LinearProgressIndicator(
          value: (_currentPage + 1) / 4,
          backgroundColor: Colors.grey[200],
          color: const Color(0xFF74EC7A),
          minHeight: 4,
          borderRadius: BorderRadius.circular(2),
        ),
        const SizedBox(height: 8),
        Text(
          '${_currentPage + 1} of 4',
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  bool get _canProceed {
    switch (_currentPage) {
      case 0:
        return _workType.isNotEmpty;
      case 1:
        return _focusStyle.isNotEmpty;
      case 2:
        return _interests.length >= 2;
      case 3:
        return _productivityGoal.isNotEmpty;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (page) => setState(() => _currentPage = page),
                  children: [
                    _buildPage1(),
                    _buildPage2(),
                    _buildPage3(),
                    _buildPage4(),
                  ],
                ),
              ),
              
              // Navigation Buttons
              Padding(
                padding: const EdgeInsets.only(bottom: 40, top: 20),
                child: Row(
                  children: [
                    if (_currentPage > 0)
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF74EC7A),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: const BorderSide(color: Color(0xFF74EC7A)),
                          ),
                          onPressed: _previousPage,
                          child: const Text('Back'),
                        ),
                      ),
                    if (_currentPage > 0) const SizedBox(width: 12),
                    Expanded(
                      flex: _currentPage > 0 ? 1 : 2,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _canProceed 
                              ? const Color(0xFF74EC7A)
                              : Colors.grey[400],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        onPressed: _canProceed ? _nextPage : null,
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _currentPage == 3 ? 'Get Started' : 'Continue',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}