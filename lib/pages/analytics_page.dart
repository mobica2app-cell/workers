// lib/pages/analytics_page.dart
import 'dart:math' as math;
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
  double get _pageWidth => MediaQuery.sizeOf(context).width;
  bool get _isMobile => _pageWidth < 600;

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

  // Helper to get first 2 words of a name
  String _getShortName(String fullName) {
    final words = fullName.trim().split(RegExp(r'\s+'));
    if (words.length <= 2) return fullName;
    return '${words[0]} ${words[1]}';
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
          : LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final isMobile = width < 600;
          final horizontalPadding = isMobile
              ? 12.0
              : width < 900
              ? 18.0
              : 24.0;

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              isMobile ? 16 : 24,
              horizontalPadding,
              24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Analytics',
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 22 : width < 900 ? 25 : 28,
                    fontWeight: FontWeight.bold,
                    color: _textColor,
                  ),
                ),
                SizedBox(height: isMobile ? 14 : 18),
                LayoutBuilder(
                  builder: (context, kpiConstraints) {
                    final spacing = isMobile ? 10.0 : 16.0;
                    final columns = isMobile ? 2 : 3;
                    final cardWidth =
                        (kpiConstraints.maxWidth -
                            spacing * (columns - 1)) /
                            columns;

                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        SizedBox(
                          width: cardWidth,
                          child: _buildKpiCard(
                            'Total Orders',
                            '$_totalOrders',
                            Icons.receipt_long,
                            Colors.blue,
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _buildKpiCard(
                            'Total Value',
                            '\$${_formatNumber(_totalValue)}',
                            Icons.attach_money,
                            Colors.green,
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _buildKpiCard(
                            'Total QTY',
                            _totalQuantity.toStringAsFixed(0),
                            Icons.inventory_2,
                            Colors.orange,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                SizedBox(height: isMobile ? 16 : 24),
                _buildFactoryChart(),
                SizedBox(height: isMobile ? 16 : 24),
                _buildEngineerWorkloadChart(),
                SizedBox(height: isMobile ? 16 : 24),
                _buildMonthlyTrendsChart(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(_isMobile ? 12 : 20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: _isDark
                ? Colors.black.withOpacity(0.3)
                : Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 180;
          return Row(
            children: [
              Container(
                padding: EdgeInsets.all(compact ? 7 : 10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: compact ? 22 : 28),
              ),
              SizedBox(width: compact ? 8 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                        fontSize: compact ? 17 : 24,
                        fontWeight: FontWeight.bold,
                        color: _textColor,
                      ),
                    ),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                        fontSize: compact ? 10 : 12,
                        color: _secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFactoryChart() {
    final entries = _factoryDistribution.entries.toList();
    final maxVal = entries.isEmpty
        ? 1
        : entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return Container(
      padding: EdgeInsets.all(_isMobile ? 14 : 24),
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
            height: _isMobile ? 270 : 300,
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
                        width: _isMobile ? 14 : 20,
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
                      reservedSize: _isMobile ? 52 : 60,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() < entries.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Transform.rotate(
                              angle: -math.pi / 4,
                              child: Text(
                                entries[value.toInt()].key,
                                style: GoogleFonts.cairo(
                                  fontSize: 9,
                                  color: _secondaryTextColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          );
                        }
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
      padding: EdgeInsets.all(_isMobile ? 14 : 24),
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
            'Sales Engineer Workloads',
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
              height: _isMobile ? 270 : 300,
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
                          width: _isMobile ? 13 : 18,
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
                        reservedSize: _isMobile ? 52 : 60,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() < entries.length) {
                            // Get first 2 words of engineer name
                            final shortName = _getShortName(entries[value.toInt()].key);
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Transform.rotate(
                                angle: -math.pi / 4,
                                child: Text(
                                  shortName,
                                  style: GoogleFonts.cairo(
                                    fontSize: 9,
                                    color: _secondaryTextColor,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            );
                          }
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
      padding: EdgeInsets.all(_isMobile ? 14 : 24),
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
            'Order Dates Load',
            style: GoogleFonts.cairo(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: _isMobile ? 230 : 250,
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
                      reservedSize: _isMobile ? 42 : 50,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() < entries.length)
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Transform.rotate(
                              angle: -math.pi / 4,
                              child: Text(
                                entries[value.toInt()].key,
                                style: GoogleFonts.cairo(fontSize: 9, color: _secondaryTextColor),
                              ),
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
}
