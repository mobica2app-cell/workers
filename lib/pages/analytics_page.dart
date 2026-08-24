// lib/pages/analytics_page.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/sap_service.dart';

class AnalyticsPage extends StatefulWidget {
  final SAPMainService sapService;

  const AnalyticsPage({Key? key, required this.sapService}) : super(key: key);

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  bool _isLoading = true;

  // Data
  Map<String, int> _statusDistribution = {};
  Map<String, int> _factoryDistribution = {};
  Map<String, int> _engineerWorkloads = {};
  Map<String, int> _designTeamDistribution = {};
  int _totalOrders = 0;
  double _totalValue = 0;
  double _totalQuantity = 0;
  Map<String, int> _ordersByMonth = {};

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
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() => _isLoading = true);
    try {
      final orders = await widget.sapService.getAllOrders();

      final statusDist = <String, int>{};
      final factoryDist = <String, int>{};
      final engineerDist = <String, int>{};
      final designTeamDist = <String, int>{};
      final monthlyDist = <String, int>{};
      double totalVal = 0;
      double totalQty = 0;
      int unknown = 0;

      for (var order in orders) {
        // Status distribution
        final status = order.status.isEmpty ? 'Unknown' : order.status;
        statusDist[status] = (statusDist[status] ?? 0) + 1;
        if (status == 'Unknown') unknown++;

        // Factory distribution
        if (order.factory != null && order.factory!.isNotEmpty) {
          factoryDist[order.factory!] = (factoryDist[order.factory!] ?? 0) + 1;
        }

        // Engineer workloads (Sales Engineer)
        if (order.salesEngineer.isNotEmpty) {
          engineerDist[order.salesEngineer] =
              (engineerDist[order.salesEngineer] ?? 0) + 1;
        }

        // Design team distribution
        if (order.designTeam != null && order.designTeam!.isNotEmpty) {
          designTeamDist[order.designTeam!] =
              (designTeamDist[order.designTeam!] ?? 0) + 1;
        }

        // Monthly distribution
        if (order.orderDate != null) {
          final month = order.orderDate!.substring(0, 7); // YYYY-MM
          monthlyDist[month] = (monthlyDist[month] ?? 0) + 1;
        }

        totalVal += order.value;
        totalQty += order.quantity;
      }

      setState(() {
        _totalOrders = orders.length;
        _totalValue = totalVal;
        _totalQuantity = totalQty;
        _statusDistribution = statusDist;
        _factoryDistribution = factoryDist;
        _engineerWorkloads = engineerDist;
        _designTeamDistribution = designTeamDist;
        _ordersByMonth = monthlyDist;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading analytics: $e');
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
                  'Analytics',
                  style: GoogleFonts.cairo(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: _textColor,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _loadAnalytics,
                  icon: Icon(Icons.refresh, color: _secondaryTextColor),
                  tooltip: 'Refresh',
                ),
              ],
            ),
            const SizedBox(height: 24),

            // KPI Row
            Row(
              children: [
                _buildKpiCard(
                  'Total Orders',
                  '$_totalOrders',
                  Icons.receipt_long,
                  Colors.blue,
                ),
                const SizedBox(width: 16),
                _buildKpiCard(
                  'Total Value',
                  '\$${_formatNumber(_totalValue)}',
                  Icons.attach_money,
                  Colors.green,
                ),
                const SizedBox(width: 16),
                _buildKpiCard(
                  'Total QTY',
                  _totalQuantity.toStringAsFixed(0),
                  Icons.inventory_2,
                  Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Charts Row 1
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _buildStatusPieChart()),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: _buildStatusSummary()),
              ],
            ),
            const SizedBox(height: 24),

            // Charts Row 2
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 1, child: _buildFactoryChart()),
                const SizedBox(width: 16),
                Expanded(flex: 1, child: _buildEngineerWorkloadChart()),
              ],
            ),
            const SizedBox(height: 24),

            // Monthly Trends
            _buildMonthlyTrendsChart(),
            const SizedBox(height: 24),

            // Status Distribution Table
            _buildStatusTable(),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color color) {
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
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: GoogleFonts.cairo(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _textColor,
                  ),
                ),
                Text(
                  title,
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: _secondaryTextColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusPieChart() {
    final colors = [
      Colors.blue,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.green,
      Colors.indigo,
      Colors.amber,
      Colors.cyan,
      Colors.deepOrange,
      Colors.brown,
      Colors.pink,
      Colors.lime,
    ];
    final entries = _statusDistribution.entries.take(10).toList();
    final total = entries.fold(0, (a, b) => a + b.value);

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
            'Status Distribution',
            style: GoogleFonts.cairo(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 300,
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: PieChart(
                    PieChartData(
                      sections: entries.asMap().entries.map((e) {
                        final i = e.key;
                        final entry = e.value;
                        return PieChartSectionData(
                          color: colors[i % colors.length],
                          value: entry.value.toDouble(),
                          title: '${(entry.value / total * 100).round()}%',
                          radius: 100,
                          titleStyle: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        );
                      }).toList(),
                      centerSpaceRadius: 40,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: entries.asMap().entries.map((e) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: colors[e.key % colors.length],
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                e.value.key.length > 18
                                    ? '${e.value.key.substring(0, 16)}...'
                                    : e.value.key,
                                style: GoogleFonts.cairo(fontSize: 11, color: _textColor),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${e.value.value}',
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _textColor,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSummary() {
    final entries = _statusDistribution.entries.take(5).toList();
    final maxVal = entries.isEmpty ? 1 : entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);

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
            'Top Statuses',
            style: GoogleFonts.cairo(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 24),
          ...entries.map((e) {
            final pct = _totalOrders > 0
                ? (e.value / _totalOrders * 100).round()
                : 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          e.key,
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: _textColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${e.value} ($pct%)',
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: e.value / maxVal,
                      backgroundColor: _isDark ? Colors.grey.withOpacity(0.2) : Colors.grey.withOpacity(0.1),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.blue,
                      ),
                      minHeight: 8,
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

  Widget _buildFactoryChart() {
    final entries = _factoryDistribution.entries.toList();
    final maxVal = entries.isEmpty
        ? 1
        : entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);

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
            'By Factory',
            style: GoogleFonts.cairo(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 250,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxVal.toDouble() + 2,
                barGroups: entries
                    .asMap()
                    .entries
                    .map(
                      (e) => BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: e.value.value.toDouble(),
                        color: Colors.blue,
                        width: 20,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(6),
                          topRight: Radius.circular(6),
                        ),
                      ),
                    ],
                  ),
                )
                    .toList(),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() < entries.length)
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              entries[value.toInt()].key,
                              style: GoogleFonts.cairo(fontSize: 9, color: _secondaryTextColor),
                            ),
                          );
                        return const SizedBox();
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) => Text(
                        '${value.toInt()}',
                        style: GoogleFonts.cairo(fontSize: 10, color: _secondaryTextColor),
                      ),
                    ),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: _borderColor,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEngineerWorkloadChart() {
    final entries = _engineerWorkloads.entries
        .where((e) => e.value > 0)
        .take(10)
        .toList();
    final maxVal = entries.isEmpty
        ? 1
        : entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);

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
            'Engineer Workloads',
            style: GoogleFonts.cairo(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 20),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Text(
                  'No data',
                  style: GoogleFonts.cairo(color: _secondaryTextColor),
                ),
              ),
            )
          else
            SizedBox(
              height: 250,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxVal.toDouble() + 2,
                  barGroups: entries
                      .asMap()
                      .entries
                      .map(
                        (e) => BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: e.value.value.toDouble(),
                          color: Colors.orange,
                          width: 18,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(6),
                            topRight: Radius.circular(6),
                          ),
                        ),
                      ],
                    ),
                  )
                      .toList(),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() < entries.length)
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                entries[value.toInt()].key.length > 10
                                    ? '${entries[value.toInt()].key.substring(0, 8)}..'
                                    : entries[value.toInt()].key,
                                style: GoogleFonts.cairo(fontSize: 9, color: _secondaryTextColor),
                              ),
                            );
                          return const SizedBox();
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) => Text(
                          '${value.toInt()}',
                          style: GoogleFonts.cairo(fontSize: 10, color: _secondaryTextColor),
                        ),
                      ),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: _borderColor,
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMonthlyTrendsChart() {
    final entries = _ordersByMonth.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (entries.isEmpty) return const SizedBox.shrink();
    final maxVal = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);

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
            'Monthly Trends',
            style: GoogleFonts.cairo(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxVal.toDouble() + 5,
                lineBarsData: [
                  LineChartBarData(
                    spots: entries
                        .asMap()
                        .entries
                        .map(
                          (e) => FlSpot(
                        e.key.toDouble(),
                        e.value.value.toDouble(),
                      ),
                    )
                        .toList(),
                    isCurved: true,
                    color: const Color(0xFF6366F1),
                    barWidth: 3,
                    dotData: FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFF6366F1).withOpacity(0.1),
                    ),
                  ),
                ],
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() < entries.length)
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              entries[value.toInt()].key,
                              style: GoogleFonts.cairo(fontSize: 9, color: _secondaryTextColor),
                            ),
                          );
                        return const SizedBox();
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) => Text(
                        '${value.toInt()}',
                        style: GoogleFonts.cairo(fontSize: 10, color: _secondaryTextColor),
                      ),
                    ),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: _borderColor,
                    strokeWidth: 1,
                  ),
                  getDrawingVerticalLine: (value) => FlLine(
                    color: _borderColor,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTable() {
    final entries = _statusDistribution.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

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
            'Status Distribution Details',
            style: GoogleFonts.cairo(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 16),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(3),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(color: _isDark ? const Color(0xFF334155).withOpacity(0.3) : Colors.grey.withOpacity(0.05)),
                children: [
                  _tableHeader('Status'),
                  _tableHeader('Count'),
                  _tableHeader('%'),
                ],
              ),
              ...entries.map((e) {
                final pct = _totalOrders > 0
                    ? (e.value / _totalOrders * 100).toStringAsFixed(1)
                    : '0';
                return TableRow(
                  children: [
                    _tableCell(e.key),
                    _tableCell('${e.value}'),
                    _tableCell('$pct%'),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tableHeader(String text) => Padding(
    padding: const EdgeInsets.all(12),
    child: Text(
      text,
      style: GoogleFonts.cairo(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: _textColor,
      ),
    ),
  );

  Widget _tableCell(String text) => Padding(
    padding: const EdgeInsets.all(12),
    child: Text(
      text,
      style: GoogleFonts.cairo(
        fontSize: 13,
        color: _secondaryTextColor,
      ),
    ),
  );
}
