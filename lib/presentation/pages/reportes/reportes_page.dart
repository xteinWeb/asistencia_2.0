import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:go_router/go_router.dart';
import '../../../core/routes/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/file_saver.dart';
import '../../../data/datasources/local/database_helper.dart';
import '../../../data/models/empleado_model.dart';
import '../../../data/models/registro_model.dart';
import '../../../data/models/ausentismo_model.dart';

class ReportesPage extends StatefulWidget {
  const ReportesPage({super.key});

  @override
  State<ReportesPage> createState() => _ReportesPageState();
}

class _ReportesPageState extends State<ReportesPage> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  DateTimeRange? _selectedDateRange;
  List<EmpleadoModel> _empleados = [];
  EmpleadoModel? _selectedEmpleado; // null means "Todos"
  
  bool _isLoading = false;
  List<RegistroModel> _allRegistros = [];
  List<AusentismoModel> _allAusentismos = [];
  List<String> _datesInRange = [];
  List<Map<String, dynamic>> _reportGridData = [];

  // Stats
  int _totalAsistencias = 0;
  int _totalRetardos = 0;
  int _totalAusentismos = 0;
  double _attendanceRate = 0.0;
  int _totalDaysSelected = 0;
  int _rowsPerPage = 10;

  @override
  void initState() {
    super.initState();
    // Default range: last 7 days
    final now = DateTime.now();
    _selectedDateRange = DateTimeRange(
      start: now.subtract(const Duration(days: 7)),
      end: now,
    );
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final emps = await _dbHelper.getAllEmpleados();
      setState(() {
        _empleados = emps.where((e) => e.estado.toUpperCase() == 'ACTIVO').toList();
      });
      await _generateReport();
    } catch (e) {
      _showSnackBar('Error al cargar datos iniciales: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _generateReport() async {
    if (_selectedDateRange == null) return;
    
    final startStr = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start);
    final endStr = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end);
    
    _totalDaysSelected = _selectedDateRange!.end.difference(_selectedDateRange!.start).inDays + 1;

    // Generate sorted list of dates in the range
    final List<String> tempDates = [];
    for (int i = 0; i < _totalDaysSelected; i++) {
      final date = _selectedDateRange!.start.add(Duration(days: i));
      tempDates.add(DateFormat('yyyy-MM-dd').format(date));
    }

    try {
      final regs = await _dbHelper.getRegistrosRango(startStr, endStr);
      final aus = await _dbHelper.getAusentismosRango(startStr, endStr);
      
      _allRegistros = regs;
      _allAusentismos = aus;
      _datesInRange = tempDates;

      // Filter target employees
      List<EmpleadoModel> targetEmpleados = [];
      if (_selectedEmpleado != null) {
        targetEmpleados = [_selectedEmpleado!];
      } else {
        targetEmpleados = await _dbHelper.getAllEmpleados();
      }

      final List<Map<String, dynamic>> gridRows = [];
      int tempAsistencias = 0;
      int tempRetardos = 0;
      int tempAusentismos = 0;

      for (var emp in targetEmpleados) {
        DateTime? registrationDate;
        if (emp.fechaRegistro != null && emp.fechaRegistro!.isNotEmpty) {
          try {
            registrationDate = DateTime.parse(emp.fechaRegistro!.substring(0, 10));
          } catch (_) {}
        }

        final Map<String, Map<String, String>> datesDetails = {};
        int empAsistencias = 0;
        int empRetardos = 0;
        int empAusentismos = 0;
        bool hasAnyActivity = false;

        for (var dateStr in _datesInRange) {
          final currentDate = DateTime.parse(dateStr);

          // Find clock-ins/outs
          final dayRegs = _allRegistros.where((r) => 
            r.cedula == emp.cedula && 
            r.fechaHora.startsWith(dateStr)
          ).toList();

          // Find absence/ausentismo
          final dayAus = _allAusentismos.firstWhere((a) => 
            a.cedulaEmpleado == emp.cedula && 
            a.fecha == dateStr,
            orElse: () => AusentismoModel(id: '', cedulaEmpleado: '', fecha: '', siglaAusencia: '')
          );

          final hasRealData = dayRegs.isNotEmpty || (dayAus.id != null && dayAus.id!.isNotEmpty);

          // Skip if date is before registration date or after contract end (unless we have real data)
          if (!hasRealData && registrationDate != null && currentDate.isBefore(registrationDate)) {
            datesDetails[dateStr] = {
              'estado': 'No Registrado',
              'entrada': '-',
              'salida': '-',
              'observacion': 'Previo a Registro',
            };
            continue;
          }

          if (!hasRealData && emp.fechaFinContrato != null && emp.fechaFinContrato!.isNotEmpty) {
            try {
              final finContrato = DateTime.parse(emp.fechaFinContrato!.substring(0, 10));
              if (currentDate.isAfter(finContrato)) {
                datesDetails[dateStr] = {
                  'estado': 'No Registrado',
                  'entrada': '-',
                  'salida': '-',
                  'observacion': 'Contrato Terminado',
                };
                continue;
              }
            } catch (_) {}
          }

          hasAnyActivity = true;

          final checkIn = dayRegs.firstWhere((r) => r.evento.toUpperCase() == 'ENTRADA', orElse: () => RegistroModel(
            id: '', fechaHora: '', cedula: '', evento: '', tipo: '', unidadNegocio: ''
          ));
          final checkOut = dayRegs.firstWhere((r) => r.evento.toUpperCase() == 'SALIDA', orElse: () => RegistroModel(
            id: '', fechaHora: '', cedula: '', evento: '', tipo: '', unidadNegocio: ''
          ));

          String status = 'No Registró';
          String timeIn = '-';
          String timeOut = '-';
          String obs = '';

          if (checkIn.id != null && checkIn.id!.isNotEmpty) {
            timeIn = _formatTime(checkIn.fechaHora);
            if (checkIn.tipo.toUpperCase() == 'RETARDO') {
              status = 'Retardo';
              empRetardos++;
              tempRetardos++;
            } else {
              status = 'Asistió';
              empAsistencias++;
              tempAsistencias++;
            }
          }

          if (checkOut.id != null && checkOut.id!.isNotEmpty) {
            timeOut = _formatTime(checkOut.fechaHora);
          }

          if (dayAus.id != null && dayAus.id!.isNotEmpty) {
            status = 'Ausente (${dayAus.siglaAusencia})';
            obs = dayAus.observacion ?? '';
            empAusentismos++;
            tempAusentismos++;
          } else if (status == 'No Registró') {
            final isWeekend = currentDate.weekday == DateTime.saturday || currentDate.weekday == DateTime.sunday;
            if (isWeekend) {
              status = 'Fin de Semana';
            }
          }

          datesDetails[dateStr] = {
            'estado': status,
            'entrada': timeIn,
            'salida': timeOut,
            'observacion': obs,
          };
        }

        // Only include employees who are active or had contract days/activity in the selected range
        if (emp.estado.toUpperCase() == 'ACTIVO' || hasAnyActivity) {
          gridRows.add({
            'cedula': emp.cedula,
            'nombre': emp.nombre,
            'asistencias': empAsistencias,
            'retardos': empRetardos,
            'ausentismos': empAusentismos,
            'fechas': datesDetails,
          });
        }
      }

      // Sort rows alphabetically by employee name
      gridRows.sort((a, b) => a['nombre'].toString().compareTo(b['nombre'].toString()));

      setState(() {
        _reportGridData = gridRows;
        _totalAsistencias = tempAsistencias;
        _totalRetardos = tempRetardos;
        _totalAusentismos = tempAusentismos;
        final totalDenominator = tempAsistencias + tempRetardos + tempAusentismos;
        _attendanceRate = totalDenominator > 0
            ? ((tempAsistencias + tempRetardos) / totalDenominator) * 100
            : 100.0;
      });
    } catch (e) {
      _showSnackBar('Error al generar reporte: $e', isError: true);
    }
  }

  String _formatTime(String datetimeStr) {
    if (datetimeStr.length < 16) return datetimeStr;
    try {
      final dt = DateTime.parse(datetimeStr);
      return DateFormat('hh:mm a').format(dt);
    } catch (_) {
      return datetimeStr;
    }
  }

  Future<void> _exportToExcel() async {
    if (_reportGridData.isEmpty) {
      _showSnackBar('No hay datos en el reporte para exportar.', isError: true);
      return;
    }

    try {
      final StringBuffer csvBuffer = StringBuffer();
      // Add UTF-8 BOM
      csvBuffer.write('\uFEFF');
      
      // Pivot Headers: Cédula;Nombre;[Date 1];[Date 2];...;Asistencias;Retardos;Ausencias
      csvBuffer.write('Cédula;Nombre');
      for (var dateStr in _datesInRange) {
        final formattedDate = DateFormat('dd/MM/yyyy').format(DateTime.parse(dateStr));
        csvBuffer.write(';$formattedDate');
      }
      csvBuffer.writeln(';Asistencias;Retardos;Ausencias');

      // Grid Rows
      for (var row in _reportGridData) {
        csvBuffer.write('${row['cedula']};${row['nombre']}');
        
        final datesDetails = row['fechas'] as Map<String, Map<String, String>>;
        for (var dateStr in _datesInRange) {
          final detail = datesDetails[dateStr];
          String cellVal = '-';
          if (detail != null) {
            final estado = detail['estado']!;
            if (estado == 'Asistió') {
              cellVal = 'Asistió (${detail['entrada']})';
            } else if (estado == 'Retardo') {
              cellVal = 'Retardo (${detail['entrada']})';
            } else if (estado.startsWith('Ausente')) {
              final obs = detail['observacion']!.isNotEmpty ? ' - ${detail['observacion']}' : '';
              cellVal = '$estado$obs';
            } else {
              cellVal = estado;
            }
          }
          csvBuffer.write(';"${cellVal.replaceAll('"', '""')}"');
        }

        csvBuffer.writeln(';${row['asistencias']};${row['retardos']};${row['ausentismos']}');
      }

      final startStr = DateFormat('yyyyMMdd').format(_selectedDateRange!.start);
      final endStr = DateFormat('yyyyMMdd').format(_selectedDateRange!.end);
      final fileName = _selectedEmpleado != null
          ? 'Reporte_Matriz_${_selectedEmpleado!.cedula}_${startStr}_a_${endStr}.csv'
          : 'Reporte_Matriz_General_${startStr}_a_${endStr}.csv';

      if (kIsWeb) {
        saveFile(csvBuffer.toString(), fileName);
        _showSuccessDialogWeb(fileName);
        return;
      }

      Directory? directory;
      if (Platform.isWindows) {
        directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);
      await file.writeAsString(csvBuffer.toString());

      if (Platform.isWindows) {
        try {
          await Process.run('cmd', ['/c', 'start', '""', filePath]);
        } catch (_) {}
      }

      _showSuccessDialog(filePath, fileName);
    } catch (e) {
      _showSnackBar('Error al exportar archivo: $e', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessDialog(String path, String fileName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.check_circle_outline, color: AppColors.success, size: 28),
            SizedBox(width: 8),
            Text('Reporte Exportado'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('El archivo Excel (CSV) se ha generado exitosamente:'),
            const SizedBox(height: 12),
            SelectableText(
              fileName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ubicación:',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            SelectableText(
              path,
              style: const TextStyle(fontSize: 12, color: AppColors.primary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialogWeb(String fileName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.check_circle_outline, color: AppColors.success, size: 28),
            SizedBox(width: 8),
            Text('Reporte Descargado'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('El archivo Excel (CSV) en formato de cuadrícula se ha descargado exitosamente:'),
            const SizedBox(height: 12),
            SelectableText(
              fileName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final startStr = _selectedDateRange == null ? '' : DateFormat('dd/MM/yyyy').format(_selectedDateRange!.start);
    final endStr = _selectedDateRange == null ? '' : DateFormat('dd/MM/yyyy').format(_selectedDateRange!.end);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportes de Asistencia'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.home),
        ),
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              elevation: 2,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            onPressed: _reportGridData.isEmpty ? null : _exportToExcel,
            icon: const Icon(Icons.description),
            label: const Text('Excel'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _generateReport,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFilters(startStr, endStr),
                      const SizedBox(height: 20),
                      _buildStatsRow(),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Cuadrícula de Control de Asistencias',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (_reportGridData.isNotEmpty)
                            const Text(
                              'Desliza horizontalmente para ver las fechas',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildGridTable(),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildFilters(String startStr, String endStr) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Parámetros del Reporte',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 600;
                return Flex(
                  direction: isWide ? Axis.horizontal : Axis.vertical,
                  children: [
                    Expanded(
                      flex: isWide ? 1 : 0,
                      child: InkWell(
                        onTap: _pickDateRange,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.date_range, color: AppColors.primary),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Rango de Fechas', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                  Text('$startStr - $endStr', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                ],
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (!isWide) const SizedBox(height: 12),
                    if (isWide) const SizedBox(width: 16),
                    Expanded(
                      flex: isWide ? 1 : 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<EmpleadoModel?>(
                            isExpanded: true,
                            value: _selectedEmpleado,
                            hint: const Text('Todos los Empleados'),
                            items: [
                              const DropdownMenuItem<EmpleadoModel?>(
                                value: null,
                                child: Text('Todos los Empleados'),
                              ),
                              ..._empleados.map((emp) => DropdownMenuItem<EmpleadoModel?>(
                                    value: emp,
                                    child: Text('${emp.nombre} (${emp.cedula})'),
                                  )),
                            ],
                            onChanged: (val) {
                              setState(() {
                                _selectedEmpleado = val;
                              });
                              _generateReport();
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 700;
        final cards = [
          _buildStatCard(
            title: 'Tasa de Asistencia',
            value: '${_attendanceRate.toStringAsFixed(1)}%',
            subtitle: 'Presente vs Ausencias',
            icon: Icons.check_circle_outline,
            color: AppColors.success,
          ),
          _buildStatCard(
            title: 'Asistencias',
            value: '$_totalAsistencias',
            subtitle: 'Registros normales',
            icon: Icons.check,
            color: AppColors.info,
          ),
          _buildStatCard(
            title: 'Retardos',
            value: '$_totalRetardos',
            subtitle: 'Llegadas tarde',
            icon: Icons.warning_amber_rounded,
            color: AppColors.warning,
          ),
          _buildStatCard(
            title: 'Ausencias',
            value: '$_totalAusentismos',
            subtitle: 'Justificadas/Injustificadas',
            icon: Icons.event_busy,
            color: AppColors.error,
          ),
        ];

        if (isWide) {
          return Row(
            children: cards.map((c) => Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: c,
            ))).toList(),
          );
        } else {
          return GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.4,
            children: cards,
          );
        }
      },
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(icon, color: color, size: 20),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 10, color: AppColors.textDisabled),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridTable() {
    if (_reportGridData.isEmpty) {
      return Card(
        elevation: 2,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(32),
          child: Column(
            children: const [
              Icon(Icons.calendar_today_outlined, size: 48, color: AppColors.textDisabled),
              SizedBox(height: 16),
              Text(
                'No se encontraron registros',
                style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary),
              ),
              SizedBox(height: 4),
              Text(
                'Intente cambiando el rango de fechas o los filtros.',
                style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final dataSource = _ReportDataTableSource(
          data: _reportGridData,
          datesInRange: _datesInRange,
          buildBadgeCell: _buildBadgeCell,
          showCellDetailsDialog: _showCellDetailsDialog,
        );

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: PaginatedDataTable(
              header: const Text('Asistencias por Empleado'),
              rowsPerPage: _rowsPerPage,
              onRowsPerPageChanged: (value) {
                if (value != null) {
                  setState(() {
                    _rowsPerPage = value;
                  });
                }
              },
              availableRowsPerPage: const [5, 10, 20, 50],
              columnSpacing: 15,
              horizontalMargin: 10,
              showCheckboxColumn: false,
              columns: [
                const DataColumn(
                  label: Text(
                    'Empleado / Nombre',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                ),
                ..._datesInRange.map((dateStr) {
                  final parsedDate = DateTime.parse(dateStr);
                  final dayLabel = DateFormat('dd MMM').format(parsedDate);
                  return DataColumn(
                    label: Text(
                      dayLabel,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  );
                }),
                const DataColumn(
                  label: Text('Asist.', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.success)),
                  numeric: true,
                ),
                const DataColumn(
                  label: Text('Ret.', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.warning)),
                  numeric: true,
                ),
                const DataColumn(
                  label: Text('Aus.', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.error)),
                  numeric: true,
                ),
              ],
              source: dataSource,
            ),
          ),
        );
      },
    );
  }
}

class _ReportDataTableSource extends DataTableSource {
  final List<Map<String, dynamic>> data;
  final List<String> datesInRange;
  final Widget Function(Map<String, String>) buildBadgeCell;
  final void Function(String, String, Map<String, String>) showCellDetailsDialog;

  _ReportDataTableSource({
    required this.data,
    required this.datesInRange,
    required this.buildBadgeCell,
    required this.showCellDetailsDialog,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= data.length) return null;
    final row = data[index];
    final datesDetails = row['fechas'] as Map<String, Map<String, String>>;

    return DataRow.byIndex(
      index: index,
      cells: [
        DataCell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                row['nombre'].toString(),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'C.C. ${row['cedula']}',
                style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        ...datesInRange.map((dateStr) {
          final detail = datesDetails[dateStr];
          if (detail == null) {
            return const DataCell(Center(child: Text('-')));
          }
          return DataCell(
            buildBadgeCell(detail),
            onTap: () => showCellDetailsDialog(row['nombre'].toString(), dateStr, detail),
          );
        }),
        DataCell(Text(row['asistencias'].toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
        DataCell(Text(row['retardos'].toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
        DataCell(Text(row['ausentismos'].toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
      ],
    );
  }

  @override
  int get selectedRowCount => 0;

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => data.length;
}

// Continuación del estado _ReportesPageState:
extension _ReportesPageStateBadge on _ReportesPageState {
  Widget _buildBadgeCell(Map<String, String> detail) {
    final estado = detail['estado']!;
    
    Color color = Colors.grey;
    IconData icon = Icons.remove;
    String label = '-';

    if (estado == 'Asistió') {
      color = AppColors.success;
      icon = Icons.check_circle_outline;
      label = 'A';
    } else if (estado == 'Retardo') {
      color = AppColors.warning;
      icon = Icons.warning_amber_rounded;
      label = 'R';
    } else if (estado.startsWith('Ausente')) {
      color = AppColors.error;
      icon = Icons.event_busy;
      final startIdx = estado.indexOf('(');
      final endIdx = estado.indexOf(')');
      if (startIdx != -1 && endIdx != -1) {
        label = estado.substring(startIdx + 1, endIdx);
      } else {
        label = 'Aus';
      }
    } else if (estado == 'Fin de Semana') {
      color = Colors.blueGrey.withOpacity(0.4);
      icon = Icons.weekend_outlined;
      label = 'F';
    } else if (estado == 'No Registrado') {
      color = AppColors.textDisabled.withOpacity(0.5);
      icon = Icons.lock_clock;
      label = 'N/R';
    }

    return Tooltip(
      message: estado == 'Asistió' || estado == 'Retardo'
          ? '$estado\nEntrada: ${detail['entrada']}\nSalida: ${detail['salida']}'
          : (detail['observacion']!.isNotEmpty ? '$estado: ${detail['observacion']}' : estado),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withOpacity(0.3), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 12),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCellDetailsDialog(String name, String dateStr, Map<String, String> detail) {
    final parsedDate = DateTime.parse(dateStr);
    final dateFormatted = DateFormat('EEEE dd/MM/yyyy').format(parsedDate);
    final estado = detail['estado']!;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 4),
            Text(dateFormatted, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Estado: ', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(estado),
              ],
            ),
            const SizedBox(height: 8),
            if (estado == 'Asistió' || estado == 'Retardo') ...[
              Row(
                children: [
                  const Text('Hora Entrada: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(detail['entrada']!),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Hora Salida: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(detail['salida']!),
                ],
              ),
            ] else if (detail['observacion']!.isNotEmpty) ...[
              const Text('Observación / Justificación:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(detail['observacion']!, style: const TextStyle(fontStyle: FontStyle.italic)),
            ]
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _selectedDateRange,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDateRange) {
      setState(() {
        _selectedDateRange = picked;
      });
      _generateReport();
    }
  }
}
