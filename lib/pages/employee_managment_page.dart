// lib/pages/employee_management_page.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../services/sap_service.dart';

class EmployeeManagementPage extends StatefulWidget {
  const EmployeeManagementPage({Key? key}) : super(key: key);

  @override
  State<EmployeeManagementPage> createState() => _EmployeeManagementPageState();
}

class _EmployeeManagementPageState extends State<EmployeeManagementPage> {
  final EmployeeAuthService _authService = EmployeeAuthService(
    Supabase.instance.client,
  );
  List<EmployeeAuth> _employees = [];
  bool _isLoading = false;
  String _searchQuery = '';
  String? _filterDepartment;
  String? _filterRole;

  // Theme helper getters
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _backgroundColor => _isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get _surfaceColor => _isDark ? const Color(0xFF1E293B) : Colors.white;
  Color get _textColor => _isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);
  Color get _secondaryTextColor => _isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  Color get _borderColor => _isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  Color get _cardColor => _isDark ? const Color(0xFF1E293B) : Colors.white;

  // Get unique departments and roles from data
  List<String> get _departments {
    final depts = _employees
        .map((e) => e.department)
        .where((d) => d != null && d!.isNotEmpty)
        .toSet();
    return depts.cast<String>().toList()..sort();
  }

  List<String> get _roles {
    final roles = _employees
        .map((e) => e.role)
        .where((r) => r != null && r!.isNotEmpty)
        .toSet();
    return roles.cast<String>().toList()..sort();
  }

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    setState(() => _isLoading = true);
    try {
      var employees = await _authService.getAllEmployees();

      // Apply filters
      if (_filterDepartment != null) {
        employees = employees
            .where((e) => e.department == _filterDepartment)
            .toList();
      }
      if (_filterRole != null) {
        employees = employees.where((e) => e.role == _filterRole).toList();
      }

      setState(() {
        _employees = employees;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading employees: $e');
      setState(() => _isLoading = false);
    }
  }

  void _showAddEmployeeDialog() {
    final nameController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final phoneController = TextEditingController();
    String selectedDepartment = _departments.isNotEmpty
        ? _departments.first
        : '';
    String selectedRole = _roles.isNotEmpty ? _roles.first : '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _surfaceColor,
          title: Text(
            'Add New Employee',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w600, color: _textColor),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  style: GoogleFonts.cairo(color: _textColor),
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    labelStyle: GoogleFonts.cairo(color: _secondaryTextColor),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: usernameController,
                  style: GoogleFonts.cairo(color: _textColor),
                  decoration: InputDecoration(
                    labelText: 'Username',
                    labelStyle: GoogleFonts.cairo(color: _secondaryTextColor),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  style: GoogleFonts.cairo(color: _textColor),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: GoogleFonts.cairo(color: _secondaryTextColor),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  style: GoogleFonts.cairo(color: _textColor),
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    labelStyle: GoogleFonts.cairo(color: _secondaryTextColor),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                // Department Dropdown
                DropdownButtonFormField<String>(
                  value: _departments.contains(selectedDepartment)
                      ? selectedDepartment
                      : null,
                  decoration: InputDecoration(
                    labelText: 'Department',
                    labelStyle: GoogleFonts.cairo(color: _secondaryTextColor),
                    border: const OutlineInputBorder(),
                  ),
                  items: _departments
                      .map(
                        (dept) => DropdownMenuItem(
                      value: dept,
                      child: Text(dept, style: GoogleFonts.cairo(color: _textColor)),
                    ),
                  )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => selectedDepartment = value ?? ''),
                ),
                const SizedBox(height: 12),
                // Role Dropdown
                DropdownButtonFormField<String>(
                  value: _roles.contains(selectedRole) ? selectedRole : null,
                  decoration: InputDecoration(
                    labelText: 'Role',
                    labelStyle: GoogleFonts.cairo(color: _secondaryTextColor),
                    border: const OutlineInputBorder(),
                  ),
                  items: _roles
                      .map(
                        (role) => DropdownMenuItem(
                      value: role,
                      child: Text(role, style: GoogleFonts.cairo(color: _textColor)),
                    ),
                  )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => selectedRole = value ?? ''),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: GoogleFonts.cairo(color: _secondaryTextColor)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty ||
                    usernameController.text.isEmpty ||
                    passwordController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Please fill all required fields',
                        style: GoogleFonts.cairo(),
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                if (passwordController.text.length < 4) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Password must be at least 4 characters',
                        style: GoogleFonts.cairo(),
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                final success = await _authService.addEmployee(
                  username: usernameController.text.trim(),
                  password: passwordController.text,
                  fullName: nameController.text.trim(),
                  department: selectedDepartment.isNotEmpty
                      ? selectedDepartment
                      : null,
                  role: selectedRole.isNotEmpty ? selectedRole : null,
                  phoneNumber: phoneController.text.isNotEmpty
                      ? phoneController.text.trim()
                      : null,
                );

                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        success
                            ? 'Employee created!'
                            : 'Failed to create employee',
                        style: GoogleFonts.cairo(),
                      ),
                      backgroundColor: success ? Colors.green : Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  if (success) _loadEmployees();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
              ),
              child: Text(
                'Create',
                style: GoogleFonts.cairo(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditEmployeeDialog(EmployeeAuth employee) {
    final nameController = TextEditingController(text: employee.fullName);
    final usernameController = TextEditingController(text: employee.username);
    final phoneController = TextEditingController(
      text: employee.phoneNumber ?? '',
    );
    String selectedDepartment = employee.department ?? '';
    String selectedRole = employee.role ?? '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _surfaceColor,
          title: Text(
            'Edit Employee',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w600, color: _textColor),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  style: GoogleFonts.cairo(color: _textColor),
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    labelStyle: GoogleFonts.cairo(color: _secondaryTextColor),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: usernameController,
                  enabled: false,
                  style: GoogleFonts.cairo(color: _secondaryTextColor),
                  decoration: InputDecoration(
                    labelText: 'Username',
                    labelStyle: GoogleFonts.cairo(color: _secondaryTextColor),
                    border: const OutlineInputBorder(),
                    disabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: _borderColor),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  style: GoogleFonts.cairo(color: _textColor),
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    labelStyle: GoogleFonts.cairo(color: _secondaryTextColor),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _departments.contains(selectedDepartment)
                      ? selectedDepartment
                      : null,
                  decoration: InputDecoration(
                    labelText: 'Department',
                    labelStyle: GoogleFonts.cairo(color: _secondaryTextColor),
                    border: const OutlineInputBorder(),
                  ),
                  items: _departments
                      .map(
                        (dept) => DropdownMenuItem(
                      value: dept,
                      child: Text(dept, style: GoogleFonts.cairo(color: _textColor)),
                    ),
                  )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => selectedDepartment = value ?? ''),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _roles.contains(selectedRole) ? selectedRole : null,
                  decoration: InputDecoration(
                    labelText: 'Role',
                    labelStyle: GoogleFonts.cairo(color: _secondaryTextColor),
                    border: const OutlineInputBorder(),
                  ),
                  items: _roles
                      .map(
                        (role) => DropdownMenuItem(
                      value: role,
                      child: Text(role, style: GoogleFonts.cairo(color: _textColor)),
                    ),
                  )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => selectedRole = value ?? ''),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: GoogleFonts.cairo(color: _secondaryTextColor)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Name is required',
                        style: GoogleFonts.cairo(),
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                final success = await _authService.updateEmployee(
                  id: employee.id,
                  fullName: nameController.text.trim(),
                  department: selectedDepartment.isNotEmpty
                      ? selectedDepartment
                      : null,
                  role: selectedRole.isNotEmpty ? selectedRole : null,
                  phoneNumber: phoneController.text.isNotEmpty
                      ? phoneController.text.trim()
                      : null,
                );
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        success ? 'Employee updated!' : 'Failed to update',
                        style: GoogleFonts.cairo(),
                      ),
                      backgroundColor: success ? Colors.green : Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  if (success) _loadEmployees();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
              ),
              child: Text(
                'Update',
                style: GoogleFonts.cairo(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: Text(
          'Employee Management',
          style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: _showAddEmployeeDialog,
            tooltip: 'Add Employee',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filters
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (value) => setState(() => _searchQuery = value),
                    style: GoogleFonts.cairo(color: _textColor),
                    decoration: InputDecoration(
                      hintText: 'Search employees...',
                      hintStyle: GoogleFonts.cairo(color: _secondaryTextColor),
                      prefixIcon: Icon(Icons.search, color: _secondaryTextColor),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _filterDepartment,
                  hint: Text('Department', style: GoogleFonts.cairo(color: _secondaryTextColor)),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(
                        'All Departments',
                        style: GoogleFonts.cairo(color: _textColor),
                      ),
                    ),
                    ..._departments.map(
                          (dept) => DropdownMenuItem(
                        value: dept,
                        child: Text(dept, style: GoogleFonts.cairo(color: _textColor)),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _filterDepartment = value);
                    _loadEmployees();
                  },
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _filterRole,
                  hint: Text('Role', style: GoogleFonts.cairo(color: _secondaryTextColor)),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text('All Roles', style: GoogleFonts.cairo(color: _textColor)),
                    ),
                    ..._roles.map(
                          (role) => DropdownMenuItem(
                        value: role,
                        child: Text(role, style: GoogleFonts.cairo(color: _textColor)),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _filterRole = value);
                    _loadEmployees();
                  },
                ),
              ],
            ),
          ),
          // Employee List
          Expanded(
            child: _isLoading
                ? Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              ),
            )
                : _employees.isEmpty
                ? Center(
              child: Text(
                'No employees found',
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  color: _secondaryTextColor,
                ),
              ),
            )
                : ListView.builder(
              itemCount: _employees.length,
              itemBuilder: (context, index) {
                final employee = _employees[index];
                if (_searchQuery.isNotEmpty &&
                    !employee.fullName.toLowerCase().contains(
                      _searchQuery.toLowerCase(),
                    ) &&
                    !employee.username.toLowerCase().contains(
                      _searchQuery.toLowerCase(),
                    )) {
                  return const SizedBox.shrink();
                }
                return _buildEmployeeCard(employee);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeCard(EmployeeAuth employee) {
    return Card(
      color: _cardColor,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getDepartmentColor(employee.department),
          child: Text(
            employee.initials,
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        title: Text(
          employee.fullName,
          style: GoogleFonts.cairo(fontWeight: FontWeight.w600, color: _textColor),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(employee.username, style: GoogleFonts.cairo(fontSize: 12, color: _secondaryTextColor)),
            const SizedBox(height: 4),
            Row(
              children: [
                if (employee.department != null) ...[
                  _buildBadge(employee.department!, Colors.blue),
                  const SizedBox(width: 8),
                ],
                if (employee.role != null)
                  _buildBadge(employee.role!, Colors.purple),
                if (!employee.isActive) ...[
                  const SizedBox(width: 8),
                  _buildBadge('Inactive', Colors.red),
                ],
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'edit':
                _showEditEmployeeDialog(employee);
                break;
              case 'toggle_active':
                _authService
                    .updateEmployee(
                  id: employee.id,
                  isActive: !employee.isActive,
                )
                    .then((_) => _loadEmployees());
                break;
              case 'reset_password':
                _showResetPasswordDialog(employee);
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  const Icon(Icons.edit, size: 20, color: Colors.orange),
                  const SizedBox(width: 8),
                  Text('Edit', style: GoogleFonts.cairo(color: _textColor)),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'reset_password',
              child: Row(
                children: [
                  const Icon(Icons.lock_reset, size: 20, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text('Reset Password', style: GoogleFonts.cairo(color: _textColor)),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'toggle_active',
              child: Row(
                children: [
                  Icon(
                    employee.isActive ? Icons.block : Icons.check_circle,
                    size: 20,
                    color: employee.isActive ? Colors.red : Colors.green,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    employee.isActive ? 'Deactivate' : 'Activate',
                    style: GoogleFonts.cairo(color: _textColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showResetPasswordDialog(EmployeeAuth employee) {
    final passwordController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceColor,
        title: Text(
          'Reset Password',
          style: GoogleFonts.cairo(fontWeight: FontWeight.w600, color: _textColor),
        ),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          style: GoogleFonts.cairo(color: _textColor),
          decoration: InputDecoration(
            labelText: 'New Password',
            labelStyle: GoogleFonts.cairo(color: _secondaryTextColor),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.cairo(color: _secondaryTextColor)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (passwordController.text.length < 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Password must be at least 4 characters',
                      style: GoogleFonts.cairo(),
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              final success = await _authService.changePassword(
                employee.id,
                passwordController.text,
              );
              if (mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success ? 'Password reset!' : 'Failed',
                      style: GoogleFonts.cairo(),
                    ),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
            ),
            child: Text('Reset', style: GoogleFonts.cairo(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: GoogleFonts.cairo(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _getDepartmentColor(String? department) {
    switch (department) {
      case 'Technical Office':
        return Colors.blue;
      case 'Projects Design':
        return Colors.purple;
      case 'Sofa Section':
        return Colors.orange;
      case 'Product Section':
        return Colors.teal;
      case 'Partation Section':
        return Colors.indigo;
      case 'Cladding Section':
        return Colors.brown;
      case 'Solid Work Section':
        return Colors.pink;
      case 'Data Entry':
        return Colors.cyan;
      case 'Management':
        return Colors.deepOrange;
      default:
        return _isDark ? Colors.grey.shade400 : Colors.grey;
    }
  }
}
