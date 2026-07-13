import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../data/store.dart';
import '../ui/screens/admin/admin_helpers.dart';

/// Builds an .xlsx file for a single employee's monthly timesheet.
/// Returns raw bytes ready for download.
Uint8List buildMonthlyExcelExport({
  required Employee employee,
  required DateTime month,
  required List<TimeEvent> monthEvents,
  required Map<String, Map<String, dynamic>> overrides,
  String? approvedBy,
  DateTime? approvedAt,
}) {
  final excel = Excel.createExcel();
  final sheetName = monthLabel(month);
  excel.rename('Sheet1', sheetName);
  final sheet = excel[sheetName];

  // ── Styles ──
  final headerStyle = CellStyle(
    bold: true,
    backgroundColorHex: ExcelColor.fromHexString('#4472C4'),
    fontColorHex: ExcelColor.white,
    horizontalAlign: HorizontalAlign.Center,
  );
  final boldStyle = CellStyle(bold: true);
  final rightBold = CellStyle(bold: true, horizontalAlign: HorizontalAlign.Right);

  // ── Row 0: Title ──
  final title = 'Stundennachweis - ${employee.name} (${employee.id}) - ${monthLabel(month)}';
  sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = TextCellValue(title);
  sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).cellStyle = boldStyle;
  sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0), CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: 0));

  // ── Row 1: Approval ──
  if (approvedBy != null && approvedBy.isNotEmpty) {
    final approvedAtStr = approvedAt != null
        ? '${approvedAt.day.toString().padLeft(2, '0')}.${approvedAt.month.toString().padLeft(2, '0')}.${approvedAt.year}'
        : '—';
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value =
        TextCellValue('Geprueft von: $approvedBy am $approvedAtStr');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).cellStyle = boldStyle;
    sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1), CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: 1));
  }

  // ── Row 3: Column headers ──
  const headers = [
    'Datum',
    'Wochentag',
    'Kommen',
    'Gehen',
    'Pause Start',
    'Pause Ende',
    'Brutto',
    'Pause',
    'Netto',
    'Quelle',
    'Bemerkung',
  ];
  for (var c = 0; c < headers.length; c++) {
    final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 3));
    cell.value = TextCellValue(headers[c]);
    cell.cellStyle = headerStyle;
  }

  // ── Column widths ──
  sheet.setColumnWidth(0, 14); // Datum
  sheet.setColumnWidth(1, 12); // Wochentag
  sheet.setColumnWidth(2, 10); // Kommen
  sheet.setColumnWidth(3, 10); // Gehen
  sheet.setColumnWidth(4, 12); // Pause Start
  sheet.setColumnWidth(5, 12); // Pause Ende
  sheet.setColumnWidth(6, 10); // Brutto
  sheet.setColumnWidth(7, 10); // Pause
  sheet.setColumnWidth(8, 10); // Netto
  sheet.setColumnWidth(9, 10); // Quelle
  sheet.setColumnWidth(10, 30); // Bemerkung

  // ── Day rows ──
  final byDay = groupEventsByDayKey(monthEvents);
  final start = startOfMonthLocal(month);
  final end = endOfMonthLocal(month);

  final dowNames = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
  Duration totalBrutto = Duration.zero;
  Duration totalPause = Duration.zero;
  Duration totalNetto = Duration.zero;

  var rowIdx = 4;
  for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
    final dk = dayKeyLocal(d);
    final ov = overrides[dk];
    final autoDayEvents = byDay[dk] ?? const <TimeEvent>[];
    final summary = (ov != null) ? summaryFromOverrideMerged(ov, autoDayEvents) : summaryFromEventsForDay(autoDayEvents);

    final dateStr = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    final dowStr = dowNames[(d.weekday - 1).clamp(0, 6)];

    final brutto = safeDiff(summary.inTime, summary.outTime);
    final pause = safeDiff(summary.breakStart, summary.breakEnd);

    totalBrutto += brutto;
    totalPause += pause;
    totalNetto += summary.net;

    final reason = summary.reason ?? '';

    final values = [
      TextCellValue(dateStr),
      TextCellValue(dowStr),
      TextCellValue(hhmm(summary.inTime)),
      TextCellValue(hhmm(summary.outTime)),
      TextCellValue(hhmm(summary.breakStart)),
      TextCellValue(hhmm(summary.breakEnd)),
      TextCellValue(durHHMM(brutto)),
      TextCellValue(durHHMM(pause)),
      TextCellValue(durHHMM(summary.net)),
      TextCellValue(summary.sourceLabel),
      TextCellValue(reason),
    ];

    for (var c = 0; c < values.length; c++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIdx)).value = values[c];
    }

    // Grey out weekends
    if (d.weekday >= 6) {
      final weekendStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString('#F0F0F4'),
      );
      for (var c = 0; c < values.length; c++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIdx)).cellStyle = weekendStyle;
      }
    }

    rowIdx++;
  }

  // ── Summary row ──
  rowIdx++; // blank row
  sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx)).value = TextCellValue('GESAMT');
  sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx)).cellStyle = boldStyle;
  sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIdx)).value = TextCellValue(durHHMM(totalBrutto));
  sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIdx)).cellStyle = rightBold;
  sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIdx)).value = TextCellValue(durHHMM(totalPause));
  sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIdx)).cellStyle = rightBold;
  sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIdx)).value = TextCellValue(durHHMM(totalNetto));
  sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIdx)).cellStyle = rightBold;

  final encoded = excel.encode();
  if (encoded == null) throw Exception('Excel encoding failed');
  return Uint8List.fromList(encoded);
}
