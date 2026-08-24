// lib/pages/login_page.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobitem/pages/main_shell.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_html/html.dart' as html;
import '../main.dart';
import '../services/sap_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _supabase = Supabase.instance.client;
  late final EmployeeAuthService _authService;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  bool _rememberMe = false;

  // Theme helper getters
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _cardColor => _isDark ? const Color(0xFF1E293B) : Colors.white;
  Color get _textColor => _isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);
  Color get _secondaryTextColor => _isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600;
  Color get _borderColor => _isDark ? const Color(0xFF334155) : Colors.grey.shade300;
  Color get _inputFillColor => _isDark ? const Color(0xFF1E293B) : Colors.white;

  @override
  void initState() {
    super.initState();
    _authService = EmployeeAuthService(_supabase);
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _loadSavedCredentials() {
    try {
      final savedUsername = html.window.localStorage['remembered_username'];
      final savedPassword = html.window.localStorage['remembered_password'];
      if (savedUsername != null && savedPassword != null) {
        _usernameController.text = savedUsername;
        _passwordController.text = savedPassword;
        // Auto login if credentials are saved
        _signIn();
      }
    } catch (e) {
      print('Error loading credentials: $e');
    }
  }

  void _saveCredentials(String username, String password) {
    try {
      // Always save credentials (automatic remember me)
      html.window.localStorage['remembered_username'] = username;
      html.window.localStorage['remembered_password'] = password;
    } catch (e) {
      print('Error saving credentials: $e');
    }
  }

  Future<void> _signIn() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    print('🔐 Attempting login: $username');

    if (username.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please enter username and password');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final employee = await _authService.login(username, password);

      print('Login result: ${employee?.fullName ?? "FAILED"}');

      if (employee != null && mounted) {
        // Save credentials if remember me is checked
        _saveCredentials(username, password);

        _setLoggedInEmployee(employee);

        final sapService = SAPMainService(_supabase);

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => MainShell(
              sapService: sapService,
              loggedInEmployee: employee,
            ),
          ),
        );
      } else {
        setState(() {
          _errorMessage = 'Invalid username or password';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Login exception: $e');
      setState(() {
        _errorMessage = 'An error occurred. Please try again.';
        _isLoading = false;
      });
    }
  }

  void _setLoggedInEmployee(EmployeeAuth employee) {
    // You can store this in a global state or pass it around
    print('Logged in: ${employee.fullName} (${employee.role})');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _isDark
                ? [
              const Color(0xFF0F172A),
              const Color(0xFF1E293B),
              const Color(0xFF0F172A),
            ]
                : [
              const Color(0xFF0F172A),
              const Color(0xFF1E293B),
              const Color(0xFF0F172A),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.factory,
                      size: 45,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Title
                  Text(
                    'MOBICA Workers',
                    style: GoogleFonts.cairo(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Sign in with your account',
                    style: GoogleFonts.cairo(
                      fontSize: 15,
                      color: Colors.white.withOpacity(0.85),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Login Card
                  Container(
                    width: 420,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: _cardColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: _isDark
                              ? Colors.black.withOpacity(0.3)
                              : Colors.black.withOpacity(0.15),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome Back',
                          style: GoogleFonts.cairo(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: _textColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Enter your credentials to continue',
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            color: _secondaryTextColor,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Error message
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _isDark
                                  ? Colors.red.withOpacity(0.1)
                                  : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _isDark
                                    ? Colors.red.withOpacity(0.3)
                                    : Colors.red.shade200,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: _isDark
                                      ? Colors.red.shade300
                                      : Colors.red.shade700,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: GoogleFonts.cairo(
                                      fontSize: 13,
                                      color: _isDark
                                          ? Colors.red.shade300
                                          : Colors.red.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Username Field
                        TextField(
                          controller: _usernameController,
                          style: GoogleFonts.cairo(color: _textColor),
                          decoration: InputDecoration(
                            labelText: 'Username',
                            labelStyle: GoogleFonts.cairo(color: _secondaryTextColor),
                            hintText: 'Enter your username',
                            hintStyle: GoogleFonts.cairo(fontSize: 14, color: _secondaryTextColor),
                            prefixIcon: Icon(Icons.person_outline, color: _secondaryTextColor),
                            filled: true,
                            fillColor: _inputFillColor,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: _borderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: _isDark ? const Color(0xFF60A5FA) : const Color(0xFF0F172A),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Password Field
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: GoogleFonts.cairo(color: _textColor),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            labelStyle: GoogleFonts.cairo(color: _secondaryTextColor),
                            hintText: 'Enter your password',
                            hintStyle: GoogleFonts.cairo(fontSize: 14, color: _secondaryTextColor),
                            prefixIcon: Icon(Icons.lock_outline, color: _secondaryTextColor),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                color: _secondaryTextColor,
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                            filled: true,
                            fillColor: _inputFillColor,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: _borderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: _isDark ? const Color(0xFF60A5FA) : const Color(0xFF0F172A),
                                width: 2,
                              ),
                            ),
                          ),
                          onSubmitted: (_) => _signIn(),
                        ),
                        const SizedBox(height: 24),

                        // Sign In Button
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _signIn,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isDark ? const Color(0xFF60A5FA) : const Color(0xFF0F172A),
                              foregroundColor: _isDark ? const Color(0xFF0F172A) : Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                              disabledBackgroundColor: _isDark
                                  ? const Color(0xFF60A5FA).withOpacity(0.5)
                                  : const Color(0xFF0F172A).withOpacity(0.5),
                            ),
                            child: _isLoading
                                ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _isDark ? const Color(0xFF0F172A) : Colors.white,
                              ),
                            )
                                : Text(
                              'Sign In',
                              style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '© 2026 MOBICA. All rights reserved.',
                    style: GoogleFonts.cairo(fontSize: 12, color: Colors.white.withOpacity(0.6)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
