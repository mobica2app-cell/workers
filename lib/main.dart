// lib/main.dart
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobitem/pages/login_page.dart';
import 'package:mobitem/pages/main_shell.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:universal_html/html.dart' as html;
import 'services/sap_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Global Theme Notifier for instant theme changes
class ThemeNotifier extends ChangeNotifier {
  static final ThemeNotifier instance = ThemeNotifier._();

  bool _isDarkMode = false;
  static const String _themeKey = 'app_theme_preference';

  bool get isDarkMode => _isDarkMode;

  ThemeNotifier._() {
    _loadThemePreference();
  }

  void _loadThemePreference() {
    try {
      final String? savedTheme = html.window.localStorage[_themeKey];

      if (savedTheme != null && savedTheme.isNotEmpty) {
        _isDarkMode = savedTheme == 'dark';
      } else {
        _isDarkMode = html.window.matchMedia('(prefers-color-scheme: dark)').matches;
      }
    } catch (e) {
      print('Error loading theme preference: $e');
      _isDarkMode = false;
    }
  }

  void toggleTheme(bool isDark) {
    if (_isDarkMode != isDark) {
      _isDarkMode = isDark;
      try {
        html.window.localStorage[_themeKey] = isDark ? 'dark' : 'light';
      } catch (e) {
        print('Error saving theme preference: $e');
      }
      notifyListeners();
    }
  }

  void refreshTheme() {
    _loadThemePreference();
    notifyListeners();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeNotifier.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'Mood',
          debugShowCheckedModeBanner: false,
          theme: _buildLightTheme(),
          darkTheme: _buildDarkTheme(),
          themeMode: ThemeNotifier.instance.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) {
            final screenWidth = MediaQuery.of(context).size.width;
            final brightness = Theme.of(context).brightness;
            final isDark = brightness == Brightness.dark;

            Widget content = child!;

            // Wrap with theme-aware container
            content = ColoredBox(
              color: isDark ? const Color(0xFF000000) : const Color(0xFFF8FAFC),
              child: content,
            );

            // Scale down to 1120px desktop width when viewed on screens smaller than 1120px
            if (screenWidth < 1120) {
              content = ResponsiveScaledBox(
                width: 680,
                child: content,
              );
            }

            return AutoRefreshManager(
              child: SmartZoomWrapper(
                child: content,
              ),
            );
          },
          home: const LoginPage(),
        );
      },
    );
  }

  // Light Theme
  ThemeData _buildLightTheme() {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF000000),
      brightness: Brightness.light,
      primary: const Color(0xFF0F172A),
      secondary: const Color(0xFF3B82F6),
      surface: const Color(0xFFFFFFFF),
      background: const Color(0xFFF8FAFC),
      error: const Color(0xFFEF4444),
      onPrimary: const Color(0xFFFFFFFF),
      onSecondary: const Color(0xFFFFFFFF),
      onSurface: const Color(0xFF1E293B),
      onBackground: const Color(0xFF1E293B),
      onError: const Color(0xFFFFFFFF),
    );

    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      fontFamily: GoogleFonts.cairo().fontFamily,
      useMaterial3: true,
      textTheme: GoogleFonts.cairoTextTheme(
        ThemeData.light().textTheme,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFFFFFFF),
        foregroundColor: Color(0xFF0F172A),
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFFFFFFFF),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFFFFFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF0F172A), width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0F172A),
          foregroundColor: const Color(0xFFFFFFFF),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE2E8F0),
        thickness: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFFFFFFFF),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: const Color(0xFFFFFFFF),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1E293B),
        contentTextStyle: GoogleFonts.cairo(
          color: Colors.white,
          fontSize: 14,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  // Dark Theme
  ThemeData _buildDarkTheme() {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF000000),
      brightness: Brightness.dark,
      primary: const Color(0xFF60A5FA),
      secondary: const Color(0xFF3B82F6),
      surface: const Color(0xFF121212),
      background: const Color(0xFF000000),
      error: const Color(0xFFEF4444),
      onPrimary: const Color(0xFF000000),
      onSecondary: const Color(0xFFFFFFFF),
      onSurface: const Color(0xFFF5F5F5),
      onBackground: const Color(0xFFF5F5F5),
      onError: const Color(0xFFFFFFFF),
    );

    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF000000),
      fontFamily: GoogleFonts.cairo().fontFamily,
      useMaterial3: true,
      textTheme: GoogleFonts.cairoTextTheme(
        ThemeData.dark().textTheme,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF121212),
        foregroundColor: Color(0xFFF5F5F5),
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF121212),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF121212),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF60A5FA), width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF60A5FA),
          foregroundColor: const Color(0xFF0F172A),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF334155),
        thickness: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF1E293B),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: const Color(0xFF121212),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF000000),
        contentTextStyle: GoogleFonts.cairo(
          color: Colors.white,
          fontSize: 14,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

/// Controls zoom activation via Touch OR by holding the 'Z' key on Desktop/Web
class SmartZoomWrapper extends StatefulWidget {
  final Widget child;
  const SmartZoomWrapper({Key? key, required this.child}) : super(key: key);

  @override
  State<SmartZoomWrapper> createState() => _SmartZoomWrapperState();
}

class _SmartZoomWrapperState extends State<SmartZoomWrapper> {
  final FocusNode _focusNode = FocusNode();
  bool _isCtrlPressed = false;
  bool _isTouchDevice = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool canZoom = _isTouchDevice || _isCtrlPressed;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        final isCtrlDown =
            HardwareKeyboard.instance.isLogicalKeyPressed(
              LogicalKeyboardKey.controlLeft,
            ) ||
                HardwareKeyboard.instance.isLogicalKeyPressed(
                  LogicalKeyboardKey.controlRight,
                );
        if (isCtrlDown != _isCtrlPressed) {
          setState(() {
            _isCtrlPressed = isCtrlDown;
          });
        }
      },
      child: Listener(
        onPointerDown: (event) {
          final isTouch = event.kind == PointerDeviceKind.touch;
          if (isTouch != _isTouchDevice) {
            setState(() {
              _isTouchDevice = isTouch;
            });
          }
        },
        child: InteractiveViewer(
          scaleEnabled: canZoom,
          panEnabled: canZoom,
          minScale: 1.0,
          maxScale: 3.0,
          clipBehavior: Clip.none,
          child: widget.child,
        ),
      ),
    );
  }
}

class EmployeeAuthService {
  final SupabaseClient _client;
  static const String _sessionTokenKey = 'mood_session_token';

  EmployeeAuthService(this._client);

  String? get sessionToken {
    try {
      final sessionValue = html.window.sessionStorage[_sessionTokenKey];
      if (sessionValue != null && sessionValue.isNotEmpty) return sessionValue;
      final persistentValue = html.window.localStorage[_sessionTokenKey];
      if (persistentValue == null || persistentValue.isEmpty) return null;
      // Restore the persistent token into this browser session as well, so
      // existing features that read sessionStorage continue to work.
      html.window.sessionStorage[_sessionTokenKey] = persistentValue;
      return persistentValue;
    } catch (_) {
      return null;
    }
  }

  Map<String, String> get _sessionHeaders => {
    if (sessionToken != null) 'Authorization': 'Bearer $sessionToken',
  };

  Future<Map<String, dynamic>?> _invokeAuth(
      Map<String, dynamic> body, {
        bool requireSession = true,
      }) async {
    try {
      final token = sessionToken;
      if (requireSession && (token == null || token.isEmpty)) return null;
      final response = await _client.functions.invoke(
        'mood-auth',
        body: body,
        headers: requireSession ? {'Authorization': 'Bearer $token'} : const {},
      );
      if (response.status < 200 || response.status >= 300 || response.data is! Map) {
        return null;
      }
      return Map<String, dynamic>.from(response.data as Map);
    } catch (e) {
      print('MOOD auth request failed: $e');
      return null;
    }
  }

  Future<EmployeeAuth?> login(
      String username,
      String password, {
        bool rememberMe = false,
      }) async {
    try {
      final response = await _client.functions.invoke(
        'mood-auth',
        body: {
          'action': 'login',
          'username': username,
          'password': password,
          'remember_me': rememberMe,
        },
      );
      if (response.status < 200 || response.status >= 300 || response.data is! Map) {
        return null;
      }
      final payload = Map<String, dynamic>.from(response.data as Map);
      final token = payload['token']?.toString();
      final employeeData = payload['employee'];
      if (token == null || token.isEmpty || employeeData is! Map) return null;
      html.window.sessionStorage[_sessionTokenKey] = token;
      if (rememberMe) {
        html.window.localStorage[_sessionTokenKey] = token;
      } else {
        html.window.localStorage.remove(_sessionTokenKey);
      }
      return EmployeeAuth.fromJson(Map<String, dynamic>.from(employeeData));
    } catch (e) {
      print('Login error: $e');
      return null;
    }
  }

  Future<List<EmployeeAuth>> getAllEmployees() async {
    final result = await _invokeAuth({'action': 'list_employees'});
    final employees = result?['employees'];
    if (employees is! List) return [];
    return employees
        .whereType<Map>()
        .map((row) => EmployeeAuth.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<EmployeeAuth?> getEmployeeById(String id) async {
    final result = await _invokeAuth({'action': 'get_employee', 'id': id});
    final employee = result?['employee'];
    if (employee is! Map) return null;
    return EmployeeAuth.fromJson(Map<String, dynamic>.from(employee));
  }

  Future<bool> addEmployee({
    required String username,
    required String password,
    required String fullName,
    String? department,
    String? role,
    String? phoneNumber,
  }) async {
    final result = await _invokeAuth({
      'action': 'create_employee',
      'username': username.trim(),
      'password': password,
      'full_name': fullName.trim(),
      'department': department,
      'role': role,
      'phone_number': phoneNumber,
    });
    return result?['employee'] is Map;
  }

  Future<bool> updateEmployee({
    required String id,
    String? fullName,
    String? username,
    String? department,
    String? role,
    String? phoneNumber,
    String? password,
    bool? isActive,
  }) async {
    final updates = <String, dynamic>{'action': 'update_employee', 'id': id};
    if (fullName != null) updates['full_name'] = fullName;
    if (username != null) updates['username'] = username.trim();
    if (department != null) updates['department'] = department;
    if (role != null) updates['role'] = role;
    if (phoneNumber != null) updates['phone_number'] = phoneNumber;
    if (password != null && password.isNotEmpty) updates['password'] = password;
    if (isActive != null) updates['is_active'] = isActive;
    final result = await _invokeAuth(updates);
    return result?['employee'] is Map;
  }

  Future<bool> changePassword(String id, String newPassword) async {
    final result = await _invokeAuth({
      'action': 'change_password',
      'id': id,
      'password': newPassword,
    });
    return result?['success'] == true;
  }

  void clearSession() {
    try {
      html.window.sessionStorage.remove(_sessionTokenKey);
      html.window.localStorage.remove(_sessionTokenKey);
      html.window.localStorage.remove('remembered_employee_id');
      html.window.localStorage.remove('remember_me_enabled');
    } catch (_) {}
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Supply these at build time so they are not hardcoded in Dart source.
  // NOTE: Flutter web embeds compile-time values in the built app; this does
  // not make the URL or publishable/anon key secret from browser DevTools.
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
    throw StateError(
      'Missing Supabase configuration. Build with '
          '--dart-define=SUPABASE_URL=... and '
          '--dart-define=SUPABASE_PUBLISHABLE_KEY=...',
    );
  }

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabasePublishableKey,
  );

  runApp(const MyApp());
}

class AutoRefreshManager extends StatefulWidget {
  final Widget child;

  const AutoRefreshManager({
    super.key,
    required this.child,
  });

  @override
  State<AutoRefreshManager> createState() => _AutoRefreshManagerState();
}

class _AutoRefreshManagerState extends State<AutoRefreshManager> {
  Timer? _refreshTimer;
  Timer? _countdownTimer;

  bool _showWarning = false;
  int _secondsLeft = 30;

  @override
  void initState() {
    super.initState();

    // Show the refresh warning after 1 hours.
    _refreshTimer = Timer(
      const Duration(hours: 1),
      _showRefreshWarning,
    );
  }

  void _showRefreshWarning() {
    if (!mounted) return;

    setState(() {
      _showWarning = true;
      _secondsLeft = 30;
    });

    _countdownTimer?.cancel();

    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
          (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (_secondsLeft <= 1) {
          timer.cancel();

          // Full browser/page refresh.
          html.window.location.reload();
          return;
        }

        setState(() {
          _secondsLeft--;
        });
      },
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,

        // Refresh warning.
        if (_showWarning)
          Positioned(
            top: 20,
            right: 20,
            child: Material(
              elevation: 10,
              borderRadius: BorderRadius.circular(12),
              color: Theme.of(context).cardColor,
              child: Container(
                width: 340,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.orange,
                    width: 1.5,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 15,
                      spreadRadius: 1,
                      offset: Offset(0, 5),
                      color: Colors.black26,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.refresh,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Page Refresh Required',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    Text(
                      'This page will refresh automatically to load the latest version.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.8),
                      ),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      'Refreshing in $_secondsLeft seconds...',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface,
                      ),
                    ),

                    const SizedBox(height: 10),

                    LinearProgressIndicator(
                      value: _secondsLeft / 30,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}


/*
flutter clean
flutter pub get
flutter build web --release
git add .
git commit -m "Update"
git push

*/
