// lib/pages/dashboard_page.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/sap_service.dart';
import '../main.dart';


class DashboardPage extends StatefulWidget {
  final SAPMainService sapService;

  const DashboardPage({Key? key, required this.sapService}) : super(key: key);

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _isLoading = true;

  // Stats
  int _totalOrders = 0;
  double _totalValue = 0;
  double _totalQuantity = 0;
  int _totalEmployees = 0;
  int _totalFactories = 0;

// Add these fields near the other fields
  Map<String, double> _statusValues = {};
  Map<String, double> _statusQuantities = {};

  // Status distribution
  Map<String, int> _statusDistribution = {};


  // Recent orders
  List<SAPMainOrder> _recentOrders = [];

  // Orders this month
  int _ordersThisMonth = 0;

  // Approach and Manufacturing data
  List<SAPMainOrder> _approachOrders = [];
  List<SAPMainOrder> _manufacturingOrders = [];
  double _approachValue = 0;
  double _manufacturingValue = 0;
  double _approachQuantity = 0;
  double _manufacturingQuantity = 0;

  // Employee auth service
  final EmployeeAuthService _authService = EmployeeAuthService(
    Supabase.instance.client,
  );

  // Theme helper getters
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _backgroundColor => _isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get _surfaceColor => _isDark ? const Color(0xFF1E293B) : Colors.white;
  Color get _textColor => _isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);
  Color get _secondaryTextColor => _isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  Color get _borderColor => _isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  Color get _cardColor => _isDark ? const Color(0xFF1E293B) : Colors.white;

  // Status lists
  static const List<String> _approachStatuses = [
    'Drawing Submittal',
    'modifications submitted',
    'Approval',
    'Sales',
    'As Built',
    'ادارة تصميم المنتجات',
    'الادارة الهندسه',
    'design studio',
  ];

  static const List<String> _manufacturingStatuses = [
    'Manufacturing Drawing',
    'Review',
    'Master Data',
    'partation  master data',
  ];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final orders = await widget.sapService.getAllOrders();
      final employees = await _authService.getAllEmployees();

      // Calculate stats
      final statusDist = <String, int>{};
      final statusValues = <String, double>{};
      final statusQuantities = <String, double>{};
      final factoryDist = <String, int>{};
      final engineerCount = <String, int>{};
      double totalVal = 0;
      double totalQty = 0;
      final factories = <String>{};
      int thisMonth = 0;
      final now = DateTime.now();
      final currentMonth =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';

      // Approach and Manufacturing
      final approachOrders = <SAPMainOrder>[];
      final manufacturingOrders = <SAPMainOrder>[];
      double approachVal = 0;
      double manufacturingVal = 0;
      double approachQty = 0;
      double manufacturingQty = 0;

      for (var order in orders) {
        // Status
        final status = order.status.isEmpty ? 'Unknown' : order.status;
        statusDist[status] = (statusDist[status] ?? 0) + 1;
        statusValues[status] = (statusValues[status] ?? 0) + order.value;
        statusQuantities[status] = (statusQuantities[status] ?? 0) + order.quantity;

        // Factory
        if (order.factory != null && order.factory!.isNotEmpty) {
          factoryDist[order.factory!] = (factoryDist[order.factory!] ?? 0) + 1;
          factories.add(order.factory!);
        }

        // Engineer count
        if (order.salesEngineer.isNotEmpty) {
          engineerCount[order.salesEngineer] =
              (engineerCount[order.salesEngineer] ?? 0) + 1;
        }

        // Values
        totalVal += order.value;
        totalQty += order.quantity;

        // This month
        if (order.orderDate != null &&
            order.orderDate!.startsWith(currentMonth)) {
          thisMonth++;
        }

        // Approach statuses
        if (_approachStatuses.contains(order.status)) {
          approachOrders.add(order);
          approachVal += order.value;
          approachQty += order.quantity;
        }

        // Manufacturing statuses
        if (_manufacturingStatuses.contains(order.status)) {
          manufacturingOrders.add(order);
          manufacturingVal += order.value;
          manufacturingQty += order.quantity;
        }
      }

      // Top engineers
      final topEngineers =
      engineerCount.entries
          .map((e) => {'name': e.key, 'count': e.value})
          .toList()
        ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

      // Recent orders (last 10)
      final recent = List<SAPMainOrder>.from(orders)
        ..sort((a, b) {
          final aDate = a.createdAt ?? DateTime(2000);
          final bDate = b.createdAt ?? DateTime(2000);
          return bDate.compareTo(aDate);
        });

      setState(() {
        _totalOrders = orders.length;
        _totalValue = totalVal;
        _totalQuantity = totalQty;
        _totalEmployees = employees.length;
        _totalFactories = factories.length;
        _statusDistribution = statusDist;
        _statusValues = statusValues;
        _statusQuantities = statusQuantities;
        _recentOrders = recent.take(8).toList();
        _ordersThisMonth = thisMonth;
        _approachOrders = approachOrders;
        _manufacturingOrders = manufacturingOrders;
        _approachValue = approachVal;
        _manufacturingValue = manufacturingVal;
        _approachQuantity = approachQty;
        _manufacturingQuantity = manufacturingQty;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading dashboard: $e');
      setState(() => _isLoading = false);
    }
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

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Done':
        return Colors.green;
      case 'Approval':
        return Colors.green;
      case 'Drawing Submittal':
        return Colors.purple;
      case 'Manufacturing Drawing':
        return Colors.indigo;
      case 'Review':
        return Colors.amber;
      case 'Sales':
        return Colors.deepOrange;
      case 'As Built':
        return Colors.brown;
      case 'Master Data':
        return Colors.cyan;
      case 'partation  master data':
        return Colors.deepPurple;
      case 'ادارة تصميم المنتجات':
        return Colors.teal;
      case 'الادارة الهندسه':
        return Colors.blueGrey;
      case 'design studio':
        return Colors.pink;
      case 'modifications submitted':
        return Colors.lightBlue;
      case 'Unknown':
        return _isDark ? Colors.grey.shade400 : Colors.grey;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: _isLoading
          ? Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Text(
                  'Dashboard',
                  style: GoogleFonts.cairo(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: _textColor,
                  ),
                ),
                const Spacer(),
                Text(
                  DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now()),
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    color: _secondaryTextColor,
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: _loadDashboardData,
                  icon: Icon(Icons.refresh, color: _secondaryTextColor),
                  tooltip: 'Refresh',
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Comparison Section
            _buildComparisonSection(),
            const SizedBox(height: 24),

            // Charts Row
            _buildStatusDistributionCard(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Order Breakdown',
            style: GoogleFonts.cairo(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Total Column
              Expanded(
                child: _buildComparisonColumn(
                  title: 'Total',
                  icon: Icons.all_inclusive,
                  color: Colors.blue,
                  orderCount: _totalOrders,
                  totalValue: _totalValue,
                  totalQuantity: _totalQuantity,
                  statuses: null, // Show all statuses
                ),
              ),
              const SizedBox(width: 16),
              // Approach Column
              Expanded(
                child: _buildComparisonColumn(
                  title: 'Approach',
                  icon: Icons.design_services,
                  color: Colors.purple,
                  orderCount: _approachOrders.length,
                  totalValue: _approachValue,
                  totalQuantity: _approachQuantity,
                  statuses: _approachStatuses,
                ),
              ),
              const SizedBox(width: 16),
              // Manufacturing Column
              Expanded(
                child: _buildComparisonColumn(
                  title: 'Manufacturing',
                  icon: Icons.precision_manufacturing,
                  color: Colors.orange,
                  orderCount: _manufacturingOrders.length,
                  totalValue: _manufacturingValue,
                  totalQuantity: _manufacturingQuantity,
                  statuses: _manufacturingStatuses,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonColumn({
    required String title,
    required IconData icon,
    required Color color,
    required int orderCount,
    required double totalValue,
    required double totalQuantity,
    required List<String>? statuses,
  })
  {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildComparisonRow('Orders', '$orderCount', color),
          const SizedBox(height: 8),
          _buildComparisonRow('Value', '\$${_formatNumber(totalValue)}', color),
          const SizedBox(height: 8),
          _buildComparisonRow('QTY', totalQuantity.toStringAsFixed(0), color),
          const SizedBox(height: 16),
          if (statuses != null && statuses.isNotEmpty) ...[
            Divider(color: color.withOpacity(0.3)),
            const SizedBox(height: 8),
            Text(
              'Statuses (${statuses.length})',
              style: GoogleFonts.cairo(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _secondaryTextColor,
              ),
            ),
            const SizedBox(height: 8),
            ...statuses.map((status) {
              final count = _statusDistribution[status] ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _getStatusColor(status),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        status,
                        style: GoogleFonts.cairo(
                          fontSize: 10,
                          color: _secondaryTextColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '$count',
                      style: GoogleFonts.cairo(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _textColor,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildComparisonRow(String label, String value, Color color) {
    return Row(
      children: [
        Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: 12,
            color: _secondaryTextColor,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: GoogleFonts.cairo(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _textColor,
          ),
        ),
      ],
    );
  }


  Widget _buildStatusDistributionCard() {
    // Define all statuses
    final allStatuses = [
      'Drawing Submittal',
      'Approval',
      'modifications submitted',
      'Manufacturing Drawing',
      'Done',
      'Task Done',
      'مطلوب اكوادها الاسترشاديه',
      'تحت المراجعة',
      'Review',
      'Master Data',
      'Sales',
      'As Built',
      'Tasks',
      'planning',
      'partation  master data',
      'الادارة الهندسه',
      'design studio',
      'imported',
      'ادارة تصميم المنتجات',
    ];

    // Colors for each status
    final statusColors = <String, Color>{
      'Drawing Submittal': Colors.purple,
      'Approval': Colors.green,
      'modifications submitted': Colors.lightBlue,
      'Manufacturing Drawing': Colors.indigo,
      'Done': Colors.green.shade700,
      'Task Done': Colors.teal,
      'مطلوب اكوادها الاسترشاديه': Colors.blue,
      'تحت المراجعة': Colors.orange,
      'Review': Colors.amber,
      'Master Data': Colors.cyan,
      'Sales': Colors.deepOrange,
      'As Built': Colors.brown,
      'Tasks': Colors.lime,
      'planning': Colors.pink,
      'partation  master data': Colors.deepPurple,
      'الادارة الهندسه': Colors.blueGrey,
      'design studio': Colors.red,
      'imported': Colors.grey,
      'ادارة تصميم المنتجات': Colors.teal,
    };

    // Calculate total value per status
    final statusValues = <String, double>{};
    for (var order in _recentOrders.isEmpty ? [] : _recentOrders) {
      // This won't work correctly as _recentOrders only has 8 items
    }

    // Better approach: store all orders with their status and value
    // For now, we'll calculate from _statusDistribution

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: _isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Orders by Status',
            style: GoogleFonts.cairo(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 20),
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: _isDark ? const Color(0xFF334155).withOpacity(0.3) : Colors.grey.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text('Status', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w700, color: _textColor))),
                Expanded(flex: 2, child: Text('Count', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w700, color: _textColor), textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text('Value', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w700, color: _textColor), textAlign: TextAlign.right)),
                Expanded(flex: 2, child: Text('%', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w700, color: _textColor), textAlign: TextAlign.right)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Status Rows
          ...allStatuses.map((status) {
            final count = _statusDistribution[status] ?? 0;
            if (count == 0) return const SizedBox.shrink();

            final color = statusColors[status] ?? Colors.grey;
            final pct = _totalOrders > 0 ? (count / _totalOrders * 100) : 0.0;
            final pctFormatted = pct.toStringAsFixed(2);

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              status,
                              style: GoogleFonts.cairo(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: _textColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '$count',
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _textColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '\$${_formatNumber(_statusValues[status] ?? 0)}',
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF059669),
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '$pctFormatted%',
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          // Total Row
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Total',
                    style: GoogleFonts.cairo(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _textColor,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '$_totalOrders',
                    style: GoogleFonts.cairo(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _textColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '\$${_formatNumber(_totalValue)}',
                    style: GoogleFonts.cairo(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF059669),
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '100.00%',
                    style: GoogleFonts.cairo(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


}

