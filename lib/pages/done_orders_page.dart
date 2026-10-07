import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/sap_service.dart';
import 'track_order.dart';

class DoneOrdersPage extends StatefulWidget {
  const DoneOrdersPage({super.key});

  @override
  State<DoneOrdersPage> createState() => _DoneOrdersPageState();
}

class _DoneOrdersPageState extends State<DoneOrdersPage> {
  final SAPMainService _service = SAPMainService(Supabase.instance.client);
  List<SAPMainOrder> _orders = [];
  bool _loading = true;
  String? _error;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _background => _isDark ? const Color(0xFF000000) : const Color(0xFFF8FAFC);
  Color get _surface => _isDark ? const Color(0xFF121212) : Colors.white;
  Color get _text => _isDark ? const Color(0xFFF5F5F5) : const Color(0xFF0F172A);
  Color get _secondary => _isDark ? const Color(0xFFAAAAAA) : const Color(0xFF64748B);
  Color get _border => _isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE2E8F0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final orders = await _service.getAllDoneOrders();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: _text,
        elevation: 0,
        title: Text(
          'SAP Done Orders',
          style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Text(
                      'Could not load SAP done orders:\n$_error',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.cairo(color: _secondary),
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _border),
                    ),
                    child: _orders.isEmpty
                        ? Center(
                            child: Text(
                              'No SAP done orders',
                              style: GoogleFonts.cairo(color: _secondary),
                            ),
                          )
                        : _buildTable(),
                  ),
      ),
    );
  }

  Widget _buildTable() {
    final rows = _orders.map((order) {
      return DataRow(
        cells: [
          _cell(order.status, order),
          _cell(order.designOrder, order),
          _cell(order.contractNumber, order),
          _cell(order.customerName, order),
          _cell(order.productCode, order),
          _cell(order.description, order),
          _cell(order.quantity.toString(), order),
          _cell(order.value.toString(), order),
          _cell(order.salesEngineer, order),
          _cell(order.factory ?? '-', order),
        ],
      );
    }).toList();

    const widths = [120.0, 130.0, 120.0, 180.0, 150.0, 220.0, 70.0, 110.0, 150.0, 100.0];
    const labels = [
      'Status',
      'Design Order',
      'Contract Num',
      'Customer',
      'Product Code',
      'Description',
      'QTY',
      'Value',
      'Sales Engineer',
      'Factory',
    ];

    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            headingRowHeight: 44,
            dataRowMinHeight: 40,
            dataRowMaxHeight: 52,
            columnSpacing: 18,
            headingTextStyle: GoogleFonts.cairo(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _text,
            ),
            dataTextStyle: GoogleFonts.cairo(fontSize: 11, color: _text),
            columns: List.generate(
              labels.length,
              (i) => DataColumn(
                label: SizedBox(width: widths[i], child: Text(labels[i])),
              ),
            ),
            rows: rows,
          ),
        ),
      ),
    );
  }

  DataCell _cell(String value, SAPMainOrder order) {
    return DataCell(
      SizedBox(width: 120, child: Text(value, overflow: TextOverflow.ellipsis)),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => OrderTrackingPage(order: order)),
        );
      },
    );
  }
}
