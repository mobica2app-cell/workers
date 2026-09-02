// lib/pages/order_detail_page.dart
import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mobitem/pages/track_order.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_html/html.dart' as html;

import '../services/sap_service.dart';

class OrderDetailPage extends StatefulWidget {
  final SAPMainOrder order;
  final SAPMainService sapService;

  const OrderDetailPage({
    Key? key,
    required this.order,
    required this.sapService,
  }) : super(key: key);

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  List<SAPMainOrder> _relatedOrders = [];
  final Map<String, List<_AuditEvent>> _eventsByOrderId = {};

  bool _isLoading = true;
  bool _isExporting = false;
  String? _error;

  // ============================================================
  // WORKFLOW
  // ============================================================

  static const String _drawing = 'Drawing Submittal';
  static const String _approval = 'Approval';
  static const String _modification = 'modifications submitted';
  static const String _manufacturing = 'Manufacturing Drawing';
  static const String _masterData = 'Master Data';
  static const String _done = 'Done';

  // These are the stages the contract journey is interested in.
  static const List<String> _mainStages = [
    _drawing,
    _approval,
    _modification,
    _manufacturing,
    _masterData,
    _done,
  ];

  // ============================================================
  // THEME
  // ============================================================

  bool get _isDark =>
      Theme.of(context).brightness == Brightness.dark;

  Color get _backgroundColor =>
      _isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF8FAFC);

  Color get _surfaceColor =>
      _isDark
          ? const Color(0xFF1E293B)
          : Colors.white;

  Color get _textColor =>
      _isDark
          ? const Color(0xFFE2E8F0)
          : const Color(0xFF0F172A);

  Color get _secondaryTextColor =>
      _isDark
          ? const Color(0xFF94A3B8)
          : const Color(0xFF64748B);

  Color get _borderColor =>
      _isDark
          ? const Color(0xFF334155)
          : const Color(0xFFE2E8F0);

  Color get _mutedBackground =>
      _isDark
          ? const Color(0xFF0B1220)
          : const Color(0xFFF8FAFC);

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();
    _loadContractJourney();
  }

  Future<void> _loadContractJourney() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      // Get all orders through the same service used by the app,
      // then keep only orders with this contract number.
      final allOrders = await widget.sapService.getAllOrders();

      final contract = widget.order.contractNumber.trim();

      final related = allOrders.where((order) {
        return order.contractNumber.trim() == contract;
      }).toList();

      // If the service did not return the selected order for some reason,
      // keep it in the contract view.
      if (!related.any((o) => o.id == widget.order.id)) {
        related.add(widget.order);
      }

      // Sort bands by sap_main_orders.created_at.
      // Orders without created_at are kept at the end.
      related.sort((a, b) {
        final aDate = _createdAt(a);
        final bDate = _createdAt(b);

        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;

        return aDate.compareTo(bDate);
      });

      final orderIds = related
          .map((o) => o.id)
          .where((id) => id.trim().isNotEmpty)
          .toList();

      final Map<String, List<_AuditEvent>> eventMap = {};

      for (final id in orderIds) {
        eventMap[id] = [];
      }

      // ----------------------------------------------------------
      // Load ALL status audit events for this contract.
      // ----------------------------------------------------------
      //
      // The audit table used elsewhere in this project stores status
      // changes as field_name/new_value/changed_at.
      //
      if (orderIds.isNotEmpty) {
        final rows = await _supabase
            .from('order_audit_log')
            .select(
          'id, order_id, field_name, old_value, new_value, '
              'changed_at, changed_by, changed_by_id',
        )
            .filter('order_id', 'in', '(${orderIds.map((id) => '"$id"').join(',')})')
            .order('changed_at', ascending: true);

        for (final raw in rows) {
          final map = Map<String, dynamic>.from(raw);

          final orderId =
          (map['order_id'] ?? '').toString().trim();

          if (orderId.isEmpty || !eventMap.containsKey(orderId)) {
            continue;
          }

          final fieldName =
          (map['field_name'] ?? '').toString().trim();

          // Only status changes belong to the journey.
          if (!_isStatusField(fieldName)) {
            continue;
          }

          final newValue =
          (map['new_value'] ?? '').toString().trim();

          if (newValue.isEmpty) {
            continue;
          }

          final changedAt =
          _parseDateTime(
            map['changed_at'],
          );

          if (changedAt == null) {
            continue;
          }

          eventMap[orderId]!.add(
            _AuditEvent(
              id: (map['id'] ?? '').toString(),
              orderId: orderId,
              oldValue:
              (map['old_value'] ?? '').toString(),
              newValue: newValue,
              changedAt: changedAt,
              changedBy:
              (map['changed_by'] ?? '').toString(),
              changedById:
              (map['changed_by_id'] ?? '').toString(),
            ),
          );
        }
      }

      // ----------------------------------------------------------
      // Sort and remove exact duplicate audit events.
      // ----------------------------------------------------------

      for (final entry in eventMap.entries) {
        entry.value.sort(
              (a, b) => a.changedAt.compareTo(b.changedAt),
        );

        final unique = <_AuditEvent>[];
        final seen = <String>{};

        for (final event in entry.value) {
          final key =
              '${event.changedAt.toIso8601String()}|'
              '${event.newValue.toLowerCase().trim()}|'
              '${event.oldValue.toLowerCase().trim()}';

          if (seen.add(key)) {
            unique.add(event);
          }
        }

        eventMap[entry.key] = unique;
      }

      if (!mounted) return;

      setState(() {
        _relatedOrders = related;
        _eventsByOrderId
          ..clear()
          ..addAll(eventMap);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  // ============================================================
  // AUDIT HELPERS
  // ============================================================

  bool _isStatusField(String fieldName) {
    final value = fieldName.toLowerCase().trim();

    return value == 'status' ||
        value == 'order_status' ||
        value == 'current_status';
  }

  DateTime? _createdAt(SAPMainOrder order) {
    // created_at belongs to sap_main_orders and is mapped to createdAt.
    // Do not use order_date or any audit-log timestamp as creation time.
    return order.createdAt?.toLocal();
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;

    if (value is DateTime) return value;

    final text = value.toString().trim();

    if (text.isEmpty) return null;

    return DateTime.tryParse(text)?.toLocal();
  }

  String _normalizeStatus(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  String _displayStatus(String status) {
    final normalized = _normalizeStatus(status);

    switch (normalized) {
      case 'drawing submittal':
        return _drawing;

      case 'approval':
        return _approval;

      case 'modifications submitted':
      case 'modification submitted':
      case 'modification':
        return _modification;

      case 'manufacturing drawing':
      case 'manufacturing':
        return _manufacturing;

      case 'master data':
        return _masterData;

      case 'done':
      case 'completed':
        return _done;

      default:
        return status.trim();
    }
  }

  bool _isTrackedStage(String status) {
    final normalized =
    _normalizeStatus(_displayStatus(status));

    return _mainStages
        .map(_normalizeStatus)
        .contains(normalized);
  }

  // ============================================================
  // BUILD JOURNEY
  // ============================================================

  List<_JourneyRow> _buildJourneyRows(
      SAPMainOrder order,
      ) {
    final events =
    List<_AuditEvent>.from(
      _eventsByOrderId[order.id] ?? const [],
    );

    final rows = <_JourneyRow>[];

    // ----------------------------------------------------------
    // CREATED
    // ----------------------------------------------------------

    rows.add(
      _JourneyRow.created(
        time: _createdAt(order),
      ),
    );

    // ----------------------------------------------------------
    // Every status event.
    //
    // We intentionally do NOT collapse repeated statuses.
    //
    // Example:
    //
    // Approval
    // Modification
    // Approval
    // Modification
    // Approval
    //
    // All five events remain visible.
    // ----------------------------------------------------------

    final trackedEvents = events
        .where(
          (event) =>
          _isTrackedStage(event.newValue),
    )
        .toList();

    for (int i = 0; i < trackedEvents.length; i++) {
      final current = trackedEvents[i];

      final next =
      i + 1 < trackedEvents.length
          ? trackedEvents[i + 1]
          : null;

      final from =
      i == 0
          ? null
          : _displayStatus(
        trackedEvents[i - 1].newValue,
      );

      final to =
      _displayStatus(
        current.newValue,
      );

      // The current event marks entry into "to".
      // The next tracked status marks exit from it.
      final exitTime =
          next?.changedAt;

      rows.add(
        _JourneyRow.stage(
          status: to,
          enteredAt: current.changedAt,
          exitedAt: exitTime,
          fromStatus: from,
          changedBy: current.changedBy,
          event: current,
          direction:
          _directionFor(
            from,
            to,
          ),
        ),
      );
    }

    // ----------------------------------------------------------
    // If there are no audit status events, show current status.
    // ----------------------------------------------------------

    if (trackedEvents.isEmpty) {
      if (_isTrackedStage(order.status)) {
        rows.add(
          _JourneyRow.stage(
            status:
            _displayStatus(order.status),
            enteredAt: _createdAt(order),
            exitedAt: null,
            fromStatus: null,
            changedBy: '',
            event: null,
            direction: 'CURRENT',
          ),
        );
      }
    }

    return rows;
  }

  // ============================================================
  // TRANSITION DIRECTION
  // ============================================================

  String _directionFor(
      String? from,
      String to,
      ) {
    if (from == null || from.trim().isEmpty) {
      return 'START';
    }

    final a = _normalizeStatus(
      _displayStatus(from),
    );

    final b = _normalizeStatus(
      _displayStatus(to),
    );

    if (a == b) {
      return 'REPEAT';
    }

    // Explicit transitions requested for the contract journey.
    final forwardPairs = <String>{
      '${_normalizeStatus(_drawing)}>${_normalizeStatus(_approval)}',
      '${_normalizeStatus(_approval)}>${_normalizeStatus(_modification)}',
      '${_normalizeStatus(_modification)}>${_normalizeStatus(_approval)}',
      '${_normalizeStatus(_approval)}>${_normalizeStatus(_manufacturing)}',
      '${_normalizeStatus(_manufacturing)}>${_normalizeStatus(_masterData)}',
      '${_normalizeStatus(_masterData)}>${_normalizeStatus(_done)}',
    };

    final key = '$a>$b';

    if (forwardPairs.contains(key)) {
      // Modification -> Approval is a return to approval after
      // the requested modification. It is deliberately labeled.
      if (a == _normalizeStatus(_modification) &&
          b == _normalizeStatus(_approval)) {
        return 'RETURN';
      }

      return 'FORWARD';
    }

    // The exact reverse of the important pairs is explicitly marked.
    final reversePairs = <String>{
      '${_normalizeStatus(_approval)}>${_normalizeStatus(_drawing)}',
      '${_normalizeStatus(_modification)}>${_normalizeStatus(_approval)}',
      '${_normalizeStatus(_manufacturing)}>${_normalizeStatus(_approval)}',
      '${_normalizeStatus(_masterData)}>${_normalizeStatus(_manufacturing)}',
      '${_normalizeStatus(_done)}>${_normalizeStatus(_masterData)}',
      '${_normalizeStatus(_approval)}>${_normalizeStatus(_manufacturing)}',
    };

    if (reversePairs.contains(key)) {
      return 'REVERSE';
    }

    // Use the main workflow ranking for any other movement.
    final rank = <String, int>{
      _normalizeStatus(_drawing): 0,
      _normalizeStatus(_approval): 1,
      _normalizeStatus(_modification): 2,
      _normalizeStatus(_manufacturing): 3,
      _normalizeStatus(_masterData): 4,
      _normalizeStatus(_done): 5,
    };

    final fromRank = rank[a];
    final toRank = rank[b];

    if (fromRank != null && toRank != null) {
      if (toRank > fromRank) return 'FORWARD';
      if (toRank < fromRank) return 'REVERSE';
    }

    return 'OTHER';
  }

  // ============================================================
  // DURATION
  // ============================================================

  Duration _duration(
      DateTime start,
      DateTime? end,
      ) {
    final finish =
        end ?? DateTime.now();

    final value =
    finish.difference(start);

    if (value.isNegative) {
      return Duration.zero;
    }

    return value;
  }

  String _formatDuration(
      Duration duration,
      ) {
    final totalMinutes =
        duration.inMinutes;

    if (totalMinutes < 60) {
      return '${totalMinutes}m';
    }

    final days =
        totalMinutes ~/ (60 * 24);

    final hours =
        (totalMinutes % (60 * 24)) ~/ 60;

    final minutes =
        totalMinutes % 60;

    if (days > 0) {
      return '${days}d ${hours}h ${minutes}m';
    }

    return '${hours}h ${minutes}m';
  }

  // ============================================================
  // NAVIGATE TO TRACKING
  // ============================================================

  void _openTracking(
      SAPMainOrder order,
      ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            OrderTrackingPage(
              order: order,
            ),
      ),
    );
  }

  // ============================================================
  // EXCEL EXPORT
  // ============================================================

  Future<void> _exportContractToExcel() async {
    if (_isExporting) return;

    setState(() {
      _isExporting = true;
    });

    try {
      final excel = Excel.createExcel();

      final defaultSheet = excel.getDefaultSheet();
      if (defaultSheet != null) {
        excel.delete(defaultSheet);
      }

      final sheet = excel['Contract Journey'];
      final contract = widget.order.contractNumber.trim();

      // ============================================================
      // ONE ROW PER BAND / ITEM
      //
      // The manager report intentionally contains only:
      //   - Contract
      //   - Item
      //   - Created At (sap_main_orders.created_at)
      //   - Workflow transition dates
      //
      // Repeated transitions stay on the SAME ROW. For example:
      //   Approval -> Modification #1
      //   Modification -> Approval #1 (RETURN)
      //   Approval -> Modification #2
      //   Modification -> Approval #2 (RETURN)
      //
      // This makes the Excel a manager-friendly timeline instead of
      // putting every event on a separate Excel row.
      // ============================================================

      final transitionDefinitions = <String>[
        'Drawing Submittal → Approval',
        'Approval → Modifications',
        'Modifications → Approval (RETURN)',
        'Approval → Manufacturing Drawing',
        'Manufacturing Drawing → Master Data',
        'Master Data → Done',
      ];

      // Build transition records for every band first so we know how
      // many repeated columns are required.
      final rowsByOrder = <String, List<_ExcelTransition>>{};
      for (final order in _relatedOrders) {
        final events = List<_AuditEvent>.from(
          _eventsByOrderId[order.id] ?? const [],
        )..sort((a, b) => a.changedAt.compareTo(b.changedAt));

        final trackedEvents = events
            .where((event) => _isTrackedStage(event.newValue))
            .toList();

        final transitions = <_ExcelTransition>[];

        for (int i = 1; i < trackedEvents.length; i++) {
          final previous = trackedEvents[i - 1];
          final current = trackedEvents[i];

          final from = _displayStatus(previous.newValue);
          final to = _displayStatus(current.newValue);

          String? type;

          final fromN = _normalizeStatus(from);
          final toN = _normalizeStatus(to);

          if (fromN == _normalizeStatus(_drawing) &&
              toN == _normalizeStatus(_approval)) {
            type = 'Drawing Submittal → Approval';
          } else if (fromN == _normalizeStatus(_approval) &&
              toN == _normalizeStatus(_modification)) {
            type = 'Approval → Modifications';
          } else if (fromN == _normalizeStatus(_modification) &&
              toN == _normalizeStatus(_approval)) {
            type = 'Modifications → Approval (RETURN)';
          } else if (fromN == _normalizeStatus(_approval) &&
              toN == _normalizeStatus(_manufacturing)) {
            type = 'Approval → Manufacturing Drawing';
          } else if (fromN == _normalizeStatus(_manufacturing) &&
              toN == _normalizeStatus(_masterData)) {
            type = 'Manufacturing Drawing → Master Data';
          } else if (fromN == _normalizeStatus(_masterData) &&
              toN == _normalizeStatus(_done)) {
            type = 'Master Data → Done';
          }

          if (type == null) {
            // Keep other movements visible as well, especially unexpected
            // reverse movements, instead of silently losing them.
            type = '$from → $to';
          }

          transitions.add(
            _ExcelTransition(
              type: type,
              changedAt: current.changedAt,
              duration: current.changedAt.difference(previous.changedAt),
            ),
          );
        }

        rowsByOrder[order.id] = transitions;

        final counts = <String, int>{};
        for (final transition in transitions) {
          counts[transition.type] = (counts[transition.type] ?? 0) + 1;
        }
      }

      // ============================================================
      // HEADER
      // ============================================================

      final headers = <String>[
        'Contract Number',
        'Item',
        'Created At',
      ];

      for (final definition in transitionDefinitions) {
        final occurrences = _maxTransitionOccurrence(
          rowsByOrder.values,
          definition,
        );

        for (int occurrence = 1;
        occurrence <= occurrences;
        occurrence++) {
          headers.add('$definition #$occurrence - When');
        }
      }

      // Add unexpected movements at the end, also on the same row.
      final unexpectedTypes = <String>{};
      for (final transitions in rowsByOrder.values) {
        for (final transition in transitions) {
          if (!transitionDefinitions.contains(transition.type)) {
            unexpectedTypes.add(transition.type);
          }
        }
      }

      final sortedUnexpected = unexpectedTypes.toList()..sort();

      for (final type in sortedUnexpected) {
        final occurrences = _maxTransitionOccurrence(
          rowsByOrder.values,
          type,
        );

        for (int occurrence = 1;
        occurrence <= occurrences;
        occurrence++) {
          headers.add('$type #$occurrence - When');
        }
      }

      for (int column = 0; column < headers.length; column++) {
        sheet
            .cell(
          CellIndex.indexByColumnRow(
            columnIndex: column,
            rowIndex: 0,
          ),
        )
            .value = TextCellValue(headers[column]);
      }

      // ============================================================
      // DATA: EXACTLY ONE ROW PER BAND / ITEM
      // ============================================================

      int excelRow = 1;

      for (final order in _relatedOrders) {
        final transitions = rowsByOrder[order.id] ?? const [];

        final values = <String>[
          contract,
          order.itemNumber,
          _formatDateTime(_createdAt(order)),
        ];

        for (final definition in transitionDefinitions) {
          final matching = transitions
              .where((transition) => transition.type == definition)
              .toList();

          final occurrences = _maxTransitionOccurrence(
            rowsByOrder.values,
            definition,
          );

          for (int occurrence = 0;
          occurrence < occurrences;
          occurrence++) {
            if (occurrence < matching.length) {
              final transition = matching[occurrence];

              values.add(_formatDateTime(transition.changedAt));
            } else {
              values.add('');
              values.add('');
            }
          }
        }

        for (final type in sortedUnexpected) {
          final matching = transitions
              .where((transition) => transition.type == type)
              .toList();

          final occurrences = _maxTransitionOccurrence(
            rowsByOrder.values,
            type,
          );

          for (int occurrence = 0;
          occurrence < occurrences;
          occurrence++) {
            if (occurrence < matching.length) {
              final transition = matching[occurrence];

              values.add(_formatDateTime(transition.changedAt));
            } else {
              values.add('');
              values.add('');
            }
          }
        }

        for (int column = 0; column < values.length; column++) {
          sheet
              .cell(
            CellIndex.indexByColumnRow(
              columnIndex: column,
              rowIndex: excelRow,
            ),
          )
              .value = TextCellValue(values[column]);
        }

        excelRow++;
      }


      // ============================================================
      // DELAY REPORT - ALL ORDERS
      // ============================================================
      //
      // This report is NOT limited to the currently opened contract.
      //
      // Source logic is equivalent to:
      //
      // SELECT DISTINCT
      //     order_id,
      //     old_value || ' → ' || new_value AS movement
      // FROM order_audit_log
      // WHERE
      //     (old_value = 'Drawing Submittal' AND new_value = 'Approval')
      //     OR
      //     (old_value = 'modifications submitted' AND new_value = 'Approval')
      //     OR
      //     (old_value = 'Manufacturing Drawing' AND new_value = 'Master Data')
      // ORDER BY order_id
      // LIMIT 100000;
      //
      // After getting those order_ids, sap_main_orders is used to find
      // Contract Number, Item and Created At.
      // ============================================================

      final delaySheet = excel['Delay Report'];

      final delayHeaders = <String>[
        'Order ID',
        'Contract Number',
        'Item',
        'Created At',
        'Movement',
        'Movement Date',
        'Days From Created To Movement',
        'Days From Movement To Now',
        'Current Status',
        'Reason of Delay',
      ];

      for (int column = 0; column < delayHeaders.length; column++) {
        delaySheet
            .cell(CellIndex.indexByColumnRow(
          columnIndex: column,
          rowIndex: 0,
        ))
            .value = TextCellValue(delayHeaders[column]);
      }

      // IMPORTANT:
      // Get ALL orders, not only the orders belonging to the contract
      // currently displayed on this page.
      final allOrdersForDelayReport =
      await widget.sapService.getAllOrders();

      final ordersById = <String, SAPMainOrder>{
        for (final order in allOrdersForDelayReport)
          if (order.id.trim().isNotEmpty) order.id.trim(): order,
      };

      // Apply the WHERE conditions in Supabase BEFORE the 100,000 limit.
      // This matches the user's SQL instead of downloading the first
      // 100,000 audit rows and filtering them afterwards.
      final delayAuditRows = await _supabase
          .from('order_audit_log')
          .select('order_id, old_value, new_value, changed_at')
          .or(
        'and(old_value.eq.Drawing Submittal,new_value.eq.Approval),'
            'and(old_value.eq.modifications submitted,new_value.eq.Approval),'
            'and(old_value.eq.Manufacturing Drawing,new_value.eq.Master Data)',
      )
          .order('order_id', ascending: true)
          .limit(100000);

      // DISTINCT order_id + movement.
      //
      // changed_at is intentionally NOT part of the distinct key because
      // the requested SQL selects only order_id and movement.
      //
      // If the same order has the same movement multiple times, it appears
      // only once in this report.
      final distinctMovements = <String, Map<String, dynamic>>{};

      for (final raw in delayAuditRows) {
        final map = Map<String, dynamic>.from(raw);

        final orderId =
        (map['order_id'] ?? '').toString().trim();

        if (orderId.isEmpty) continue;

        final oldValue =
        (map['old_value'] ?? '').toString().trim();

        final newValue =
        (map['new_value'] ?? '').toString().trim();

        final movement = '$oldValue → $newValue';

        final key =
            '$orderId|${oldValue.toLowerCase()}|${newValue.toLowerCase()}';

        // Keep the first row because the SQL DISTINCT result does not
        // contain changed_at. We only use changed_at as supporting
        // information in Excel.
        distinctMovements.putIfAbsent(
          key,
              () => {
            'order_id': orderId,
            'old_value': oldValue,
            'new_value': newValue,
            'changed_at': map['changed_at'],
            'movement': movement,
          },
        );
      }

      final delayRows = distinctMovements.values.toList()
        ..sort((a, b) {
          final aOrder =
          (a['order_id'] ?? '').toString();
          final bOrder =
          (b['order_id'] ?? '').toString();

          final orderCompare =
          aOrder.compareTo(bOrder);

          if (orderCompare != 0) {
            return orderCompare;
          }

          return (a['movement'] ?? '')
              .toString()
              .compareTo((b['movement'] ?? '').toString());
        });

      int delayExcelRow = 1;
      final now = DateTime.now();

      for (final movementRow in delayRows) {
        final orderId =
        (movementRow['order_id'] ?? '').toString().trim();

        // Find the contract number and item using order_id.
        final order = ordersById[orderId];

        // If the audit order_id no longer exists in sap_main_orders,
        // there is no contract/item mapping to put in the manager report.
        if (order == null) continue;

        final createdAt = _createdAt(order);

        final movementDate =
        _parseDateTime(movementRow['changed_at']);

        final daysFromCreatedToMovement =
        createdAt == null || movementDate == null
            ? null
            : movementDate.difference(createdAt).inDays;

        final daysFromMovementToNow =
        movementDate == null
            ? null
            : now.difference(movementDate).inDays;

        final currentStatus =
        _displayStatus(order.status);

        // The movement itself is the reason/event that puts this order
        // into the delay report. The current status tells the manager
        // where the order is now.
        final reasonOfDelay =
        _normalizeStatus(currentStatus) ==
            _normalizeStatus(_done)
            ? 'Completed'
            : 'Still in $currentStatus';

        final values = <String>[
          order.id,
          order.contractNumber,
          order.itemNumber,
          _formatDateTime(createdAt),
          (movementRow['movement'] ?? '').toString(),
          _formatDateTime(movementDate),
          daysFromCreatedToMovement?.toString() ?? '',
          daysFromMovementToNow?.toString() ?? '',
          currentStatus,
          reasonOfDelay,
        ];

        for (int column = 0;
        column < values.length;
        column++) {
          delaySheet
              .cell(
            CellIndex.indexByColumnRow(
              columnIndex: column,
              rowIndex: delayExcelRow,
            ),
          )
              .value = TextCellValue(values[column]);
        }

        delayExcelRow++;
      }

      final delayWidths = <double>[
        28, // Order ID
        20, // Contract Number
        16, // Item
        22, // Created At
        38, // Movement
        22, // Movement Date
        28, // Days From Created To Movement
        26, // Days From Movement To Now
        24, // Current Status
        30, // Reason of Delay
      ];

      for (int column = 0;
      column < delayHeaders.length;
      column++) {
        delaySheet.setColumnWidth(
          column,
          delayWidths[column],
        );
      }

      // ============================================================
      // COLUMN WIDTHS
      // ============================================================

      for (int column = 0; column < headers.length; column++) {
        final header = headers[column];

        double width;
        if (header == 'Contract Number') {
          width = 20;
        } else if (header == 'Item') {
          width = 16;
        } else if (header == 'Created At') {
          width = 22;
        } else {
          width = 23;
        }

        sheet.setColumnWidth(column, width);
      }

      final encoded = excel.encode();
      final Uint8List? bytes = encoded == null
          ? null
          : Uint8List.fromList(encoded);

      if (bytes == null) {
        throw Exception('Could not create Excel file');
      }

      _downloadExcel(
        bytes,
        'contract_${_safeFileName(contract)}_manager_journey_delay_report.xlsx',
      );

      _showSnackBar(
        'Manager Excel exported successfully for all orders',
      );
    } catch (e) {
      _showSnackBar(
        'Excel export failed: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  int _maxTransitionOccurrence(
      Iterable<List<_ExcelTransition>> allRows,
      String type,
      ) {
    int maximum = 0;

    for (final transitions in allRows) {
      final count = transitions.where((item) => item.type == type).length;
      if (count > maximum) {
        maximum = count;
      }
    }

    return maximum == 0 ? 1 : maximum;
  }

  double _excelColumnWidth(
      String header,
      ) {
    switch (header) {
      case 'Description':
        return 35;
      case 'Customer':
        return 28;
      case 'Contract':
      case 'Band':
      case 'Item Number':
        return 18;
      case 'Changed By':
        return 22;
      case 'Event Type':
      case 'From Status':
      case 'To Status':
      case 'Direction':
        return 22;
      default:
        return 20;
    }
  }

  void _downloadExcel(
      Uint8List bytes,
      String fileName,
      ) {
    final blob =
    html.Blob(
      [
        bytes,
      ],
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );

    final url =
    html.Url.createObjectUrlFromBlob(
      blob,
    );

    final anchor =
    html.AnchorElement(href: url)
      ..setAttribute(
        'download',
        fileName,
      )
      ..style.display = 'none';

    html.document.body?.children
        .add(anchor);

    anchor.click();

    anchor.remove();

    html.Url.revokeObjectUrl(url);
  }

  String _safeFileName(
      String value,
      ) {
    final cleaned =
    value.replaceAll(
      RegExp(r'[\\/:*?"<>| ]+'),
      '_',
    );

    return cleaned.isEmpty
        ? 'contract'
        : cleaned;
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
      _backgroundColor,

      appBar: AppBar(
        backgroundColor:
        const Color(0xFF0F172A),
        foregroundColor:
        Colors.white,
        elevation: 0,

        title: Row(
          children: [
            const Icon(
              Icons.route,
              size: 21,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Contract ${widget.order.contractNumber}',
                style:
                GoogleFonts.cairo(
                  fontSize: 17,
                  fontWeight:
                  FontWeight.w700,
                ),
                overflow:
                TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),

      body:
      _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child:
        CircularProgressIndicator(
          color:
          Theme.of(context)
              .colorScheme
              .primary,
        ),
      );
    }

    if (_error != null) {
      return _buildError();
    }

    if (_relatedOrders.isEmpty) {
      return _buildEmpty();
    }

    return RefreshIndicator(
      onRefresh:
      _loadContractJourney,

      child: ListView(
        padding:
        const EdgeInsets.fromLTRB(
          18,
          18,
          18,
          40,
        ),

        children: [
          _buildContractHeader(),

          const SizedBox(height: 18),

          _buildLegend(),

          const SizedBox(height: 18),

          ..._relatedOrders.asMap().entries.map(
                (entry) => Padding(
              padding:
              const EdgeInsets.only(
                bottom: 14,
              ),
              child:
              _buildBandCard(
                entry.key + 1,
                entry.value,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CONTRACT HEADER
  // ============================================================

  Widget _buildContractHeader() {
    final totalQuantity =
    _relatedOrders.fold<double>(
      0,
          (sum, order) =>
      sum + order.quantity,
    );

    final totalValue =
    _relatedOrders.fold<double>(
      0,
          (sum, order) =>
      sum + order.value,
    );

    DateTime? earliest;

    for (final order in _relatedOrders) {
      final created = _createdAt(order);

      if (created == null) continue;

      if (earliest == null || created.isBefore(earliest!)) {
        earliest = created;
      }
    }

    return Container(
      padding:
      const EdgeInsets.all(20),

      decoration:
      BoxDecoration(
        color: _surfaceColor,
        borderRadius:
        BorderRadius.circular(14),
        border:
        Border.all(
          color: _borderColor,
        ),
      ),

      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,

        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,

                decoration:
                BoxDecoration(
                  color:
                  const Color(
                    0xFF6366F1,
                  ).withOpacity(
                    0.12,
                  ),
                  borderRadius:
                  BorderRadius.circular(
                    11,
                  ),
                ),

                child:
                const Icon(
                  Icons.description_outlined,
                  color:
                  Color(0xFF6366F1),
                ),
              ),

              const SizedBox(
                width: 12,
              ),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Contract Position',
                      style:
                      GoogleFonts.cairo(
                        fontSize: 12,
                        color:
                        _secondaryTextColor,
                        fontWeight:
                        FontWeight.w600,
                      ),
                    ),

                    Text(
                      widget.order
                          .contractNumber,
                      style:
                      GoogleFonts.cairo(
                        fontSize: 21,
                        fontWeight:
                        FontWeight.w800,
                        color:
                        _textColor,
                      ),
                    ),
                  ],
                ),
              ),

              _buildHeaderAction(),
            ],
          ),

          const SizedBox(
            height: 18,
          ),

          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildMetric(
                'Bands',
                '${_relatedOrders.length}',
                Icons.view_list_outlined,
              ),
              _buildMetric(
                'Quantity',
                totalQuantity
                    .toStringAsFixed(0),
                Icons.numbers,
              ),
              _buildMetric(
                'Value',
                '\$${_formatNumber(totalValue)}',
                Icons.attach_money,
              ),
              _buildMetric(
                'Started',
                _formatDate(
                  earliest,
                ),
                Icons.event_outlined,
              ),
            ],
          ),

          const SizedBox(
            height: 16,
          ),

          Text(
            widget.order.customerName
                .isNotEmpty
                ? widget.order.customerName
                : 'No customer',
            style:
            GoogleFonts.cairo(
              fontSize: 14,
              fontWeight:
              FontWeight.w600,
              color:
              _textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderAction() {
    return Tooltip(
      message:
      'Export contract journey',

      child: OutlinedButton.icon(
        onPressed:
        _isExporting
            ? null
            : _exportContractToExcel,

        icon:
        const Icon(
          Icons.table_view_outlined,
          size: 17,
        ),

        label: Text(
          'Excel',
          style:
          GoogleFonts.cairo(
            fontSize: 12,
            fontWeight:
            FontWeight.w700,
          ),
        ),

        style:
        OutlinedButton.styleFrom(
          foregroundColor:
          const Color(
            0xFF059669,
          ),
          side:
          const BorderSide(
            color:
            Color(0xFF059669),
          ),
          padding:
          const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 9,
          ),
          shape:
          RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(
              8,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetric(
      String label,
      String value,
      IconData icon,
      ) {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 8,
      ),

      decoration:
      BoxDecoration(
        color: _mutedBackground,
        borderRadius:
        BorderRadius.circular(8),
        border:
        Border.all(
          color: _borderColor,
        ),
      ),

      child: Row(
        mainAxisSize:
        MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color:
            _secondaryTextColor,
          ),
          const SizedBox(width: 7),
          Text(
            '$label: ',
            style:
            GoogleFonts.cairo(
              fontSize: 11,
              color:
              _secondaryTextColor,
              fontWeight:
              FontWeight.w500,
            ),
          ),
          Text(
            value,
            style:
            GoogleFonts.cairo(
              fontSize: 11,
              color:
              _textColor,
              fontWeight:
              FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // LEGEND
  // ============================================================

  Widget _buildLegend() {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 11,
      ),

      decoration:
      BoxDecoration(
        color: _surfaceColor,
        borderRadius:
        BorderRadius.circular(10),
        border:
        Border.all(
          color: _borderColor,
        ),
      ),

      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          _legendItem(
            'FORWARD',
            Colors.green,
          ),
          _legendItem(
            'RETURN',
            Colors.orange,
          ),
          _legendItem(
            'REVERSE',
            Colors.red,
          ),
          _legendItem(
            'REPEAT',
            Colors.blue,
          ),
        ],
      ),
    );
  }

  Widget _legendItem(
      String label,
      Color color,
      ) {
    return Row(
      mainAxisSize:
      MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration:
          BoxDecoration(
            color: color,
            shape:
            BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style:
          GoogleFonts.cairo(
            fontSize: 10,
            fontWeight:
            FontWeight.w700,
            color:
            _secondaryTextColor,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // BAND CARD
  // ============================================================

  Widget _buildBandCard(
      int bandNumber,
      SAPMainOrder order,
      ) {
    final events =
        _eventsByOrderId[order.id] ??
            const <_AuditEvent>[];

    final journey =
    _buildJourneyRows(order);

    final current =
        journey
            .where(
              (row) =>
          row.status != null &&
              row.status!.isNotEmpty,
        )
            .lastOrNull;

    return Container(
      decoration:
      BoxDecoration(
        color: _surfaceColor,
        borderRadius:
        BorderRadius.circular(14),
        border:
        Border.all(
          color: _borderColor,
        ),
        boxShadow: [
          BoxShadow(
            color:
            Colors.black.withOpacity(
              _isDark ? 0.12 : 0.035,
            ),
            blurRadius: 10,
            offset:
            const Offset(0, 2),
          ),
        ],
      ),

      child: Column(
        children: [
          // ======================================================
          // BAND HEADER
          // ======================================================

          InkWell(
            onTap:
                () => _openTracking(
              order,
            ),

            borderRadius:
            const BorderRadius.vertical(
              top: Radius.circular(14),
            ),

            child: Padding(
              padding:
              const EdgeInsets.all(
                16,
              ),

              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,

                    alignment:
                    Alignment.center,

                    decoration:
                    BoxDecoration(
                      color:
                      const Color(
                        0xFF6366F1,
                      ).withOpacity(
                        0.1,
                      ),
                      borderRadius:
                      BorderRadius.circular(
                        10,
                      ),
                    ),

                    child: Text(
                      bandNumber
                          .toString()
                          .padLeft(
                        2,
                        '0',
                      ),

                      style:
                      GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight:
                        FontWeight.w800,
                        color:
                        const Color(
                          0xFF6366F1,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(
                    width: 12,
                  ),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,

                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'Band ${bandNumber.toString().padLeft(2, '0')}',
                                style:
                                GoogleFonts.cairo(
                                  fontSize:
                                  12,
                                  fontWeight:
                                  FontWeight.w700,
                                  color:
                                  _secondaryTextColor,
                                ),
                              ),
                            ),

                            const SizedBox(
                              width: 8,
                            ),

                            Container(
                              padding:
                              const EdgeInsets
                                  .symmetric(
                                horizontal:
                                7,
                                vertical:
                                2,
                              ),

                              decoration:
                              BoxDecoration(
                                color:
                                _mutedBackground,
                                borderRadius:
                                BorderRadius
                                    .circular(
                                  5,
                                ),
                              ),

                              child: Text(
                                '#${order.itemNumber}',
                                style:
                                GoogleFonts.cairo(
                                  fontSize:
                                  10,
                                  fontWeight:
                                  FontWeight
                                      .w700,
                                  color:
                                  _secondaryTextColor,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(
                          height: 3,
                        ),

                        Text(
                          order.designOrder
                              .isNotEmpty
                              ? order.designOrder
                              : 'No design order',

                          style:
                          GoogleFonts.cairo(
                            fontSize: 16,
                            fontWeight:
                            FontWeight.w800,
                            color:
                            _textColor,
                          ),
                          overflow:
                          TextOverflow
                              .ellipsis,
                        ),

                        const SizedBox(
                          height: 2,
                        ),

                        Text(
                          order.description
                              .isNotEmpty
                              ? order.description
                              : 'No description',

                          maxLines: 1,
                          overflow:
                          TextOverflow
                              .ellipsis,

                          style:
                          GoogleFonts.cairo(
                            fontSize: 11,
                            color:
                            _secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(
                    width: 8,
                  ),

                  _buildCurrentStatus(
                    current?.status ??
                        order.status,
                  ),

                  const SizedBox(
                    width: 8,
                  ),

                  const Icon(
                    Icons
                        .arrow_forward_ios,
                    size: 14,
                  ),
                ],
              ),
            ),
          ),

          Divider(
            height: 1,
            color: _borderColor,
          ),

          // ======================================================
          // QUICK INFO
          // ======================================================

          Padding(
            padding:
            const EdgeInsets.fromLTRB(
              16,
              11,
              16,
              11,
            ),

            child: Wrap(
              spacing: 18,
              runSpacing: 7,
              children: [
                _quickInfo(
                  Icons.schedule,
                  'Created ${_formatDateTime(_createdAt(order))}',
                ),
                _quickInfo(
                  Icons.inventory_2_outlined,
                  'QTY ${order.quantity.toStringAsFixed(0)} ${order.unitOfMeasure}',
                ),
                _quickInfo(
                  Icons.attach_money,
                  '\$${_formatNumber(order.value)}',
                ),
                if ((order.factory ?? '')
                    .trim()
                    .isNotEmpty)
                  _quickInfo(
                    Icons.factory_outlined,
                    order.factory!,
                  ),
                _quickInfo(
                  Icons.history,
                  '${events.length} status events',
                ),
              ],
            ),
          ),

          Divider(
            height: 1,
            color: _borderColor,
          ),

          // ======================================================
          // TIMELINE
          // ======================================================

          Padding(
            padding:
            const EdgeInsets.fromLTRB(
              16,
              16,
              16,
              18,
            ),

            child:
            journey.isEmpty
                ? _buildNoHistory()
                : _buildTimeline(
              journey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStatus(
      String status,
      ) {
    final color =
    _statusColor(status);

    return Container(
      constraints:
      const BoxConstraints(
        maxWidth: 155,
      ),

      padding:
      const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),

      decoration:
      BoxDecoration(
        color:
        color.withOpacity(
          0.1,
        ),
        borderRadius:
        BorderRadius.circular(
          20,
        ),
        border:
        Border.all(
          color:
          color.withOpacity(
            0.3,
          ),
        ),
      ),

      child: Row(
        mainAxisSize:
        MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration:
            BoxDecoration(
              color: color,
              shape:
              BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              status,
              overflow:
              TextOverflow.ellipsis,
              style:
              GoogleFonts.cairo(
                fontSize: 10,
                fontWeight:
                FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TIMELINE
  // ============================================================

  Widget _buildTimeline(
      List<_JourneyRow> rows,
      ) {
    return Column(
      children:
      List.generate(
        rows.length,
            (index) {
          final row =
          rows[index];

          final isLast =
              index ==
                  rows.length - 1;

          return _buildTimelineRow(
            row,
            isLast,
          );
        },
      ),
    );
  }

  Widget _buildTimelineRow(
      _JourneyRow row,
      bool isLast,
      ) {
    final color =
    _statusColor(
      row.status ?? 'Created',
    );

    final duration =
    row.enteredAt == null
        ? Duration.zero
        : _duration(
      row.enteredAt!,
      row.exitedAt,
    );

    final isReverse =
        row.direction ==
            'REVERSE';

    final isReturn =
        row.direction ==
            'RETURN';

    final isRepeat =
        row.direction ==
            'REPEAT';

    final directionColor =
    isReverse
        ? Colors.red
        : isReturn
        ? Colors.orange
        : isRepeat
        ? Colors.blue
        : Colors.green;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.stretch,

        children: [
          // ======================================================
          // VERTICAL LINE
          // ======================================================

          SizedBox(
            width: 28,

            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,

                  decoration:
                  BoxDecoration(
                    color: color,
                    shape:
                    BoxShape.circle,
                    border:
                    Border.all(
                      color:
                      _surfaceColor,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                        color.withOpacity(
                          0.25,
                        ),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),

                if (!isLast)
                  Expanded(
                    child:
                    Container(
                      width: 2,
                      color:
                      _borderColor,
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(
            width: 9,
          ),

          // ======================================================
          // EVENT CONTENT
          // ======================================================

          Expanded(
            child: Padding(
              padding:
              const EdgeInsets.only(
                bottom: 16,
              ),

              child: Container(
                padding:
                const EdgeInsets.all(
                  12,
                ),

                decoration:
                BoxDecoration(
                  color:
                  _mutedBackground,
                  borderRadius:
                  BorderRadius.circular(
                    9,
                  ),
                  border:
                  Border.all(
                    color:
                    _borderColor,
                  ),
                ),

                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,

                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child:
                                Text(
                                  row.eventType ==
                                      'CREATED'
                                      ? 'Contract Created'
                                      : row.status ??
                                      'Unknown',
                                  style:
                                  GoogleFonts.cairo(
                                    fontSize:
                                    13,
                                    fontWeight:
                                    FontWeight.w800,
                                    color:
                                    _textColor,
                                  ),
                                  overflow:
                                  TextOverflow.ellipsis,
                                ),
                              ),

                              if (row.direction
                                  .isNotEmpty &&
                                  row.direction !=
                                      'START') ...[
                                const SizedBox(
                                  width: 7,
                                ),
                                _directionBadge(
                                  row.direction,
                                  directionColor,
                                ),
                              ],
                            ],
                          ),
                        ),

                        Text(
                          _formatDateTime(
                            row.enteredAt ??
                                DateTime.now(),
                          ),
                          style:
                          GoogleFonts.cairo(
                            fontSize: 10,
                            fontWeight:
                            FontWeight.w600,
                            color:
                            _secondaryTextColor,
                          ),
                        ),
                      ],
                    ),

                    if (row.eventType !=
                        'CREATED' &&
                        row.fromStatus !=
                            null &&
                        row.fromStatus!
                            .isNotEmpty) ...[
                      const SizedBox(
                        height: 6,
                      ),

                      Row(
                        children: [
                          Text(
                            row.fromStatus!,
                            style:
                            GoogleFonts.cairo(
                              fontSize: 10,
                              color:
                              _secondaryTextColor,
                              fontWeight:
                              FontWeight.w600,
                            ),
                          ),

                          const Padding(
                            padding:
                            EdgeInsets
                                .symmetric(
                              horizontal:
                              6,
                            ),
                            child:
                            Icon(
                              Icons
                                  .arrow_forward,
                              size:
                              13,
                            ),
                          ),

                          Text(
                            row.status ??
                                '',
                            style:
                            GoogleFonts.cairo(
                              fontSize: 10,
                              color:
                              _textColor,
                              fontWeight:
                              FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(
                      height: 8,
                    ),

                    Wrap(
                      spacing: 14,
                      runSpacing: 5,
                      children: [
                        _timelineMeta(
                          Icons.login,
                          'Entered',
                          row.enteredAt ==
                              null
                              ? '-'
                              : _formatDateTime(
                            row.enteredAt!,
                          ),
                        ),

                        _timelineMeta(
                          Icons.logout,
                          'Exited',
                          row.exitedAt ==
                              null
                              ? 'Still here'
                              : _formatDateTime(
                            row.exitedAt!,
                          ),
                        ),

                        _timelineMeta(
                          Icons.timer_outlined,
                          'Duration',
                          row.enteredAt ==
                              null
                              ? '-'
                              : _formatDuration(
                            duration,
                          ),
                        ),

                        if (row.changedBy
                            .trim()
                            .isNotEmpty)
                          _timelineMeta(
                            Icons.person_outline,
                            'By',
                            row.changedBy,
                          ),
                      ],
                    ),

                    if (isReverse ||
                        isReturn) ...[
                      const SizedBox(
                        height: 9,
                      ),

                      Container(
                        width:
                        double.infinity,
                        padding:
                        const EdgeInsets
                            .symmetric(
                          horizontal: 9,
                          vertical: 7,
                        ),
                        decoration:
                        BoxDecoration(
                          color:
                          directionColor
                              .withOpacity(
                            0.08,
                          ),
                          borderRadius:
                          BorderRadius
                              .circular(
                            7,
                          ),
                          border:
                          Border.all(
                            color:
                            directionColor
                                .withOpacity(
                              0.2,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isReverse
                                  ? Icons
                                  .undo
                                  : Icons
                                  .reply,
                              size: 15,
                              color:
                              directionColor,
                            ),
                            const SizedBox(
                              width: 7,
                            ),
                            Expanded(
                              child:
                              Text(
                                isReverse
                                    ? 'REVERSE MOVEMENT'
                                    : 'RETURN TO PREVIOUS STAGE',
                                style:
                                GoogleFonts.cairo(
                                  fontSize:
                                  10,
                                  fontWeight:
                                  FontWeight
                                      .w800,
                                  color:
                                  directionColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _directionBadge(
      String direction,
      Color color,
      ) {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 2,
      ),
      decoration:
      BoxDecoration(
        color:
        color.withOpacity(
          0.1,
        ),
        borderRadius:
        BorderRadius.circular(
          5,
        ),
      ),
      child: Text(
        direction,
        style:
        GoogleFonts.cairo(
          fontSize: 8,
          fontWeight:
          FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _timelineMeta(
      IconData icon,
      String label,
      String value,
      ) {
    return Row(
      mainAxisSize:
      MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 12,
          color:
          _secondaryTextColor,
        ),
        const SizedBox(
          width: 4,
        ),
        Text(
          '$label: ',
          style:
          GoogleFonts.cairo(
            fontSize: 9,
            color:
            _secondaryTextColor,
            fontWeight:
            FontWeight.w500,
          ),
        ),
        Text(
          value,
          style:
          GoogleFonts.cairo(
            fontSize: 9,
            color:
            _textColor,
            fontWeight:
            FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _quickInfo(
      IconData icon,
      String text,
      ) {
    return Row(
      mainAxisSize:
      MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 13,
          color:
          _secondaryTextColor,
        ),
        const SizedBox(
          width: 5,
        ),
        Text(
          text,
          style:
          GoogleFonts.cairo(
            fontSize: 10,
            color:
            _secondaryTextColor,
            fontWeight:
            FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildNoHistory() {
    return Row(
      children: [
        Icon(
          Icons.history_toggle_off,
          color:
          _secondaryTextColor,
        ),
        const SizedBox(
          width: 8,
        ),
        Text(
          'No status history recorded for this band.',
          style:
          GoogleFonts.cairo(
            fontSize: 11,
            color:
            _secondaryTextColor,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // ERROR / EMPTY
  // ============================================================

  Widget _buildError() {
    return Center(
      child: Padding(
        padding:
        const EdgeInsets.all(30),
        child: Column(
          mainAxisSize:
          MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 55,
              color: Colors.red,
            ),
            const SizedBox(
              height: 12,
            ),
            Text(
              'Could not load contract journey',
              style:
              GoogleFonts.cairo(
                fontSize: 16,
                fontWeight:
                FontWeight.w700,
                color:
                _textColor,
              ),
            ),
            const SizedBox(
              height: 7,
            ),
            Text(
              _error ?? '',
              textAlign:
              TextAlign.center,
              style:
              GoogleFonts.cairo(
                fontSize: 11,
                color:
                _secondaryTextColor,
              ),
            ),
            const SizedBox(
              height: 16,
            ),
            ElevatedButton.icon(
              onPressed:
              _loadContractJourney,
              icon:
              const Icon(
                Icons.refresh,
              ),
              label: Text(
                'Try Again',
                style:
                GoogleFonts.cairo(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize:
        MainAxisSize.min,
        children: [
          Icon(
            Icons.description_outlined,
            size: 60,
            color:
            _secondaryTextColor,
          ),
          const SizedBox(
            height: 12,
          ),
          Text(
            'No bands found for this contract',
            style:
            GoogleFonts.cairo(
              color:
              _secondaryTextColor,
              fontWeight:
              FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // STATUS COLORS
  // ============================================================

  Color _statusColor(
      String status,
      ) {
    switch (
    _normalizeStatus(
      _displayStatus(status),
    )) {
      case 'drawing submittal':
        return Colors.blue;

      case 'approval':
        return Colors.indigo;

      case 'modifications submitted':
        return Colors.orange;

      case 'manufacturing drawing':
        return Colors.deepPurple;

      case 'master data':
        return Colors.teal;

      case 'done':
        return Colors.green;

      default:
        return _secondaryTextColor;
    }
  }

  // ============================================================
  // DATE / NUMBER
  // ============================================================

  String _formatDateTime(
      DateTime? date,
      ) {
    if (date == null) return '';

    return DateFormat(
      'dd MMM yyyy • HH:mm',
    ).format(date);
  }

  String _formatDateTimeNullable(
      DateTime? date,
      ) {
    if (date == null) {
      return '';
    }

    return _formatDateTime(date);
  }

  String _formatDate(
      DateTime? date,
      ) {
    if (date == null) return '-';

    return DateFormat(
      'dd MMM yyyy',
    ).format(date);
  }

  String _formatNumber(
      double number,
      ) {
    if (number == 0) {
      return '0.00';
    }

    final parts =
    number.toStringAsFixed(2)
        .split('.');

    final buffer =
    StringBuffer();

    for (
    int i = 0;
    i < parts[0].length;
    i++
    ) {
      if (i > 0 &&
          (parts[0].length - i) %
              3 ==
              0) {
        buffer.write(',');
      }

      buffer.write(
        parts[0][i],
      );
    }

    return '${buffer.toString()}.${parts[1]}';
  }

  // ============================================================
  // SNACKBAR
  // ============================================================

  void _showSnackBar(
      String message,
      ) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).hideCurrentSnackBar();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style:
          GoogleFonts.cairo(
            fontSize: 12,
            fontWeight:
            FontWeight.w600,
          ),
        ),
        behavior:
        SnackBarBehavior.floating,
        duration:
        const Duration(
          seconds: 3,
        ),
        margin:
        const EdgeInsets.all(
          16,
        ),
        shape:
        RoundedRectangleBorder(
          borderRadius:
          BorderRadius.circular(
            10,
          ),
        ),
      ),
    );
  }
}

// ==================================================================
// AUDIT EVENT MODEL
// ==================================================================

class _AuditEvent {
  final String id;
  final String orderId;
  final String oldValue;
  final String newValue;
  final DateTime changedAt;
  final String changedBy;
  final String changedById;

  const _AuditEvent({
    required this.id,
    required this.orderId,
    required this.oldValue,
    required this.newValue,
    required this.changedAt,
    required this.changedBy,
    required this.changedById,
  });
}

// ==================================================================
// JOURNEY ROW MODEL
// ==================================================================

class _ExcelTransition {
  final String type;
  final DateTime changedAt;
  final Duration duration;

  const _ExcelTransition({
    required this.type,
    required this.changedAt,
    required this.duration,
  });
}

class _JourneyRow {
  final String eventType;
  final String? status;
  final String? fromStatus;
  final DateTime? enteredAt;
  final DateTime? exitedAt;
  final String direction;
  final String changedBy;
  final _AuditEvent? event;

  const _JourneyRow({
    required this.eventType,
    required this.status,
    required this.fromStatus,
    required this.enteredAt,
    required this.exitedAt,
    required this.direction,
    required this.changedBy,
    required this.event,
  });

  factory _JourneyRow.created({
    required DateTime? time,
  }) {
    return _JourneyRow(
      eventType: 'CREATED',
      status: null,
      fromStatus: null,
      enteredAt: time,
      exitedAt: null,
      direction: 'START',
      changedBy: '',
      event: null,
    );
  }

  factory _JourneyRow.stage({
    required String status,
    required DateTime? enteredAt,
    required DateTime? exitedAt,
    required String? fromStatus,
    required String changedBy,
    required _AuditEvent? event,
    required String direction,
  }) {
    return _JourneyRow(
      eventType: 'STATUS',
      status: status,
      fromStatus: fromStatus,
      enteredAt: enteredAt,
      exitedAt: exitedAt,
      direction: direction,
      changedBy: changedBy,
      event: event,
    );
  }
}

// ==================================================================
// SMALL EXTENSION
// ==================================================================

extension _IterableLastOrNull<T> on Iterable<T> {
  T? get lastOrNull =>
      isEmpty ? null : last;
}
