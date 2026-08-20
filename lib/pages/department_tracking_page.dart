// lib/pages/department_tracking_page.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mobitem/pages/track_order.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../services/audit_service.dart';
import '../services/sap_service.dart';

class DepartmentTrackingPage extends StatefulWidget {
  const DepartmentTrackingPage({Key? key}) : super(key: key);

  @override
  State<DepartmentTrackingPage> createState() => _DepartmentTrackingPageState();
}

class _DepartmentTrackingPageState extends State<DepartmentTrackingPage> {
  final EmployeeAuthService _authService = EmployeeAuthService(Supabase.instance.client);
  final SAPMainService _sapService = SAPMainService(Supabase.instance.client);
  final AuditService _auditService = AuditService(Supabase.instance.client);

  List<EmployeeAuth> _allEmployees = [];
  List<SAPMainOrder> _allOrders = [];
  List<Map<String, dynamic>> _auditLogs = [];
  Map<String, List<EmployeeAuth>> _departmentsMap = {};
  bool _isLoading = true;
  String _searchQuery = '';
  String _dateFilter = 'all';
  List<Map<String, dynamic>> _filteredAuditLogs = [];

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
      final auditLogs = await _auditService.getRecentChanges(limit: 5000);

      final deptMap = <String, List<EmployeeAuth>>{};
      for (var emp in employees) {
        final dept = emp.department ?? 'No Department';
        deptMap.putIfAbsent(dept, () => []).add(emp);
      }

      setState(() {
        _allEmployees = employees;
        _allOrders = orders;
        _auditLogs = auditLogs;
        _departmentsMap = deptMap;
        _isLoading = false;
      });

      _applyFilters();
    } catch (e) {
      print('Error loading departments: $e');
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredAuditLogs = _auditLogs.where((log) {
        if (_dateFilter != 'all') {
          final changedAt = DateTime.tryParse(log['changed_at'] ?? '');
          if (changedAt == null) return false;

          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final tomorrow = today.add(const Duration(days: 1));
          final weekStart = today.subtract(Duration(days: today.weekday - 1));
          final monthStart = DateTime(now.year, now.month, 1);

          switch (_dateFilter) {
            case 'today':
              return changedAt.isAfter(today) && changedAt.isBefore(tomorrow);
            case 'week':
              return changedAt.isAfter(weekStart) && changedAt.isBefore(tomorrow);
            case 'month':
              return changedAt.isAfter(monthStart) && changedAt.isBefore(tomorrow);
          }
        }
        return true;
      }).where((log) {
        if (_searchQuery.isNotEmpty) {
          final designOrder = log['design_order']?.toString() ?? '';
          return designOrder.toLowerCase().contains(_searchQuery.toLowerCase());
        }
        return true;
      }).toList();
    });
  }

  // Get employee's tasks
  // Get employee's tasks with priority logic (correspondence > responsible)
  // Get employee's tasks with priority logic (correspondence > responsible)
  List<SAPMainOrder> _getEmployeeTasks(EmployeeAuth employee) {
    final assignedOrders = <String, SAPMainOrder>{};

    for (var order in _allOrders) {
      if (order.correspondenceEngineer == employee.fullName) {
        // If correspondence engineer, this is the primary assignment
        assignedOrders[order.id] = order;
      } else if (order.responsibleEngineer == employee.fullName) {
        // Only assign if no correspondence engineer for this specific order (by id)
        if (!assignedOrders.containsKey(order.id)) {
          assignedOrders[order.id] = order;
        }
      }
    }

    return assignedOrders.values.toList();
  }

  // Get completed count for employee
  // Get completed count for employee based on filtered audit logs
  // Get completed count for employee based on filtered audit logs
  int _getEmployeeCompleted(EmployeeAuth employee) {
    // Get order IDs that were changed to "Done" in the filtered period
    final completedOrderIds = <String>{};

    for (var log in _filteredAuditLogs) {
      final fieldName = log['field_name']?.toString() ?? '';
      final newValue = log['new_value']?.toString() ?? '';

      // Check if status changed to Done or completed
      if (fieldName == 'status' && (newValue == 'Done' || newValue == 'completed')) {
        final orderId = log['order_id']?.toString() ?? '';
        if (orderId.isNotEmpty && orderId != 'bulk_delete' && orderId != 'import_batch') {
          completedOrderIds.add(orderId);
        }
      }
    }

    // Count orders assigned to this employee that are in the completed set
    int count = 0;
    for (var order in _allOrders) {
      // Check if this order belongs to this employee
      bool belongsToEmployee = false;

      // Priority: correspondence_engineer first
      if (order.correspondenceEngineer == employee.fullName) {
        belongsToEmployee = true;
      }
      // If no correspondence engineer, check responsible_engineer
      else if (order.responsibleEngineer == employee.fullName) {
        belongsToEmployee = true;
      }

      // Count only if belongs to employee AND order_id is in completed set
      if (belongsToEmployee && completedOrderIds.contains(order.id)) {
        count++;
      }
    }

    return count;
  }

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
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  onChanged: (value) {
                    setState(() => _searchQuery = value);
                    _applyFilters();
                  },
                  style: GoogleFonts.cairo(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search by Design Order ID...',
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildDateFilterChip('All', 'all'),
                    const SizedBox(width: 8),
                    _buildDateFilterChip('Today', 'today'),
                    const SizedBox(width: 8),
                    _buildDateFilterChip('This Week', 'week'),
                    const SizedBox(width: 8),
                    _buildDateFilterChip('This Month', 'month'),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_filteredAuditLogs.length} changes in selected period',
                    style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF64748B)),
                  ),
                ),
              ],
            ),
          ),
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

  Widget _buildDateFilterChip(String label, String value) {
    final isSelected = _dateFilter == value;
    return FilterChip(
      selected: isSelected,
      label: Text(
        label,
        style: GoogleFonts.cairo(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isSelected ? Colors.white : const Color(0xFF334155),
        ),
      ),
      onSelected: (selected) {
        setState(() => _dateFilter = value);
        _applyFilters();
      },
      selectedColor: const Color(0xFF6366F1),
      checkmarkColor: Colors.white,
      backgroundColor: Colors.white,
      side: BorderSide(color: isSelected ? const Color(0xFF6366F1) : Colors.grey.shade300),
    );
  }

  Widget _buildDepartmentCard(String department, List<EmployeeAuth> employees) {
    final color = _getDepartmentColor(department);
    final totalWorkload = employees.fold(0, (sum, emp) => sum + _getEmployeeTasks(emp).length);
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
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(_getDepartmentIcon(department), color: color, size: 24),
        ),
        title: Text(department, style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A))),
        subtitle: Row(children: [
          _buildBadge('${employees.length} Employees', color),
          const SizedBox(width: 8),
          _buildBadge('$totalWorkload Tasks', Colors.blue),
          const SizedBox(width: 8),
          _buildBadge('$totalCompleted Done', Colors.green),
        ]),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const SizedBox(height: 8),
          ...employees.map((emp) => _buildEmployeeTile(emp, color)),
        ],
      ),
    );
  }

  Widget _buildEmployeeTile(EmployeeAuth employee, Color deptColor) {
    final tasks = _getEmployeeTasks(employee);
    final completed = _getEmployeeCompleted(employee);
    final progress = tasks.isNotEmpty ? (completed / tasks.length * 100).round() : 0;

    return GestureDetector(
      onTap: () => _showEmployeeTasks(employee, deptColor),
      child: Container(
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
              child: Text(employee.initials, style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600, color: deptColor)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(employee.fullName, style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A))),
                    if (employee.role != null) ...[
                      const SizedBox(width: 8),
                      _buildBadge(employee.role!, Colors.purple),
                    ],
                  ]),
                  const SizedBox(height: 6),
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
                Text('${tasks.length} tasks', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600)),
                Text('$completed done', style: GoogleFonts.cairo(fontSize: 10, color: Colors.green)),
                const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Show employee tasks as cards
  // Show employee's completed tasks in the filtered period
  void _showEmployeeTasks(EmployeeAuth employee, Color deptColor) {
    // Get completed order IDs from filtered audit logs
    final completedOrderIds = <String>{};
    for (var log in _filteredAuditLogs) {
      final fieldName = log['field_name']?.toString() ?? '';
      final newValue = log['new_value']?.toString() ?? '';
      if (fieldName == 'status' && (newValue == 'Done' || newValue == 'completed')) {
        final orderId = log['order_id']?.toString() ?? '';
        if (orderId.isNotEmpty && orderId != 'bulk_delete' && orderId != 'import_batch') {
          completedOrderIds.add(orderId);
        }
      }
    }

    // Get employee's tasks that are COMPLETED in the filtered period
    final allTasks = _getEmployeeTasks(employee);
    final completedTasks = allTasks.where((task) => completedOrderIds.contains(task.id)).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Color(0xFFF8F9FA),
          borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: deptColor.withOpacity(0.1),
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: deptColor.withOpacity(0.2),
                    child: Text(employee.initials, style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w600, color: deptColor)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(employee.fullName, style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
                        Text(employee.role ?? 'Employee', style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF64748B))),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            // Filter label
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.green.withOpacity(0.05),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, size: 16, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(
                    'Completed orders in ${_getDateFilterLabel()}',
                    style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green),
                  ),
                  const Spacer(),
                  Text(
                    '${completedTasks.length} orders',
                    style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.green),
                  ),
                ],
              ),
            ),
            // Completed task cards
            Expanded(
              child: completedTasks.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline, size: 60, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text('No completed orders in this period', style: GoogleFonts.cairo(color: Colors.grey)),
                  ],
                ),
              )
                  : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: completedTasks.length,
                itemBuilder: (context, index) {
                  final task = completedTasks[index];
                  return _buildCompletedTaskCard(task, deptColor, employee);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

// Helper to get date filter label
  String _getDateFilterLabel() {
    switch (_dateFilter) {
      case 'today': return 'Today';
      case 'week': return 'This Week';
      case 'month': return 'This Month';
      default: return 'All Time';
    }
  }

// Completed task card - opens OrderTrackingPage on tap
  Widget _buildCompletedTaskCard(SAPMainOrder task, Color deptColor, EmployeeAuth employee) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.green.withOpacity(0.3)),
      ),
      child: InkWell(
        onTap: () {
          // Close bottom sheet first
          Navigator.pop(context);
          // Navigate to Order Tracking Page
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OrderTrackingPage(order: task),
            ),
          );
        },
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task.description.isNotEmpty ? task.description : 'No description',
                      style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Done',
                      style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.green),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildTaskInfo(Icons.receipt, task.designOrder),
                  const SizedBox(width: 12),
                  _buildTaskInfo(Icons.description, task.contractNumber),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _buildTaskInfo(Icons.inventory_2, 'QTY: ${task.quantity} ${task.unitOfMeasure}'),
                  const SizedBox(width: 12),
                  _buildTaskInfo(Icons.attach_money, '\$${_formatNumber(task.value)}'),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _buildTaskInfo(Icons.factory, task.factory ?? 'N/A'),
                  const SizedBox(width: 12),
                  _buildTaskInfo(Icons.person, task.customerName),
                  const Spacer(),
                  const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  // Individual task card
  Widget _buildTaskCard(SAPMainOrder task, bool isDone) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: isDone ? Colors.green.withOpacity(0.3) : Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.description.isNotEmpty ? task.description : 'No description',
                    style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDone ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    task.status,
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isDone ? Colors.green : Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildTaskInfo(Icons.receipt, task.designOrder),
                const SizedBox(width: 12),
                _buildTaskInfo(Icons.description, task.contractNumber),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _buildTaskInfo(Icons.inventory_2, 'QTY: ${task.quantity} ${task.unitOfMeasure}'),
                const SizedBox(width: 12),
                _buildTaskInfo(Icons.attach_money, '\$${_formatNumber(task.value)}'),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _buildTaskInfo(Icons.factory, task.factory ?? 'N/A'),
                const SizedBox(width: 12),
                _buildTaskInfo(Icons.person, task.customerName),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskInfo(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.grey),
        const SizedBox(width: 4),
        Text(
          text,
          style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF64748B)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  String _formatNumber(double number) {
    if (number == 0) return '0.00';
    final parts = number.toStringAsFixed(2).split('.');
    final buffer = StringBuffer();
    for (int i = 0; i < parts[0].length; i++) {
      if (i > 0 && (parts[0].length - i) % 3 == 0) buffer.write(',');
      buffer.write(parts[0][i]);
    }
    return '${buffer.toString()}.${parts[1]}';
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
        style: GoogleFonts.cairo(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
