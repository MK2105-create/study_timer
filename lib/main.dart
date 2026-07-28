import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

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
    size: Size(420, 700),
    center: true,
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setFullScreen(true);
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
enum ClockStyle { minimal, led }

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
  ClockStyle _clockStyle = ClockStyle.minimal;
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
    _loadPreferences();
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

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final styleStr = prefs.getString('clockStyle');
    if (styleStr != null) {
      setState(() {
        _clockStyle = ClockStyle.values.byName(styleStr);
      });
    }
  }

  Future<void> _setClockStyle(ClockStyle style) async {
    setState(() => _clockStyle = style);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('clockStyle', style.name);
  }

  void _openStylePicker() {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: surfaceColor,
        title: Text('Clock style', style: TextStyle(color: creamText)),
        children: [
          RadioListTile<ClockStyle>(
            title: Text('Minimal', style: TextStyle(color: creamText)),
            value: ClockStyle.minimal,
            groupValue: _clockStyle,
            activeColor: accentColor,
            onChanged: (v) {
              if (v != null) _setClockStyle(v);
              Navigator.pop(context);
            },
          ),
          RadioListTile<ClockStyle>(
            title: Text('LED', style: TextStyle(color: creamText)),
            value: ClockStyle.led,
            groupValue: _clockStyle,
            activeColor: accentColor,
            onChanged: (v) {
              if (v != null) _setClockStyle(v);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
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

  @override
  void dispose() {
    windowManager.removeListener(this);
    _timer?.cancel();
    super.dispose();
  }

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HistoryScreen(sessions: _sessions),
      ),
    );
  }

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
  void onWindowRestore() {
    windowManager.setFullScreen(true);
  }

  @override
  Widget build(BuildContext context) {
    final displaySeconds =
        _mode == TimerMode.stopwatch ? _elapsedSeconds : _remainingSeconds;

    // Responsive sizing — computed as a fraction of the ACTUAL screen
    // size, clamped to sane min/max bounds, instead of fixed pixel
    // values tuned for one specific window size.
    final screenSize = MediaQuery.of(context).size;
    final clockFontSize = (screenSize.width * 0.065).clamp(40.0, 130.0);
    final labelFontSize = (screenSize.width * 0.013).clamp(13.0, 20.0);
    final buttonFontSize = (screenSize.width * 0.015).clamp(14.0, 22.0);
    final sectionSpacing = (screenSize.height * 0.045).clamp(20.0, 64.0);

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
                    fontSize: labelFontSize,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: sectionSpacing),
                SegmentedButton<TimerMode>(
                  style: SegmentedButton.styleFrom(
                    backgroundColor: surfaceColor,
                    foregroundColor: mutedText,
                    selectedBackgroundColor: accentColor.withOpacity(0.2),
                    selectedForegroundColor: accentColor,
                    side: BorderSide.none,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    textStyle: TextStyle(fontSize: labelFontSize),
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
                SizedBox(height: sectionSpacing * 1.6),
                _clockStyle == ClockStyle.led
                    ? buildLedClock(
                        _formatTime(displaySeconds), clockFontSize, accentColor)
                    : buildMinimalClock(
                        _formatTime(displaySeconds), clockFontSize, creamText),
                SizedBox(height: sectionSpacing * 1.6),
                if (_mode == TimerMode.pomodoro && !_isRunning)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Duration: ',
                          style: TextStyle(
                              color: mutedText, fontSize: labelFontSize)),
                      DropdownButton<int>(
                        value: _pomodoroDurationMinutes,
                        dropdownColor: surfaceColor,
                        style: TextStyle(
                            color: creamText, fontSize: labelFontSize),
                        underline: Container(
                            height: 1, color: mutedText.withOpacity(0.3)),
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
                SizedBox(height: sectionSpacing),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: bgColor,
                        padding: EdgeInsets.symmetric(
                            horizontal: buttonFontSize * 2.2,
                            vertical: buttonFontSize),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                      onPressed: _isRunning ? _pauseTimer : _startTimer,
                      child: Text(_isRunning ? 'Pause' : 'Start',
                          style: TextStyle(fontSize: buttonFontSize)),
                    ),
                    SizedBox(width: sectionSpacing * 0.4),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: mutedText,
                        side: BorderSide(color: mutedText.withOpacity(0.3)),
                        padding: EdgeInsets.symmetric(
                            horizontal: buttonFontSize * 2.2,
                            vertical: buttonFontSize),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                      onPressed: _resetTimer,
                      child: Text('Reset',
                          style: TextStyle(fontSize: buttonFontSize)),
                    ),
                  ],
                ),
                SizedBox(height: sectionSpacing * 0.7),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(Icons.palette_outlined, color: mutedText),
                      onPressed: _openStylePicker,
                      tooltip: 'Clock style',
                    ),
                    IconButton(
                      icon: Icon(Icons.history, color: mutedText),
                      onPressed: _openHistory,
                      tooltip: 'History',
                    ),
                  ],
                ),
              ],
            ),
          ),
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
                  icon:
                      Icon(Icons.fullscreen_exit, color: mutedText, size: 20),
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

// STYLE 1 — Minimal: plain large serif digits, no card, no background.
// The simplest possible rendering — practically impossible to render
// incorrectly since it's just a single Text widget.
Widget buildMinimalClock(String formatted, double fontSize, Color textColor) {
  return Text(
    formatted,
    style: GoogleFonts.dmSerifDisplay(
      fontSize: fontSize,
      color: textColor,
      shadows: [
        Shadow(color: accentColor.withOpacity(0.3), blurRadius: fontSize * 0.4),
      ],
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}

// STYLE 2 — LED: classic 7-segment digital clock look.
// Each digit is 7 rectangles that are either "on" (lit) or "off" (dim),
// based on a fixed lookup table — no clipping, no font metrics, no
// animation timing to get wrong. Just solid shapes and a color switch.
const Map<String, Set<String>> _segmentMap = {
  '0': {'a', 'b', 'c', 'd', 'e', 'f'},
  '1': {'b', 'c'},
  '2': {'a', 'b', 'g', 'e', 'd'},
  '3': {'a', 'b', 'g', 'c', 'd'},
  '4': {'f', 'g', 'b', 'c'},
  '5': {'a', 'f', 'g', 'c', 'd'},
  '6': {'a', 'f', 'g', 'e', 'c', 'd'},
  '7': {'a', 'b', 'c'},
  '8': {'a', 'b', 'c', 'd', 'e', 'f', 'g'},
  '9': {'a', 'b', 'c', 'd', 'f', 'g'},
};

Widget buildLedClock(String formatted, double fontSize, Color onColor) {
  final digitWidth = fontSize * 0.62;
  final digitHeight = fontSize * 1.3;
  final offColor = onColor.withOpacity(0.08);

  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: formatted.split('').map((char) {
      if (char == ':') {
        return SizedBox(
          width: fontSize * 0.28,
          height: digitHeight,
          child: Center(
            child: Text(
              ':',
              style: TextStyle(
                fontSize: fontSize * 0.55,
                color: onColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      }
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: fontSize * 0.035),
        child: SevenSegmentDigit(
          digit: char,
          width: digitWidth,
          height: digitHeight,
          onColor: onColor,
          offColor: offColor,
        ),
      );
    }).toList(),
  );
}

class SevenSegmentDigit extends StatelessWidget {
  final String digit;
  final double width;
  final double height;
  final Color onColor;
  final Color offColor;

  const SevenSegmentDigit({
    super.key,
    required this.digit,
    required this.width,
    required this.height,
    required this.onColor,
    required this.offColor,
  });

  @override
  Widget build(BuildContext context) {
    final segsOn = _segmentMap[digit] ?? <String>{};
    final t = width * 0.18; // segment thickness
    final margin = width * 0.10; // side margin for horizontal segments
    final segW = width - margin * 2; // horizontal segment length
    final vSegH = (height - t * 1.6) / 2; // vertical segment length
    final radius = t * 0.35;

    Widget seg(String name, double left, double top, double w, double h) {
      final isOn = segsOn.contains(name);
      return Positioned(
        left: left,
        top: top,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: isOn ? onColor : offColor,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: isOn
                ? [BoxShadow(color: onColor.withOpacity(0.5), blurRadius: 6)]
                : null,
          ),
        ),
      );
    }

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          seg('a', margin, 0, segW, t),
          seg('f', 0, t * 0.5, t, vSegH),
          seg('b', width - t, t * 0.5, t, vSegH),
          seg('g', margin, height / 2 - t / 2, segW, t),
          seg('e', 0, height / 2 + t * 0.5, t, vSegH),
          seg('c', width - t, height / 2 + t * 0.5, t, vSegH),
          seg('d', margin, height - t, segW, t),
        ],
      ),
    );
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
                  trailing:
                      Text(s.mode.name, style: TextStyle(color: mutedText)),
                );
              },
            ),
    );
  }
}