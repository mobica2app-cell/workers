// lib/pages/department_tracking_page.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../services/sap_service.dart';

class DepartmentTrackingPage extends StatefulWidget {
  const DepartmentTrackingPage({Key? key}) : super(key: key);

  @override
  State<DepartmentTrackingPage> createState() => _DepartmentTrackingPageState();
}

class _DepartmentTrackingPageState extends State<DepartmentTrackingPage> {
  final EmployeeAuthService _authService = EmployeeAuthService(Supabase.instance.client);
  final SAPMainService _sapService = SAPMainService(Supabase.instance.client);

  List<EmployeeAuth> _allEmployees = [];
  List<SAPMainOrder> _allOrders = [];
  Map<String, List<EmployeeAuth>> _departmentsMap = {};
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final employees = await _authService.getAllEmployees();
      final orders = await _sapService.getAllOrders();

      // Group employees by department
      final deptMap = <String, List<EmployeeAuth>>{};
      for (var emp in employees) {
        final dept = emp.department ?? 'No Department';
        deptMap.putIfAbsent(dept, () => []).add(emp);
      }

      setState(() {
        _allEmployees = employees;
        _allOrders = orders;
        _departmentsMap = deptMap;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading departments: $e');
      setState(() => _isLoading = false);
    }
  }

  // Get workload for an employee
  int _getEmployeeWorkload(EmployeeAuth employee) {
    int count = 0;
    for (var order in _allOrders) {
      if (order.responsibleEngineer == employee.fullName ||
          order.reviewer == employee.fullName ||
          order.correspondenceEngineer == employee.fullName) {
        count++;
      }
    }
    return count;
  }

  // Get completed work for an employee
  int _getEmployeeCompleted(EmployeeAuth employee) {
    int count = 0;
    for (var order in _allOrders) {
      if ((order.responsibleEngineer == employee.fullName ||
          order.reviewer == employee.fullName ||
          order.correspondenceEngineer == employee.fullName) &&
          (order.status == 'Done' || order.status == 'completed')) {
        count++;
      }
    }
    return count;
  }

  // Get department color
  Color _getDepartmentColor(String department) {
    switch (department) {
      case 'Technical Office': return Colors.blue;
      case 'Projects Design': return Colors.purple;
      case 'Sofa Section': return Colors.orange;
      case 'Product Section': return Colors.teal;
      case 'Partation Section': return Colors.indigo;
      case 'Cladding Section': return Colors.brown;
      case 'Solid Work Section': return Colors.pink;
      case 'Data Entry': return Colors.cyan;
      case 'Management': return Colors.deepOrange;
      default: return Colors.grey;
    }
  }

  IconData _getDepartmentIcon(String department) {
    switch (department) {
      case 'Technical Office': return Icons.engineering;
      case 'Projects Design': return Icons.design_services;
      case 'Sofa Section': return Icons.chair;
      case 'Product Section': return Icons.inventory_2;
      case 'Partation Section': return Icons.grid_view;
      case 'Cladding Section': return Icons.layers;
      case 'Solid Work Section': return Icons.architecture;
      case 'Data Entry': return Icons.keyboard;
      case 'Management': return Icons.business;
      default: return Icons.business;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text('Departments', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // Search
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              style: GoogleFonts.cairo(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search departments...',
                hintStyle: GoogleFonts.cairo(color: Colors.grey),
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // Department list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _departmentsMap.length,
              itemBuilder: (context, index) {
                final dept = _departmentsMap.keys.elementAt(index);
                final employees = _departmentsMap[dept] ?? [];

                if (_searchQuery.isNotEmpty &&
                    !dept.toLowerCase().contains(_searchQuery.toLowerCase())) {
                  return const SizedBox.shrink();
                }

                return _buildDepartmentCard(dept, employees);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentCard(String department, List<EmployeeAuth> employees) {
    final color = _getDepartmentColor(department);
    final totalWorkload = employees.fold(0, (sum, emp) => sum + _getEmployeeWorkload(emp));
    final totalCompleted = employees.fold(0, (sum, emp) => sum + _getEmployeeCompleted(emp));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.3)),
      ),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(_getDepartmentIcon(department), color: color, size: 24),
        ),
        title: Text(
          department,
          style: GoogleFonts.cairo(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF0F172A),
          ),
        ),
        subtitle: Row(
          children: [
            _buildBadge('${employees.length} Employees', color),
            const SizedBox(width: 8),
            _buildBadge('$totalWorkload Tasks', Colors.blue),
            const SizedBox(width: 8),
            _buildBadge('$totalCompleted Done', Colors.green),
          ],
        ),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const SizedBox(height: 8),
          // Employees in this department
          ...employees.map((emp) => _buildEmployeeTile(emp, color)),
        ],
      ),
    );
  }

  Widget _buildEmployeeTile(EmployeeAuth employee, Color deptColor) {
    final workload = _getEmployeeWorkload(employee);
    final completed = _getEmployeeCompleted(employee);
    final progress = workload > 0 ? (completed / workload * 100).round() : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: deptColor.withOpacity(0.2),
            child: Text(
              employee.initials,
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: deptColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      employee.fullName,
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    if (employee.role != null) ...[
                      const SizedBox(width: 8),
                      _buildBadge(employee.role!, Colors.purple),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress / 100,
                    backgroundColor: Colors.grey.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(deptColor),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$workload tasks',
                style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              Text(
                '$completed done',
                style: GoogleFonts.cairo(fontSize: 10, color: Colors.green),
              ),
            ],
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
}