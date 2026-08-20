// lib/main.dart
import 'package:flutter/material.dart';
import 'package:mobitem/pages/login_page.dart';
import 'package:mobitem/pages/main_shell.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/sap_service.dart';
import 'pages/orders_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://tcztkkexgzxlurvhibmc.supabase.co',  // Your Supabase URL
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRjenRra2V4Z3p4bHVydmhpYm1jIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMTExNTksImV4cCI6MjEwMTU4NzE1OX0.7XHX0uaC8YzRdd42Str__cyAK8Fpyhs7h-yv2pTaDBQ',           // Your anon key
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'mobica',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F172A),
          brightness: Brightness.light,
          primary: const Color(0xFF0F172A),
          surface: const Color(0xFFF8FAFC),
          background: const Color(0xFFF8FAFC),
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        fontFamily: GoogleFonts.cairo().fontFamily,
        useMaterial3: true,
        textTheme: GoogleFonts.cairoTextTheme(
          Theme.of(context).textTheme,
        ),
      ),
      builder: (context, child) {
        final screenWidth = MediaQuery.of(context).size.width;

        // Force desktop scale using responsive_framework whenever screen width is under 1120px
        if (screenWidth < 1120) {
          return ResponsiveScaledBox(
            width: 1120,
            child: child!,
          );
        }

        return child!;
      },
      home: const LoginPage(),
    );
  }
}

class EmployeeAuthService {
  final SupabaseClient _client;

  EmployeeAuthService(this._client);

  // Login with username and password
  // lib/services/employee_auth_service.dart

  Future<EmployeeAuth?> login(String username, String password) async {
    try {
      final response = await _client
          .from('employees_auth')
          .select('*')
          .eq('username', username)
          .eq('password', password)
          .eq('is_active', true);

      // response is always a List from Supabase select()
      if (response == null || (response is List && response.isEmpty)) {
        print('No employee found with username: $username');
        return null;
      }

      final data = (response as List).first as Map<String, dynamic>;

      // Update last login
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
  }  // Get all active employees
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

  // Get employee by ID
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

  // Add new employee
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

  // Update employee
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

  // Change password
  Future<bool> changePassword(String id, String newPassword) async {
    return updateEmployee(id: id, password: newPassword);
  }
}

/*

flutter pub get
flutter build web --release
git add .
git commit -m "Update"
git push


*/
