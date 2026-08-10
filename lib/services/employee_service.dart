// lib/services/employee_service.dart
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/employee_model.dart';

class EmployeeService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Create new employee - Fixed version
  Future<Employee?> createEmployee({
    required String email,
    required String password,
    required String name,
    required String department,
    required String role,
    String? phoneNumber,
  }) async {
    try {
      // Step 1: Sign up the user (this works with anon key)
      final authResponse = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'name': name,
          'role': role,
        },
      );

      if (authResponse.user == null) {
        throw Exception('Failed to create auth user');
      }

      // Step 2: Create employee profile using the user's ID
      // Note: This requires RLS policies to allow insert
      final employeeData = {
        'id': authResponse.user!.id,
        'email': email,
        'name': name,
        'department': department,
        'role': role,
        'phone_number': phoneNumber,
        'is_active': true,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      final response = await _supabase
          .from('employees')
          .insert(employeeData)
          .select()
          .single();

      return Employee.fromJson(response);
    } catch (e) {
      print('Error creating employee: $e');
      // Show more detailed error
      if (e is AuthException) {
        print('Auth error: ${e.message}');
      }
      return null;
    }
  }

  // Get all employees
  Future<List<Employee>> getEmployees({
    String? department,
    String? role,
    bool? isActive,
  }) async {
    try {
      var query = _supabase.from('employees').select();

      if (department != null) {
        query = query.eq('department', department);
      }
      if (role != null) {
        query = query.eq('role', role);
      }
      if (isActive != null) {
        query = query.eq('is_active', isActive);
      }

      final response = await query.order('name');

      return response.map<Employee>((json) => Employee.fromJson(json)).toList();
    } catch (e) {
      print('Error fetching employees: $e');
      return [];
    }
  }

  // Get current logged-in employee
  Future<Employee?> getCurrentEmployee() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;

      final response = await _supabase
          .from('employees')
          .select()
          .eq('id', user.id)
          .single();

      return Employee.fromJson(response);
    } catch (e) {
      print('Error fetching current employee: $e');
      return null;
    }
  }

  // Get employee by ID
  Future<Employee?> getEmployeeById(String id) async {
    try {
      final response = await _supabase
          .from('employees')
          .select()
          .eq('id', id)
          .single();

      return Employee.fromJson(response);
    } catch (e) {
      print('Error fetching employee: $e');
      return null;
    }
  }

  // Update employee
  Future<bool> updateEmployee({
    required String id,
    String? name,
    String? department,
    String? role,
    String? phoneNumber,
    bool? isActive,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (name != null) updates['name'] = name;
      if (department != null) updates['department'] = department;
      if (role != null) updates['role'] = role;
      if (phoneNumber != null) updates['phone_number'] = phoneNumber;
      if (isActive != null) updates['is_active'] = isActive;

      await _supabase
          .from('employees')
          .update(updates)
          .eq('id', id);

      return true;
    } catch (e) {
      print('Error updating employee: $e');
      return false;
    }
  }

  // Update employee profile image
  Future<String?> uploadProfileImage(String employeeId, String filePath) async {
    try {
      final file = await _supabase.storage
          .from('avatars')
          .upload('$employeeId/profile.jpg', filePath as File);

      final imageUrl = _supabase.storage
          .from('avatars')
          .getPublicUrl('$employeeId/profile.jpg');

      await updateEmployee(id: employeeId);

      // You might want to add a profile_image_url field update here

      return imageUrl;
    } catch (e) {
      print('Error uploading profile image: $e');
      return null;
    }
  }

  // Deactivate employee (soft delete)
  Future<bool> deactivateEmployee(String id) async {
    return await updateEmployee(id: id, isActive: false);
  }

  // Assign job to employee
  Future<bool> assignJob({
    required String productCode,
    required String productName,
    required String employeeId,
    required String employeeName,
    required String stageName,
    DateTime? dueDate,
    String? notes,
  }) async {
    try {
      final jobData = {
        'product_code': productCode,
        'product_name': productName,
        'employee_id': employeeId,
        'employee_name': employeeName,
        'stage_name': stageName,
        'status': 'pending',
        'assigned_date': DateTime.now().toIso8601String(),
        'due_date': dueDate?.toIso8601String(),
        'notes': notes,
        'progress': 0,
      };

      await _supabase.from('job_assignments').insert(jobData);
      return true;
    } catch (e) {
      print('Error assigning job: $e');
      return false;
    }
  }

  // Get employee jobs
  Future<List<JobAssignment>> getEmployeeJobs(String employeeId) async {
    try {
      final response = await _supabase
          .from('job_assignments')
          .select()
          .eq('employee_id', employeeId)
          .order('assigned_date', ascending: false);

      return response
          .map<JobAssignment>((json) => JobAssignment.fromJson(json))
          .toList();
    } catch (e) {
      print('Error fetching employee jobs: $e');
      return [];
    }
  }

  // Update job status
  Future<bool> updateJobStatus({
    required String jobId,
    required String status,
    int? progress,
    String? notes,
  }) async {
    try {
      final updates = <String, dynamic>{
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (progress != null) updates['progress'] = progress;
      if (notes != null) updates['notes'] = notes;

      if (status == 'completed') {
        updates['completed_date'] = DateTime.now().toIso8601String();
        updates['progress'] = 100;
      }

      await _supabase
          .from('job_assignments')
          .update(updates)
          .eq('id', jobId);

      return true;
    } catch (e) {
      print('Error updating job status: $e');
      return false;
    }
  }

  // Get all jobs
  Future<List<JobAssignment>> getAllJobs({
    String? stageName,
    String? status,
    String? employeeId,
  }) async {
    try {
      var query = _supabase.from('job_assignments').select();

      if (stageName != null) {
        query = query.eq('stage_name', stageName);
      }
      if (status != null) {
        query = query.eq('status', status);
      }
      if (employeeId != null) {
        query = query.eq('employee_id', employeeId);
      }

      final response = await query.order('assigned_date', ascending: false);

      return response
          .map<JobAssignment>((json) => JobAssignment.fromJson(json))
          .toList();
    } catch (e) {
      print('Error fetching jobs: $e');
      return [];
    }
  }

  // Search employees
  Future<List<Employee>> searchEmployees(String query) async {
    try {
      final response = await _supabase
          .from('employees')
          .select()
          .or('name.ilike.%$query%,email.ilike.%$query%')
          .order('name');

      return response.map<Employee>((json) => Employee.fromJson(json)).toList();
    } catch (e) {
      print('Error searching employees: $e');
      return [];
    }
  }
}
