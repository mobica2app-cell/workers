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

  // Status distribution
  Map<String, int> _statusDistribution = {};

  // Top engineers (by order count)
  List<Map<String, dynamic>> _topEngineers = [];

  // Factory distribution
  Map<String, int> _factoryDistribution = {};

  // Recent orders
  List<SAPMainOrder> _recentOrders = [];

  // Orders this month
  int _ordersThisMonth = 0;

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
      final factoryDist = <String, int>{};
      final engineerCount = <String, int>{};
      double totalVal = 0;
      double totalQty = 0;
      final factories = <String>{};
      int thisMonth = 0;
      final now = DateTime.now();
      final currentMonth =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';

      for (var order in orders) {
        // Status
        final status = order.status.isEmpty ? 'Unknown' : order.status;
        statusDist[status] = (statusDist[status] ?? 0) + 1;

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
        _factoryDistribution = factoryDist;
        _topEngineers = topEngineers.take(5).toList();
        _recentOrders = recent.take(8).toList();
        _ordersThisMonth = thisMonth;
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

            // Stats Cards
            Row(
              children: [
                _buildStatCard(
                  'Total Orders',
                  '$_totalOrders',
                  Icons.receipt_long,
                  Colors.blue,
                ),
                const SizedBox(width: 16),
                _buildStatCard(
                  'Total Value',
                  '\$${_formatNumber(_totalValue)}',
                  Icons.attach_money,
                  Colors.green,
                ),
                const SizedBox(width: 16),
                _buildStatCard(
                  'Employees',
                  '$_totalEmployees',
                  Icons.people,
                  Colors.orange,
                ),
                const SizedBox(width: 16),
                _buildStatCard(
                  'Factories',
                  '$_totalFactories',
                  Icons.factory,
                  Colors.purple,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildStatCard(
                  'Total QTY',
                  _totalQuantity.toStringAsFixed(0),
                  Icons.inventory_2,
                  Colors.teal,
                ),
                const SizedBox(width: 16),
                _buildStatCard(
                  'This Month',
                  '$_ordersThisMonth',
                  Icons.calendar_today,
                  Colors.indigo,
                ),
                const SizedBox(width: 16),
                _buildStatCard(
                  'Avg Value',
                  '\$${_formatNumber(_totalOrders > 0 ? _totalValue / _totalOrders : 0)}',
                  Icons.trending_up,
                  Colors.amber,
                ),
                const SizedBox(width: 16),
                _buildStatCard(
                  'Products',
                  '${_statusDistribution.values.fold(0, (a, b) => a + b)}',
                  Icons.category,
                  Colors.pink,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Charts Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: _buildStatusDistributionCard()),
                const SizedBox(width: 16),
                Expanded(child: _buildTopEngineersCard()),
              ],
            ),
            const SizedBox(height: 24),

            // Recent Orders
            _buildRecentOrdersCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
      String title,
      String value,
      IconData icon,
      Color color,
      ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
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
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: GoogleFonts.cairo(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: _textColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: GoogleFonts.cairo(
                fontSize: 13,
                color: _secondaryTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusDistributionCard() {
    final colors = [
      Colors.blue,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.green,
      Colors.indigo,
      Colors.amber,
      Colors.cyan,
    ];
    final entries = _statusDistribution.entries.take(8).toList();

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
          if (entries.isEmpty)
            Center(
              child: Text(
                'No data',
                style: GoogleFonts.cairo(color: _secondaryTextColor),
              ),
            )
          else
            ...entries.asMap().entries.map((e) {
              final i = e.key;
              final entry = e.value;
              final total = _totalOrders;
              final pct = total > 0 ? (entry.value / total * 100).round() : 0;
              final color = colors[i % colors.length];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.key.length > 25
                                ? '${entry.key.substring(0, 23)}...'
                                : entry.key,
                            style: GoogleFonts.cairo(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: _textColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '$pct%',
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct / 100,
                        backgroundColor: _isDark ? Colors.grey.withOpacity(0.2) : Colors.grey.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildTopEngineersCard() {
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
            'Top Sales Engineers',
            style: GoogleFonts.cairo(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 20),
          if (_topEngineers.isEmpty)
            Center(
              child: Text(
                'No data',
                style: GoogleFonts.cairo(color: _secondaryTextColor),
              ),
            )
          else
            ..._topEngineers.asMap().entries.map((entry) {
              final i = entry.key;
              final eng = entry.value;
              final medals = ['🥇', '🥈', '🥉', '4', '5'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: i < 3
                            ? Colors.amber.withOpacity(0.2)
                            : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          medals[i],
                          style: GoogleFonts.cairo(fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            eng['name'] ?? '',
                            style: GoogleFonts.cairo(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _textColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${eng['count']} orders',
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              color: _secondaryTextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildRecentOrdersCard() {
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
          Row(
            children: [
              Text(
                'Recent Orders',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _textColor,
                ),
              ),
              const Spacer(),
              Text(
                '${_recentOrders.length} orders',
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  color: _secondaryTextColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_recentOrders.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Text(
                  'No orders yet',
                  style: GoogleFonts.cairo(color: _secondaryTextColor),
                ),
              ),
            )
          else
            ..._recentOrders.map(
                  (order) => Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: _borderColor.withOpacity(0.5)),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _getStatusColor(order.status).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.receipt,
                        color: _getStatusColor(order.status),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.description.isNotEmpty
                                ? order.description
                                : 'No description',
                            style: GoogleFonts.cairo(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _textColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${order.customerName} • ${order.designOrder}',
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              color: _secondaryTextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusColor(order.status).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        order.status.length > 15
                            ? '${order.status.substring(0, 13)}...'
                            : order.status,
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _getStatusColor(order.status),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
