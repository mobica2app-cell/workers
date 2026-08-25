// lib/main.dart
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
          title: 'mobica',
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
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              child: content,
            );

            // Scale down to 1120px desktop width when viewed on screens smaller than 1120px
            if (screenWidth < 1120) {
              content = ResponsiveScaledBox(
                width: 680,
                child: content,
              );
            }

            return SmartZoomWrapper(child: content);
          },
          home: const LoginPage(),
        );
      },
    );
  }

  // Light Theme
  ThemeData _buildLightTheme() {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F172A),
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
      seedColor: const Color(0xFF0F172A),
      brightness: Brightness.dark,
      primary: const Color(0xFF60A5FA),
      secondary: const Color(0xFF3B82F6),
      surface: const Color(0xFF1E293B),
      background: const Color(0xFF0F172A),
      error: const Color(0xFFEF4444),
      onPrimary: const Color(0xFF0F172A),
      onSecondary: const Color(0xFFFFFFFF),
      onSurface: const Color(0xFFE2E8F0),
      onBackground: const Color(0xFFE2E8F0),
      onError: const Color(0xFFFFFFFF),
    );

    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF0F172A),
      fontFamily: GoogleFonts.cairo().fontFamily,
      useMaterial3: true,
      textTheme: GoogleFonts.cairoTextTheme(
        ThemeData.dark().textTheme,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1E293B),
        foregroundColor: Color(0xFFE2E8F0),
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF1E293B),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E293B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF334155)),
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
        color: const Color(0xFF1E293B),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF334155),
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
  bool _isZPressed = false;
  bool _isTouchDevice = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool canZoom = _isTouchDevice || _isZPressed;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        final isZDown = HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.keyZ);
        if (isZDown != _isZPressed) {
          setState(() {
            _isZPressed = isZDown;
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

  EmployeeAuthService(this._client);

  Future<EmployeeAuth?> login(String username, String password) async {
    try {
      final response = await _client
          .from('employees_auth')
          .select('*')
          .eq('username', username)
          .eq('password', password)
          .eq('is_active', true);

      if (response == null || (response is List && response.isEmpty)) {
        print('No employee found with username: $username');
        return null;
      }

      final data = (response as List).first as Map<String, dynamic>;

      await _client
          .from('employees_auth')
          .update({'last_login': DateTime.now().toIso8601String()})
          .eq('id', data['id']);

      print('Login successful: ${data['full_name']}');
      return EmployeeAuth.fromJson(data);
    } catch (e) {
      print('Login error: $e');
      return null;
    }
  }

  Future<List<EmployeeAuth>> getAllEmployees() async {
    try {
      final response = await _client
          .from('employees_auth')
          .select('*')
          .eq('is_active', true)
          .order('full_name');

      return (response as List)
          .map((json) => EmployeeAuth.fromJson(json))
          .toList();
    } catch (e) {
      print('Error fetching employees: $e');
      return [];
    }
  }

  Future<EmployeeAuth?> getEmployeeById(String id) async {
    try {
      final response = await _client
          .from('employees_auth')
          .select('*')
          .eq('id', id)
          .single();

      return EmployeeAuth.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  Future<bool> addEmployee({
    required String username,
    required String password,
    required String fullName,
    String? department,
    String? role,
    String? phoneNumber,
  }) async {
    try {
      await _client.from('employees_auth').insert({
        'username': username,
        'password': password,
        'full_name': fullName,
        'department': department,
        'role': role,
        'phone_number': phoneNumber,
        'is_active': true,
      });
      return true;
    } catch (e) {
      print('Error adding employee: $e');
      return false;
    }
  }

  Future<bool> updateEmployee({
    required String id,
    String? fullName,
    String? department,
    String? role,
    String? phoneNumber,
    String? password,
    bool? isActive,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (fullName != null) updates['full_name'] = fullName;
      if (department != null) updates['department'] = department;
      if (role != null) updates['role'] = role;
      if (phoneNumber != null) updates['phone_number'] = phoneNumber;
      if (password != null) updates['password'] = password;
      if (isActive != null) updates['is_active'] = isActive;

      await _client.from('employees_auth').update(updates).eq('id', id);
      return true;
    } catch (e) {
      print('Error updating employee: $e');
      return false;
    }
  }

  Future<bool> changePassword(String id, String newPassword) async {
    return updateEmployee(id: id, password: newPassword);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://tcztkkexgzxlurvhibmc.supabase.co',  // Your Supabase URL
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRjenRra2V4Z3p4bHVydmhpYm1jIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMTExNTksImV4cCI6MjEwMTU4NzE1OX0.7XHX0uaC8YzRdd42Str__cyAK8Fpyhs7h-yv2pTaDBQ',           // Your anon key
  );

  runApp(const MyApp());
}


/*
flutter pub get
flutter build web --release
git add .
git commit -m "Update"
git push

*/
