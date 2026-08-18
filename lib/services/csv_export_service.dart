import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:mobitem/services/sap_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;

class ExcelExportService {
  static Future<String> exportOrdersToExcel(
      List<SAPMainOrder> orders,
      ) async {
    final excel = Excel.createExcel();
    final sheet = excel['Orders'];

    // ==========================================
    // HEADER STYLE
    // ==========================================
    final headerStyle = CellStyle(
      bold: true,
      fontSize: 11,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      backgroundColorHex: ExcelColor.fromHexString('#1F4E78'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
    );

    // ==========================================
    // STATUS SECTION HEADER STYLE
    // ==========================================
    final statusHeaderStyle = CellStyle(
      bold: true,
      fontSize: 14,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      backgroundColorHex: ExcelColor.fromHexString('#4472C4'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
    );

    // ==========================================
    // TOTAL ROW STYLE
    // ==========================================
    final totalRowStyle = CellStyle(
      bold: true,
      fontSize: 11,
      backgroundColorHex: ExcelColor.fromHexString('#D6DCE4'),
      fontColorHex: ExcelColor.fromHexString('#1F4E78'),
    );

    // ==========================================
    // NORMAL DATA STYLE
    // ==========================================
    final dataStyle = CellStyle(
      fontSize: 11,
      verticalAlign: VerticalAlign.Center,
    );

    // ==========================================
    // HEADERS
    // ==========================================
    final headers = [
      'Name',
      'Status',
      'Item',
      'Product Code',
      'Contract Num',
      'Description',
      'Design Order',
      'QTY',
      'Unit of Measure',
      'Value',
      'Sales Engineer',
      'O-Date',
      'Delivery Date',
      'Factory',
      'Design Team',
      'Responsible Engineer',
      'Reviewer',
      'Alternative Engineer',
    ];

    // ==========================================
    // GROUP ORDERS BY STATUS
    // ==========================================
    final groupedOrders = <String, List<SAPMainOrder>>{};
    for (var order in orders) {
      final status = order.status;
      groupedOrders.putIfAbsent(status, () => []).add(order);
    }

    // ==========================================
    // SORT STATUSES IN THE ORIGINAL LIST ORDER
    // ==========================================
    final statusOrder = [
      'Drawing Submittal',
      'Approval',
      'modifications submitted',
      'Manufacturing Drawing',
      'Done',
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
      'Unknown',
      'pending',
      'in_progress',
      'completed',
      'on_hold',
    ];

    final sortedStatuses = groupedOrders.keys.toList()
      ..sort((a, b) {
        final indexA = statusOrder.indexOf(a);
        final indexB = statusOrder.indexOf(b);
        if (indexA == -1 && indexB == -1) return a.compareTo(b);
        if (indexA == -1) return 1;
        if (indexB == -1) return -1;
        return indexA.compareTo(indexB);
      });

    // ==========================================
    // WRITE DATA WITH SECTIONS
    // ==========================================
    int currentRow = 0;

    for (var status in sortedStatuses) {
      final statusOrders = groupedOrders[status]!;

      // ==========================================
      // STATUS SECTION HEADER ROW (spans all columns)
      // ==========================================
      for (int col = 0; col < headers.length; col++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: col,
            rowIndex: currentRow,
          ),
        );

        if (col == 0) {
          cell.value = TextCellValue('$status (${statusOrders.length} orders)');
          cell.cellStyle = statusHeaderStyle;
        } else {
          cell.value = TextCellValue('');
          cell.cellStyle = CellStyle(
            backgroundColorHex: ExcelColor.fromHexString('#4472C4'),
          );
        }
      }

      sheet.setRowHeight(currentRow, 30.0);
      currentRow++;

      // ==========================================
      // COLUMN HEADERS ROW
      // ==========================================
      for (int col = 0; col < headers.length; col++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: col,
            rowIndex: currentRow,
          ),
        );

        cell.value = TextCellValue(headers[col]);
        cell.cellStyle = headerStyle;
      }

      sheet.setRowHeight(currentRow, 25.0);
      currentRow++;

      // ==========================================
      // DATA ROWS FOR THIS STATUS
      // ==========================================
      double sectionTotalValue = 0;

      for (var order in statusOrders) {
        final values = [
          order.customerName,
          order.status,
          order.itemNumber,
          order.productCode,
          order.contractNumber,
          order.description,
          order.designOrder,
          order.quantity,
          order.unitOfMeasure,
          order.value,
          order.salesEngineer,
          order.orderDate ?? '',
          order.deliveryDate ?? '',
          order.factory ?? '',
          order.designTeam ?? '',
          order.responsibleEngineer ?? '',
          order.reviewer ?? '',
          order.correspondenceEngineer ?? '',
        ];

        for (int col = 0; col < values.length; col++) {
          final cell = sheet.cell(
            CellIndex.indexByColumnRow(
              columnIndex: col,
              rowIndex: currentRow,
            ),
          );

          final value = values[col];

          if (value is num) {
            cell.value = DoubleCellValue(value.toDouble());
          } else {
            cell.value = TextCellValue(value.toString());
          }

          cell.cellStyle = dataStyle;
        }

        // ==========================================
        // STATUS CELL HIGHLIGHT
        // ==========================================
        final statusCell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: 1,
            rowIndex: currentRow,
          ),
        );

        statusCell.cellStyle = _getStatusCellStyle(order.status);

        // Accumulate value
        sectionTotalValue += order.value;

        currentRow++;
      }

      // ==========================================
      // TOTAL VALUE ROW
      // ==========================================
      for (int col = 0; col < headers.length; col++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: col,
            rowIndex: currentRow,
          ),
        );

        if (col == 0) {
          cell.value = TextCellValue('Total for $status (${statusOrders.length} orders)');
        } else if (col == 9) {
          // Value column
          cell.value = DoubleCellValue(sectionTotalValue);
          cell.cellStyle = CellStyle(
            bold: true,
            fontSize: 11,
            backgroundColorHex: ExcelColor.fromHexString('#D6DCE4'),
            fontColorHex: ExcelColor.fromHexString('#1F4E78'),
            horizontalAlign: HorizontalAlign.Right,
          );
          continue;
        } else {
          cell.value = TextCellValue('');
        }

        cell.cellStyle = totalRowStyle;
      }

      sheet.setRowHeight(currentRow, 22.0);
      currentRow++;

      // ==========================================
      // EMPTY ROW BETWEEN SECTIONS
      // ==========================================
      currentRow++;
    }

    // ==========================================
    // COLUMN WIDTHS
    // ==========================================
    final widths = <double>[
      25.0, // Name
      18.0, // Status
      12.0, // Item
      18.0, // Product Code
      18.0, // Contract Num
      35.0, // Description
      18.0, // Design Order
      10.0, // QTY
      18.0, // Unit of Measure
      15.0, // Value
      20.0, // Sales Engineer
      15.0, // O-Date
      18.0, // Delivery Date
      15.0, // Factory
      20.0, // Design Team
      25.0, // Responsible Engineer
      20.0, // Reviewer
      25.0, // Correspondence Engineer
    ];

    for (int i = 0; i < widths.length; i++) {
      sheet.setColumnWidth(i, widths[i]);
    }

    // ==========================================
    // GENERATE XLSX
    // ==========================================
    final bytes = excel.encode();

    if (bytes == null) {
      throw Exception('Failed to generate Excel file');
    }

    final fileName =
        'orders_export_${DateTime.now().millisecondsSinceEpoch}.xlsx';

    // ==========================================
    // FLUTTER WEB
    // ==========================================
    if (kIsWeb) {
      final blob = html.Blob(
        [Uint8List.fromList(bytes)],
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );

      final url = html.Url.createObjectUrlFromBlob(blob);

      final anchor = html.AnchorElement()
        ..href = url
        ..style.display = 'none'
        ..download = fileName;

      html.document.body!.children.add(anchor);
      anchor.click();
      html.document.body!.children.remove(anchor);
      html.Url.revokeObjectUrl(url);

      return fileName;
    }

    // ==========================================
    // DESKTOP / MOBILE
    // ==========================================
    final directory = await getTemporaryDirectory();
    final filePath = '${directory.path}/$fileName';
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);

    return filePath;
  }

  // ==========================================
  // STATUS CELL STYLE HELPER
  // ==========================================
  static CellStyle _getStatusCellStyle(String status) {
    final lower = status.toLowerCase();

    if (lower.contains('complete') || lower.contains('done')) {
      return CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('#008000'),
        backgroundColorHex: ExcelColor.fromHexString('#E2F0D9'),
      );
    } else if (lower.contains('pending') || lower.contains('review')) {
      return CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('#9C6500'),
        backgroundColorHex: ExcelColor.fromHexString('#FFF2CC'),
      );
    } else if (lower.contains('cancel') || lower.contains('failed')) {
      return CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('#C00000'),
        backgroundColorHex: ExcelColor.fromHexString('#F4CCCC'),
      );
    } else if (lower.contains('approval') || lower.contains('manufacturing')) {
      return CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('#1F4E78'),
        backgroundColorHex: ExcelColor.fromHexString('#D6E4F0'),
      );
    } else if (lower.contains('drawing')) {
      return CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('#7030A0'),
        backgroundColorHex: ExcelColor.fromHexString('#E5DFEC'),
      );
    } else if (lower.contains('master') || lower.contains('data')) {
      return CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('#00B0F0'),
        backgroundColorHex: ExcelColor.fromHexString('#D9F2FF'),
      );
    } else if (lower.contains('sales')) {
      return CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('#ED7D31'),
        backgroundColorHex: ExcelColor.fromHexString('#FDE9D9'),
      );
    } else if (lower.contains('tasks')) {
      return CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('#5B9BD5'),
        backgroundColorHex: ExcelColor.fromHexString('#DEEBF7'),
      );
    } else if (lower.contains('planning')) {
      return CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('#FF0000'),
        backgroundColorHex: ExcelColor.fromHexString('#FFE0E0'),
      );
    } else {
      return CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('#808080'),
        backgroundColorHex: ExcelColor.fromHexString('#E0E0E0'),
      );
    }
  }
}