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
  Color get _cardColor => _isDark ? const Color(0xFF121212) : Colors.white;
  Color get _textColor => _isDark ? const Color(0xFFF5F5F5) : const Color(0xFF0F172A);
  Color get _secondaryTextColor => _isDark ? const Color(0xFFAAAAAA) : Colors.grey.shade600;
  Color get _borderColor => _isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade300;
  Color get _inputFillColor => _isDark ? const Color(0xFF121212) : Colors.white;

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
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= 900;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _isDark
                ? const [
              Color(0xFF000000),
              Color(0xFF080808),
              Color(0xFF000000),
            ]
                : const [
              Color(0xFF0F172A),
              Color(0xFF1E293B),
              Color(0xFF0F172A),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isWide ? 32 : 20,
                vertical: 28,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: isWide
                    ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: _buildBrandPanel()),
                    const SizedBox(width: 44),
                    SizedBox(
                      width: 430,
                      child: _buildLoginCard(),
                    ),
                  ],
                )
                    : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildBrandPanel(compact: true),
                    const SizedBox(height: 28),
                    _buildLoginCard(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandPanel({bool compact = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
      compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Container(
          width: compact ? 240 : 360,
          height: compact ? 240 : 360,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(26),

            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 34,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Image.asset(
            'assets/images/logo.png',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.business_center_rounded,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(18.0),
        ),
      ],
    );
  }

  Widget _buildLoginCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(30, 30, 30, 26),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: _isDark ? const Color(0xFF2A2A2A) : Colors.white.withOpacity(0.65),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(_isDark ? 0.50 : 0.22),
            blurRadius: 40,
            offset: const Offset(0, 22),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _isDark
                      ? const Color(0xFF1C1C1C)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.lock_person_outlined,
                  color: _isDark ? const Color(0xFFF5F5F5) : const Color(0xFF0F172A),
                  size: 22,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  'Secure Sign In',
                  style: GoogleFonts.cairo(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: _textColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Padding(
            padding: const EdgeInsets.only(left: 57),
            child: Text(
              'Use your MOBICA account to continue.',
              style: GoogleFonts.cairo(
                fontSize: 12.5,
                color: _secondaryTextColor,
              ),
            ),
          ),
          const SizedBox(height: 25),

          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
              decoration: BoxDecoration(
                color: _isDark
                    ? Colors.red.withOpacity(0.09)
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: _isDark
                      ? Colors.red.withOpacity(0.24)
                      : Colors.red.shade200,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: _isDark ? Colors.red.shade300 : Colors.red.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: GoogleFonts.cairo(
                        fontSize: 12.5,
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

          _buildInput(
            controller: _usernameController,
            label: 'Username',
            hint: 'Enter your username',
            icon: Icons.person_outline_rounded,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 15),
          _buildInput(
            controller: _passwordController,
            label: 'Password',
            hint: 'Enter your password',
            icon: Icons.lock_outline_rounded,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            suffix: IconButton(
              tooltip: _obscurePassword ? 'Show password' : 'Hide password',
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: _secondaryTextColor,
                size: 20,
              ),
              onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
            ),
            onSubmitted: (_) => _signIn(),
          ),
          const SizedBox(height: 22),

          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _signIn,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isDark
                    ? const Color(0xFFF5F5F5)
                    : const Color(0xFF0F172A),
                foregroundColor: _isDark
                    ? const Color(0xFF000000)
                    : Colors.white,
                disabledBackgroundColor: _isDark
                    ? const Color(0xFF555555)
                    : const Color(0xFF64748B),
                disabledForegroundColor:
                _isDark ? const Color(0xFFAAAAAA) : Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _isLoading
                    ? SizedBox(
                  key: const ValueKey('loading'),
                  width: 21,
                  height: 21,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: _isDark
                        ? const Color(0xFF000000)
                        : Colors.white,
                  ),
                )
                    : Row(
                  key: const ValueKey('signin'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Sign In',
                      style: GoogleFonts.cairo(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 19,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              '© 2026 MOBICA • Authorized access only',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 10.5,
                color: _secondaryTextColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    TextInputAction? textInputAction,
    Widget? suffix,
    void Function(String)? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: GoogleFonts.cairo(
        color: _textColor,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      cursorColor:
      _isDark ? const Color(0xFFF5F5F5) : const Color(0xFF0F172A),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(
          color: _secondaryTextColor,
          fontSize: 13,
        ),
        hintText: hint,
        hintStyle: GoogleFonts.cairo(
          fontSize: 13,
          color: _secondaryTextColor.withOpacity(0.75),
        ),
        prefixIcon: Icon(icon, color: _secondaryTextColor, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: _inputFillColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 17,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: _isDark
                ? const Color(0xFFF5F5F5)
                : const Color(0xFF0F172A),
            width: 1.5,
          ),
        ),
      ),
    );
  }
}
