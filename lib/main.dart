import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

// Warm palette — defined once at the top level so every screen can reuse it.
const bgColor = Color(0xFF1C1410);
const surfaceColor = Color(0xFF2A2019);
const accentColor = Color(0xFFE8A24C);
const secondaryAccent = Color(0xFFC1622E);
const creamText = Color(0xFFF5E9D9);
const mutedText = Color(0xFFA89584);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(420, 700), // fallback size; overridden by setFullScreen below
    center: true,
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setFullScreen(true); // NEW — launches fullscreen
  });

  runApp(const StudyTimerApp());
}

class StudyTimerApp extends StatelessWidget {
  const StudyTimerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Study Timer',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bgColor,
        useMaterial3: true,
        colorScheme: ColorScheme.dark(
          primary: accentColor,
          secondary: mutedText,
          surface: bgColor,
        ),
        textTheme: GoogleFonts.karlaTextTheme(ThemeData.dark().textTheme),
      ),
      home: const TimerScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

enum TimerMode { stopwatch, pomodoro }

class StudySession {
  final int durationSeconds;
  final TimerMode mode;
  final DateTime completedAt;

  StudySession({
    required this.durationSeconds,
    required this.mode,
    required this.completedAt,
  });

  Map<String, dynamic> toJson() => {
        'durationSeconds': durationSeconds,
        'mode': mode.name,
        'completedAt': completedAt.toIso8601String(),
      };

  factory StudySession.fromJson(Map<String, dynamic> json) => StudySession(
        durationSeconds: json['durationSeconds'],
        mode: TimerMode.values.byName(json['mode']),
        completedAt: DateTime.parse(json['completedAt']),
      );
}

class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> with WindowListener {
  TimerMode _mode = TimerMode.stopwatch;
  int _elapsedSeconds = 0;
  int _pomodoroDurationMinutes = 25;
  late int _remainingSeconds;
  Timer? _timer;
  bool _isRunning = false;

  List<StudySession> _sessions = [];

  @override
  void initState() {
    super.initState();
     windowManager.addListener(this);
    _remainingSeconds = _pomodoroDurationMinutes * 60;
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final String? sessionsJson = prefs.getString('sessions');
    if (sessionsJson != null) {
      final List<dynamic> decoded = jsonDecode(sessionsJson);
      setState(() {
        _sessions = decoded.map((e) => StudySession.fromJson(e)).toList();
      });
    }
  }

  Future<void> _saveSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded =
        jsonEncode(_sessions.map((s) => s.toJson()).toList());
    await prefs.setString('sessions', encoded);
  }

  void _startTimer() {
    if (_isRunning) return;
    setState(() => _isRunning = true);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_mode == TimerMode.stopwatch) {
          _elapsedSeconds++;
        } else {
          if (_remainingSeconds > 0) {
            _remainingSeconds--;
          } else {
            _timer?.cancel();
            _isRunning = false;
            _logSession(_pomodoroDurationMinutes * 60);
            _showSessionCompleteDialog();
          }
        }
      });
    });
  }

  void _logSession(int durationSeconds) {
    final session = StudySession(
      durationSeconds: durationSeconds,
      mode: _mode,
      completedAt: DateTime.now(),
    );
    setState(() {
      _sessions.insert(0, session);
    });
    _saveSessions();
  }

  void _pauseTimer() {
    _timer?.cancel();
    setState(() => _isRunning = false);
  }

  void _resetTimer() {
    _timer?.cancel();
    if (_mode == TimerMode.stopwatch && _elapsedSeconds > 0) {
      _logSession(_elapsedSeconds);
    }
    setState(() {
      _isRunning = false;
      _elapsedSeconds = 0;
      _remainingSeconds = _pomodoroDurationMinutes * 60;
    });
  }

  void _switchMode(TimerMode newMode) {
    _timer?.cancel();
    setState(() {
      _mode = newMode;
      _isRunning = false;
      _elapsedSeconds = 0;
      _remainingSeconds = _pomodoroDurationMinutes * 60;
    });
  }

  void _showSessionCompleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: surfaceColor,
        title: Text('Session complete', style: TextStyle(color: creamText)),
        content: Text(
          'You focused for $_pomodoroDurationMinutes minutes.',
          style: TextStyle(color: mutedText),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resetTimer();
            },
            child: Text('OK', style: TextStyle(color: accentColor)),
          ),
        ],
      ),
    );
  }

  String _formatTime(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  int get _todaysTotalSeconds {
    final now = DateTime.now();
    return _sessions
        .where((s) =>
            s.completedAt.year == now.year &&
            s.completedAt.month == now.month &&
            s.completedAt.day == now.day)
        .fold(0, (sum, s) => sum + s.durationSeconds);
  }

  double get _pomodoroProgress {
    final total = _pomodoroDurationMinutes * 60;
    if (total == 0) return 0;
    return (total - _remainingSeconds) / total;
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _timer?.cancel();
    super.dispose();
  }
  
  @override
  void onWindowRestore() {
    windowManager.setFullScreen(true);
  }

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HistoryScreen(sessions: _sessions),
      ),
    );
  }

  // NEW — toggles fullscreen off, so there's always a way out.
  Future<void> _exitFullscreen() async {
    final isFullscreen = await windowManager.isFullScreen();
    await windowManager.setFullScreen(!isFullscreen);
  }

  Future<void> _minimizeWindow() async {
    final isFullscreen = await windowManager.isFullScreen();
    if (isFullscreen) {
    await windowManager.setFullScreen(false);
    await Future.delayed(const Duration(milliseconds: 150));
  }
  await windowManager.minimize();
}
  

  @override
  Widget build(BuildContext context) {
    final displaySeconds =
        _mode == TimerMode.stopwatch ? _elapsedSeconds : _remainingSeconds;

    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Today: ${_formatTime(_todaysTotalSeconds)}',
                  style: TextStyle(
                    color: mutedText,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 32),
                SegmentedButton<TimerMode>(
                  style: SegmentedButton.styleFrom(
                    backgroundColor: surfaceColor,
                    foregroundColor: mutedText,
                    selectedBackgroundColor: accentColor.withOpacity(0.2),
                    selectedForegroundColor: accentColor,
                    side: BorderSide.none,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  segments: const [
                    ButtonSegment(
                        value: TimerMode.stopwatch, label: Text('Timer')),
                    ButtonSegment(
                        value: TimerMode.pomodoro, label: Text('Pomodoro')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (newSelection) {
                    _switchMode(newSelection.first);
                  },
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: 320,
                  height: 320,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(320, 320),
                        painter: _RingPainter(
                          progress:
                              _mode == TimerMode.pomodoro ? _pomodoroProgress : 0,
                          color: accentColor,
                          trackColor: surfaceColor,
                        ),
                      ),
                      Text(
                        _formatTime(displaySeconds),
                        style: GoogleFonts.dmSerifDisplay(
                          fontSize: 56,
                          color: creamText,
                          shadows: [
                            Shadow(
                              color: accentColor.withOpacity(0.35),
                              blurRadius: 28,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                if (_mode == TimerMode.pomodoro && !_isRunning)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Duration: ', style: TextStyle(color: mutedText)),
                      DropdownButton<int>(
                        value: _pomodoroDurationMinutes,
                        dropdownColor: surfaceColor,
                        style: TextStyle(color: creamText),
                        underline:
                            Container(height: 1, color: mutedText.withOpacity(0.3)),
                        items: [15, 20, 25, 30, 45, 60]
                            .map((m) => DropdownMenuItem(
                                value: m, child: Text('$m min')))
                            .toList(),
                        onChanged: (newValue) {
                          if (newValue == null) return;
                          setState(() {
                            _pomodoroDurationMinutes = newValue;
                            _remainingSeconds = newValue * 60;
                          });
                        },
                      ),
                    ],
                  ),
                const SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: bgColor,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                      onPressed: _isRunning ? _pauseTimer : _startTimer,
                      child: Text(_isRunning ? 'Pause' : 'Start'),
                    ),
                    const SizedBox(width: 16),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: mutedText,
                        side: BorderSide(color: mutedText.withOpacity(0.3)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                      onPressed: _resetTimer,
                      child: const Text('Reset'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                IconButton(
                  icon: Icon(Icons.history, color: mutedText),
                  onPressed: _openHistory,
                ),
              ],
            ),
          ),

          // Custom window controls — since we're borderless/fullscreen,
          // Windows' native minimize/maximize/close buttons don't exist
          // anymore. We rebuild all three ourselves, styled to match.
          Positioned(
            top: 16,
            right: 16,
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.remove, color: mutedText, size: 20),
                  onPressed: _minimizeWindow,
                  tooltip: 'Minimize',
                ),
                IconButton(
                  icon: Icon(Icons.fullscreen_exit, color: mutedText, size: 20),
                  onPressed: _exitFullscreen,
                  tooltip: 'Exit fullscreen',
                ),
                IconButton(
                  icon: Icon(Icons.close, color: mutedText, size: 20),
                  onPressed: () => windowManager.close(),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;

  _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class HistoryScreen extends StatelessWidget {
  final List<StudySession> sessions;

  const HistoryScreen({super.key, required this.sessions});

  String _formatDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        title: Text('Session History', style: TextStyle(color: creamText)),
        iconTheme: IconThemeData(color: creamText),
      ),
      body: sessions.isEmpty
          ? Center(
              child: Text('No sessions yet — go study something!',
                  style: TextStyle(color: mutedText)))
          : ListView.builder(
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final s = sessions[index];
                return ListTile(
                  leading: Icon(
                    s.mode == TimerMode.pomodoro
                        ? Icons.timer
                        : Icons.watch_later_outlined,
                    color: accentColor,
                  ),
                  title: Text(_formatDuration(s.durationSeconds),
                      style: TextStyle(color: creamText)),
                  subtitle: Text(
                    '${s.completedAt.month}/${s.completedAt.day}/${s.completedAt.year} '
                    '${s.completedAt.hour.toString().padLeft(2, '0')}:'
                    '${s.completedAt.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(color: mutedText),
                  ),
                  trailing: Text(s.mode.name, style: TextStyle(color: mutedText)),
                );
              },
            ),
    );
  }
}