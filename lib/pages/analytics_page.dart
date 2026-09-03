// lib/pages/analytics_page.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/sap_service.dart';

class AnalyticsPage extends StatefulWidget {
  final SAPMainService sapService;

  const AnalyticsPage({Key? key, required this.sapService}) : super(key: key);

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  bool _isLoading = true;

  static const List<String> _approvalStatuses = [
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

  List<SAPMainOrder> _orders = [];
  List<Map<String, dynamic>> _auditLogs = [];

  DateTime? _startDate;
  DateTime? _endDate;

  // Section data
  int _approvalOrders = 0;
  int _manufacturingOrders = 0;
  double _approvalValue = 0;
  double _manufacturingValue = 0;
  double _approvalQuantity = 0;
  double _manufacturingQuantity = 0;

  Map<String, int> _approvalFactories = {};
  Map<String, int> _manufacturingFactories = {};
  // Factory/SLoc descriptions loaded from Supabase `factory_names`.
  // Key is normalized factory code, value is description.
  Map<String, String> _factoryDescriptions = {};
  Map<String, String> _factoryOriginalCodes = {};
  Map<String, int> _approvalSales = {};
  Map<String, int> _manufacturingSales = {};

  Map<String, int> _approvalByDate = {};
  Map<String, int> _manufacturingByDate = {};

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _backgroundColor =>
      _isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get _surfaceColor =>
      _isDark ? const Color(0xFF1E293B) : Colors.white;
  Color get _textColor =>
      _isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);
  Color get _secondaryTextColor =>
      _isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  Color get _borderColor =>
      _isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  double get _pageWidth => MediaQuery.sizeOf(context).width;
  bool get _isMobile => _pageWidth < 700;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      await _loadFactoryNames();

      final orders = await widget.sapService.getAllOrders();

      // Status audit history is used for date analytics, exactly like the
      // dashboard. A large limit keeps the analytics useful for big datasets.
      final auditRows = await Supabase.instance.client
          .from('order_audit_log')
          .select('order_id, field_name, new_value, changed_at')
          .eq('field_name', 'status')
          .order('changed_at', ascending: true)
          .limit(100000);

      _orders = orders;
      _auditLogs = List<Map<String, dynamic>>.from(auditRows);

      _recalculate();
    } catch (e) {
      debugPrint('Error loading analytics: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        _showMessage('Could not load analytics data.');
      }
    }
  }

  Future<void> _loadFactoryNames() async {
    debugPrint('');
    debugPrint('========== [FACTORY DEBUG - ANALYTICS] ==========');
    debugPrint('[FACTORY DEBUG - ANALYTICS] Loading factory_names...');

    try {
      final rows = await Supabase.instance.client
          .from('factory_names')
          .select('s_loc, description');

      debugPrint(
        '[FACTORY DEBUG - ANALYTICS] Rows returned: ${rows.length}',
      );

      final descriptions = <String, String>{};
      final originalCodes = <String, String>{};

      for (final row in rows) {
        final rawCode = row['s_loc']?.toString() ?? '';
        final rawDescription = row['description']?.toString() ?? '';

        final code = rawCode.trim();
        final description = rawDescription.trim();

        if (code.isEmpty) {
          debugPrint(
            '[FACTORY DEBUG - ANALYTICS] Skipping row with empty s_loc: $row',
          );
          continue;
        }

        final key = code.toLowerCase();
        descriptions[key] = description;
        originalCodes[key] = code;

        debugPrint(
          '[FACTORY DEBUG - ANALYTICS] Factory: "$code" | '
              'Description: "${description.isEmpty ? '<EMPTY>' : description}"',
        );
      }

      if (mounted) {
        setState(() {
          _factoryDescriptions = descriptions;
          _factoryOriginalCodes = originalCodes;
        });
      } else {
        _factoryDescriptions = descriptions;
        _factoryOriginalCodes = originalCodes;
      }

      debugPrint(
        '[FACTORY DEBUG - ANALYTICS] Loaded ${descriptions.length} factory codes.',
      );
      debugPrint('================================================');
      debugPrint('');
    } catch (e, stackTrace) {
      debugPrint(
        '[FACTORY DEBUG - ANALYTICS] ERROR loading factory_names: $e',
      );
      debugPrint(
        '[FACTORY DEBUG - ANALYTICS] STACK: $stackTrace',
      );
      debugPrint('================================================');
      debugPrint('');

      // Keep analytics usable even if factory_names is unavailable.
      _factoryDescriptions = {};
      _factoryOriginalCodes = {};
    }
  }

  String _formatFactoryLabel(String factory) {
    final code = factory.trim();
    if (code.isEmpty) return '-';

    final key = code.toLowerCase();
    final description = _factoryDescriptions[key]?.trim() ?? '';

    final label = description.isEmpty
        ? (_factoryOriginalCodes[key] ?? code)
        : '${_factoryOriginalCodes[key] ?? code} ($description)';

    debugPrint(
      '[FACTORY DEBUG - ANALYTICS] Format "$factory" -> "$label"',
    );

    return label;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  bool _inDateRange(DateTime date) {
    final d = _dateOnly(date);
    if (_startDate != null && d.isBefore(_dateOnly(_startDate!))) {
      return false;
    }
    if (_endDate != null && d.isAfter(_dateOnly(_endDate!))) {
      return false;
    }
    return true;
  }

  bool _isApproval(String status) =>
      _approvalStatuses.any((s) => s.toLowerCase() == status.toLowerCase());

  bool _isManufacturing(String status) =>
      _manufacturingStatuses.any((s) => s.toLowerCase() == status.toLowerCase());

  String _orderKey(SAPMainOrder order) => order.id.toString().trim();

  void _recalculate() {
    final ordersById = <String, SAPMainOrder>{
      for (final order in _orders) _orderKey(order): order,
    };

    final approvalIds = <String>{};
    final manufacturingIds = <String>{};

    final approvalFactories = <String, Set<String>>{};
    final manufacturingFactories = <String, Set<String>>{};
    final approvalSales = <String, Set<String>>{};
    final manufacturingSales = <String, Set<String>>{};

    final approvalDates = <String, Set<String>>{};
    final manufacturingDates = <String, Set<String>>{};

    for (final log in _auditLogs) {
      final orderId = log['order_id']?.toString().trim() ?? '';
      final status = log['new_value']?.toString().trim() ?? '';
      final changedAt = _parseDate(log['changed_at']);

      if (orderId.isEmpty ||
          orderId == 'bulk_delete' ||
          orderId == 'import_batch' ||
          status.isEmpty ||
          changedAt == null ||
          !_inDateRange(changedAt)) {
        continue;
      }

      final approval = _isApproval(status);
      final manufacturing = _isManufacturing(status);

      if (!approval && !manufacturing) continue;

      final order = ordersById[orderId];
      if (order == null) continue;

      final isSectionApproval = approval;
      final ids = isSectionApproval ? approvalIds : manufacturingIds;
      final factories =
      isSectionApproval ? approvalFactories : manufacturingFactories;
      final sales = isSectionApproval ? approvalSales : manufacturingSales;
      final dates = isSectionApproval ? approvalDates : manufacturingDates;

      // One order is counted once per section for KPI/factory/sales totals,
      // even if it has multiple status changes inside that section.
      ids.add(orderId);

      final factory = (order.factory ?? '').trim();
      if (factory.isNotEmpty) {
        factories.putIfAbsent(factory, () => <String>{}).add(orderId);
      }

      final salesEngineer = order.salesEngineer.trim();
      if (salesEngineer.isNotEmpty) {
        sales.putIfAbsent(salesEngineer, () => <String>{}).add(orderId);
      }

      // For the date graph, count each order once per day per section.
      final dayKey = DateFormat('yyyy-MM-dd').format(changedAt);
      dates.putIfAbsent(dayKey, () => <String>{}).add(orderId);
    }

    final sumValue = (Set<String> ids) => ids.fold<double>(
      0,
          (sum, id) => sum + (ordersById[id]?.value ?? 0),
    );

    final sumQuantity = (Set<String> ids) => ids.fold<double>(
      0,
          (sum, id) => sum + (ordersById[id]?.quantity ?? 0),
    );

    Map<String, int> setMapToCounts(Map<String, Set<String>> source) {
      final result = <String, int>{};
      for (final entry in source.entries) {
        result[entry.key] = entry.value.length;
      }
      return result;
    }

    Map<String, int> dateSetToCounts(Map<String, Set<String>> source) {
      final result = <String, int>{};
      for (final entry in source.entries) {
        result[entry.key] = entry.value.length;
      }
      return Map.fromEntries(
        result.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      );
    }

    if (!mounted) return;

    debugPrint('');
    debugPrint('========== [FACTORY DEBUG - ANALYTICS DATA] ==========');
    debugPrint(
      '[FACTORY DEBUG - ANALYTICS DATA] Approval factories: '
          '${approvalFactories.map((k, v) => MapEntry(k, v.length))}',
    );
    debugPrint(
      '[FACTORY DEBUG - ANALYTICS DATA] Manufacturing factories: '
          '${manufacturingFactories.map((k, v) => MapEntry(k, v.length))}',
    );
    debugPrint('======================================================');
    debugPrint('');

    setState(() {
      _approvalOrders = approvalIds.length;
      _manufacturingOrders = manufacturingIds.length;
      _approvalValue = sumValue(approvalIds);
      _manufacturingValue = sumValue(manufacturingIds);
      _approvalQuantity = sumQuantity(approvalIds);
      _manufacturingQuantity = sumQuantity(manufacturingIds);

      _approvalFactories = setMapToCounts(approvalFactories);
      _manufacturingFactories = setMapToCounts(manufacturingFactories);
      _approvalSales = setMapToCounts(approvalSales);
      _manufacturingSales = setMapToCounts(manufacturingSales);

      _approvalByDate = dateSetToCounts(approvalDates);
      _manufacturingByDate = dateSetToCounts(manufacturingDates);

      _isLoading = false;
    });
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? _endDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'SELECT START DATE',
    );
    if (picked == null) return;

    final date = _dateOnly(picked);
    if (_endDate != null && date.isAfter(_dateOnly(_endDate!))) {
      _showMessage('Start date cannot be after end date.');
      return;
    }

    setState(() => _startDate = date);
    _recalculate();
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'SELECT END DATE',
    );
    if (picked == null) return;

    final date = _dateOnly(picked);
    if (_startDate != null && date.isBefore(_dateOnly(_startDate!))) {
      _showMessage('End date cannot be before start date.');
      return;
    }

    setState(() => _endDate = date);
    _recalculate();
  }

  void _clearDateRange() {
    setState(() {
      _startDate = null;
      _endDate = null;
    });
    _recalculate();
  }

  String _dateLabel(DateTime? date) =>
      date == null ? 'Select date' : DateFormat('dd MMM yyyy').format(date);

  String _dateRangeLabel() {
    if (_startDate == null && _endDate == null) return 'All time';
    if (_startDate != null && _endDate != null) {
      return '${_dateLabel(_startDate)} → ${_dateLabel(_endDate)}';
    }
    if (_startDate != null) return 'From ${_dateLabel(_startDate)}';
    return 'Until ${_dateLabel(_endDate)}';
  }

  String _formatNumber(double number) {
    final parts = number.toStringAsFixed(2).split('.');
    final buffer = StringBuffer();
    for (int i = 0; i < parts[0].length; i++) {
      if (i > 0 && (parts[0].length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(parts[0][i]);
    }
    return '${buffer.toString()}.${parts[1]}';
  }

  String _shortName(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.length <= 2) return name;
    return '${words[0]} ${words[1]}';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.cairo(fontSize: 12)),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
          : RefreshIndicator(
        onRefresh: _loadAnalytics,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final padding = constraints.maxWidth < 700
                ? 12.0
                : constraints.maxWidth < 1100
                ? 18.0
                : 24.0;

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(padding, 20, padding, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 18),
                  _buildDateFilter(),
                  const SizedBox(height: 20),
                  _buildOverviewCards(),
                  const SizedBox(height: 24),
                  _buildSection(
                    title: 'Approval',
                    icon: Icons.fact_check_outlined,
                    sectionColor: Colors.purple,
                    orderCount: _approvalOrders,
                    value: _approvalValue,
                    quantity: _approvalQuantity,
                    factories: _approvalFactories,
                    sales: _approvalSales,
                    dates: _approvalByDate,
                  ),
                  const SizedBox(height: 24),
                  _buildSection(
                    title: 'Manufacturing',
                    icon: Icons.precision_manufacturing_outlined,
                    sectionColor: Colors.orange,
                    orderCount: _manufacturingOrders,
                    value: _manufacturingValue,
                    quantity: _manufacturingQuantity,
                    factories: _manufacturingFactories,
                    sales: _manufacturingSales,
                    dates: _manufacturingByDate,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Analytics',
                style: GoogleFonts.cairo(
                  fontSize: _isMobile ? 23 : 29,
                  fontWeight: FontWeight.bold,
                  color: _textColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Approval & Manufacturing performance',
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  color: _secondaryTextColor,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loadAnalytics,
          icon: Icon(Icons.refresh_rounded, color: _secondaryTextColor),
        ),
      ],
    );
  }

  Widget _buildDateFilter() {
    return Container(
      padding: EdgeInsets.all(_isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
      ),
      child: _isMobile
          ? Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.date_range_rounded,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Audit Date',
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w700,
                  color: _textColor,
                ),
              ),
              const Spacer(),
              if (_startDate != null || _endDate != null)
                IconButton(
                  tooltip: 'Clear dates',
                  onPressed: _clearDateRange,
                  icon: Icon(Icons.clear, color: _secondaryTextColor),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildDateField(
                  'Start Date',
                  _startDate,
                  Icons.calendar_month,
                  _pickStartDate,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDateField(
                  'End Date',
                  _endDate,
                  Icons.event,
                  _pickEndDate,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _dateRangeLabel(),
            style: GoogleFonts.cairo(
              fontSize: 11,
              color: _secondaryTextColor,
            ),
          ),
        ],
      )
          : Row(
        children: [
          Icon(Icons.date_range_rounded,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Text(
            'Audit Date',
            style: GoogleFonts.cairo(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _textColor,
            ),
          ),
          const SizedBox(width: 18),
          SizedBox(
            width: 210,
            child: _buildDateField(
              'Start Date',
              _startDate,
              Icons.calendar_month,
              _pickStartDate,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 210,
            child: _buildDateField(
              'End Date',
              _endDate,
              Icons.event,
              _pickEndDate,
            ),
          ),
          const Spacer(),
          Text(
            _dateRangeLabel(),
            style: GoogleFonts.cairo(
              fontSize: 11,
              color: _secondaryTextColor,
            ),
          ),
          if (_startDate != null || _endDate != null)
            IconButton(
              tooltip: 'Clear dates',
              onPressed: _clearDateRange,
              icon: Icon(Icons.clear, color: _secondaryTextColor),
            ),
        ],
      ),
    );
  }

  Widget _buildDateField(
      String label,
      DateTime? date,
      IconData icon,
      VoidCallback onTap,
      ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: date != null
                ? Theme.of(context).colorScheme.primary
                : _borderColor,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: _secondaryTextColor),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.cairo(
                      fontSize: 8,
                      color: _secondaryTextColor,
                    ),
                  ),
                  Text(
                    _dateLabel(date),
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _textColor,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.keyboard_arrow_down,
                size: 16, color: _secondaryTextColor),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCards() {
    final cards = [
      _overviewCard(
        'Approval Orders',
        '$_approvalOrders',
        Icons.fact_check_outlined,
        Colors.purple,
      ),
      _overviewCard(
        'Manufacturing Orders',
        '$_manufacturingOrders',
        Icons.precision_manufacturing_outlined,
        Colors.orange,
      ),
      _overviewCard(
        'Approval Value',
        '\$${_formatNumber(_approvalValue)}',
        Icons.attach_money,
        Colors.green,
      ),
      _overviewCard(
        'Manufacturing Value',
        '\$${_formatNumber(_manufacturingValue)}',
        Icons.payments_outlined,
        Colors.blue,
      ),
    ];

    final columns = _isMobile ? 2 : 4;
    final spacing = _isMobile ? 9.0 : 14.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards)
              SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }

  Widget _overviewCard(
      String title,
      String value,
      IconData icon,
      Color color,
      ) {
    return Container(
      padding: EdgeInsets.all(_isMobile ? 11 : 16),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(_isDark ? .18 : .035),
            blurRadius: 9,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: _isMobile ? 20 : 24),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                    fontSize: _isMobile ? 16 : 21,
                    fontWeight: FontWeight.bold,
                    color: _textColor,
                  ),
                ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                    fontSize: 9,
                    color: _secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Color sectionColor,
    required int orderCount,
    required double value,
    required double quantity,
    required Map<String, int> factories,
    required Map<String, int> sales,
    required Map<String, int> dates,
  }) {
    return Container(
      padding: EdgeInsets.all(_isMobile ? 14 : 20),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: sectionColor.withOpacity(.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(_isDark ? .18 : .035),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: sectionColor.withOpacity(.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: sectionColor, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.cairo(
                    fontSize: _isMobile ? 18 : 21,
                    fontWeight: FontWeight.w700,
                    color: _textColor,
                  ),
                ),
              ),
              Text(
                '$orderCount orders',
                style: GoogleFonts.cairo(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: sectionColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _sectionMetric('Orders', '$orderCount', sectionColor),
              _sectionMetric(
                'Value',
                '\$${_formatNumber(value)}',
                sectionColor,
              ),
              _sectionMetric(
                'QTY',
                quantity.toStringAsFixed(0),
                sectionColor,
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 850) {
                return Column(
                  children: [
                    _buildFactoryChart(
                      title: '$title by Factory',
                      data: factories,
                      color: sectionColor,
                    ),
                    const SizedBox(height: 18),
                    _buildSalesChart(
                      title: '$title by Sales Engineer',
                      data: sales,
                      color: sectionColor,
                    ),
                    const SizedBox(height: 18),
                    _buildDateChart(
                      title: '$title by Date',
                      data: dates,
                      color: sectionColor,
                    ),
                  ],
                );
              }

              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildFactoryChart(
                          title: '$title by Factory',
                          data: factories,
                          color: sectionColor,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildSalesChart(
                          title: '$title by Sales Engineer',
                          data: sales,
                          color: sectionColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildDateChart(
                    title: '$title by Date',
                    data: dates,
                    color: sectionColor,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _sectionMetric(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(.06),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withOpacity(.15)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$value  ',
              style: GoogleFonts.cairo(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _textColor,
              ),
            ),
            TextSpan(
              text: title,
              style: GoogleFonts.cairo(
                fontSize: 10,
                color: _secondaryTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chartContainer({
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: EdgeInsets.all(_isMobile ? 10 : 14),
      decoration: BoxDecoration(
        color: _isDark ? const Color(0xFF172033) : const Color(0xFFFAFBFD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.cairo(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildFactoryChart({
    required String title,
    required Map<String, int> data,
    required Color color,
  })
  {
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (entries.isEmpty) {
      return _chartContainer(
        title: title,
        child: _emptyChart(),
      );
    }

    final maxVal =
    entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return _chartContainer(
      title: title,
      child: SizedBox(
        height: 270,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,

            maxY: maxVal.toDouble() +
                (maxVal == 1 ? 1 : maxVal * .15),

            // ==============================
            // HOVER TOOLTIP
            // ==============================
            barTouchData: BarTouchData(
              enabled: true,
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  if (groupIndex < 0 || groupIndex >= entries.length) {
                    return null;
                  }

                  final factoryCode = entries[groupIndex].key;
                  final number = entries[groupIndex].value;

                  final description = _factoryDescriptions[factoryCode.trim().toLowerCase()]
                      ?.trim();

                  return BarTooltipItem(
                    '${description?.isNotEmpty == true ? description : factoryCode}\n'
                        'Contract terms: $number',
                    GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  );
                },
              ),
            ),

            // ==============================
            // BARS
            // ==============================
            barGroups: entries.asMap().entries.map((entry) {
              return BarChartGroupData(
                x: entry.key,
                barRods: [
                  BarChartRodData(
                    toY: entry.value.value.toDouble(),
                    color: color,
                    width: entries.length > 8 ? 12 : 18,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(5),
                      topRight: Radius.circular(5),
                    ),
                  ),
                ],
              );
            }).toList(),

            // ==============================
            // AXIS TITLES
            // ==============================
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(
                  showTitles: false,
                ),
              ),

              rightTitles: const AxisTitles(
                sideTitles: SideTitles(
                  showTitles: false,
                ),
              ),

              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  getTitlesWidget: (value, meta) {
                    return Text(
                      value.toInt().toString(),
                      style: GoogleFonts.cairo(
                        fontSize: 9,
                        color: _secondaryTextColor,
                      ),
                    );
                  },
                ),
              ),

              // IMPORTANT:
              // Don't show factory names here.
              // The user will see them when hovering.
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 35,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();

                    if (i < 0 || i >= entries.length) {
                      return const SizedBox();
                    }

                    return Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Text(
                        entries[i].key, // Factory code only
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cairo(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _secondaryTextColor,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // ==============================
            // GRID
            // ==============================
            gridData: FlGridData(
              drawVerticalLine: false,
              getDrawingHorizontalLine: (value) {
                return FlLine(
                  color: _borderColor,
                  strokeWidth: .7,
                );
              },
            ),

            borderData: FlBorderData(
              show: false,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSalesChart({
    required String title,
    required Map<String, int> data,
    required Color color,
  }) {
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (entries.isEmpty) {
      return _chartContainer(
        title: title,
        child: _emptyChart(),
      );
    }

    final visible = entries.take(10).toList();
    final maxVal =
    visible.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return _chartContainer(
      title: title,
      child: SizedBox(
        height: 270,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxVal.toDouble() + (maxVal == 1 ? 1 : maxVal * .15),
            barGroups: visible.asMap().entries.map((entry) {
              return BarChartGroupData(
                x: entry.key,
                barRods: [
                  BarChartRodData(
                    toY: entry.value.value.toDouble(),
                    color: color,
                    width: 16,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(5),
                      topRight: Radius.circular(5),
                    ),
                  ),
                ],
              );
            }).toList(),
            titlesData: FlTitlesData(
              topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  getTitlesWidget: (value, meta) => Text(
                    value.toInt().toString(),
                    style: GoogleFonts.cairo(
                      fontSize: 9,
                      color: _secondaryTextColor,
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 55,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    if (i < 0 || i >= visible.length) {
                      return const SizedBox();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Transform.rotate(
                        angle: -0.55,
                        child: SizedBox(
                          width: 78,
                          child: Text(
                            _shortName(visible[i].key),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.cairo(
                              fontSize: 8,
                              color: _secondaryTextColor,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            gridData: FlGridData(
              drawVerticalLine: false,
              getDrawingHorizontalLine: (value) =>
                  FlLine(color: _borderColor, strokeWidth: .7),
            ),
            borderData: FlBorderData(show: false),
          ),
        ),
      ),
    );
  }

  Widget _buildDateChart({
    required String title,
    required Map<String, int> data,
    required Color color,
  }) {
    if (data.isEmpty) {
      return _chartContainer(
        title: title,
        child: _emptyChart(),
      );
    }

    final entries = data.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final maxVal =
    entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return _chartContainer(
      title: title,
      child: SizedBox(
        height: 260,
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: maxVal.toDouble() + (maxVal == 1 ? 1 : maxVal * .15),
            lineBarsData: [
              LineChartBarData(
                spots: entries.asMap().entries.map((entry) {
                  return FlSpot(
                    entry.key.toDouble(),
                    entry.value.value.toDouble(),
                  );
                }).toList(),
                isCurved: true,
                color: color,
                barWidth: 3,
                dotData: FlDotData(
                  show: entries.length <= 30,
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: color.withOpacity(.08),
                ),
              ),
            ],
            titlesData: FlTitlesData(
              topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  getTitlesWidget: (value, meta) => Text(
                    value.toInt().toString(),
                    style: GoogleFonts.cairo(
                      fontSize: 9,
                      color: _secondaryTextColor,
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  interval: _dateLabelInterval(entries.length),
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    if (i < 0 || i >= entries.length) {
                      return const SizedBox();
                    }
                    final date = DateTime.tryParse(entries[i].key);
                    final label = date == null
                        ? entries[i].key
                        : DateFormat(
                      entries.length > 60 ? 'MMM' : 'dd MMM',
                    ).format(date);
                    return Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Text(
                        label,
                        style: GoogleFonts.cairo(
                          fontSize: 8,
                          color: _secondaryTextColor,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            gridData: FlGridData(
              getDrawingHorizontalLine: (value) =>
                  FlLine(color: _borderColor, strokeWidth: .7),
              getDrawingVerticalLine: (value) =>
                  FlLine(color: _borderColor, strokeWidth: .5),
            ),
            borderData: FlBorderData(show: false),
          ),
        ),
      ),
    );
  }

  double _dateLabelInterval(int length) {
    if (length <= 10) return 1;
    if (length <= 30) return 3;
    if (length <= 60) return 7;
    return 14;
  }

  Widget _emptyChart() {
    return SizedBox(
      height: 220,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bar_chart_rounded,
              size: 34,
              color: _secondaryTextColor.withOpacity(.5),
            ),
            const SizedBox(height: 7),
            Text(
              'No data for this period',
              style: GoogleFonts.cairo(
                fontSize: 11,
                color: _secondaryTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

