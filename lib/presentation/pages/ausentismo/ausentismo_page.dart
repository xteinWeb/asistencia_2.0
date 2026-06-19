import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/db_constants.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/routes/app_router.dart';
import '../../../data/datasources/local/database_helper.dart';
import '../../../data/models/empleado_model.dart';
import '../../../data/models/registro_model.dart';
import '../../../data/models/ausentismo_model.dart';
import '../../../data/models/permiso_model.dart';
import '../../../data/models/incapacidad_model.dart';
import '../../../services/sync_service.dart';

enum _FilterTab { todos, asistieron, ausentes, validados }

class AusentismoPage extends StatefulWidget {
  const AusentismoPage({super.key});

  @override
  State<AusentismoPage> createState() => _AusentismoPageState();
}

class _AusentismoPageState extends State<AusentismoPage> {
  final _db = DatabaseHelper();

  DateTime _selectedDate = DateTime.now();

  bool get _isFutureDate {
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);
    final selectedDateOnly = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    return selectedDateOnly.isAfter(todayDateOnly);
  }

  bool get _isTodayOrFuture {
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);
    final selectedDateOnly = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    return selectedDateOnly.isAtSameMomentAs(todayDateOnly) ||
        selectedDateOnly.isAfter(todayDateOnly);
  }

  List<EmpleadoModel> _empleados = [];
  List<RegistroModel> _registrosDia = [];
  List<AusentismoModel> _ausentismosDia = [];
  List<Map<String, String>> _tiposAusencia = [];
  Map<String, PermisoModel> _permisosDiaMap = {};
  Map<String, IncapacidadModel> _incapacidadesDiaMap = {};

  // Estado local temporal en memoria para edición en lote
  Map<String, String> _justificacionesTemporales = {};
  final Map<String, TextEditingController> _obsControllers = {};
  bool _hasUnsavedChanges = false;

  @override
  void dispose() {
    for (final c in _obsControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _loading = true;
  bool _syncing = false;
  String _searchQuery = '';
  _FilterTab _selectedTab = _FilterTab.todos;

  // Control para mostrar/ocultar estadísticas
  bool _showStats = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final targetDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

      // 1. Obtener empleados activos y filtrar por su fecha de registro en el sistema (fechaRegistro)
      final emps = await _db.getAllEmpleados();
      final activeEmps = emps.where((e) {
        if (e.estado.toUpperCase() != 'ACTIVO') return false;
        if (e.fechaRegistro != null && e.fechaRegistro!.trim().isNotEmpty) {
          final regStr = e.fechaRegistro!.trim();
          final regDateStr = regStr.length >= 10 ? regStr.substring(0, 10) : regStr;
          return regDateStr.compareTo(targetDateStr) <= 0;
        }
        return true;
      }).toList();

      // 2. Obtener registros del día
      List<RegistroModel> regsDia = [];
      if (kIsWeb) {
        // En Web no hay DB local, consultamos todos y filtramos
        final allRegs = await _db.getAllRegistros();
        regsDia = allRegs
            .where((r) => r.fechaHora.startsWith(targetDateStr))
            .toList();
      } else {
        // En local usamos base de datos SQLite y filtramos por fecha
        final dbHelper = DatabaseHelper();
        final db = await dbHelper.database;
        final rows = await db.query(
          DbConstants.tableRegistros,
          where: "fecha_hora LIKE ?",
          whereArgs: ['$targetDateStr%'],
          orderBy: 'fecha_hora DESC',
        );
        regsDia = rows.map(RegistroModel.fromMap).toList();
      }

      // 3. Obtener ausentismos para esta fecha
      final ausents = await _db.getAusentismosFecha(targetDateStr);

      // 4. Obtener tipos de ausentismo
      final types = await _db.getTiposAusencia();

      // 5. Obtener todos los permisos y filtrar para este día
      final allPermisos = await _db.getAllPermisos();
      final permisosDia = allPermisos.where((p) {
        if (p.fechaInicio.length < 10 || p.fechaFinal.length < 10) return false;
        final start = p.fechaInicio.substring(0, 10);
        final end = p.fechaFinal.substring(0, 10);
        return start.compareTo(targetDateStr) <= 0 &&
            end.compareTo(targetDateStr) >= 0;
      }).toList();
      final Map<String, PermisoModel> permisosDiaMap = {
        for (final p in permisosDia) p.cedulaEmpleado: p,
      };

      // 6. Obtener todas las incapacidades y filtrar para este día
      final allIncapacidades = await _db.getAllIncapacidades();
      final incapacidadesDia = allIncapacidades.where((i) {
        if (i.fechaInicio.length < 10 || i.fechaFinal.length < 10) return false;
        final start = i.fechaInicio.substring(0, 10);
        final end = i.fechaFinal.substring(0, 10);
        return start.compareTo(targetDateStr) <= 0 &&
            end.compareTo(targetDateStr) >= 0;
      }).toList();
      final Map<String, IncapacidadModel> incapacidadesDiaMap = {
        for (final i in incapacidadesDia) i.cedulaEmpleado: i,
      };

      setState(() {
        _empleados = activeEmps;
        _registrosDia = regsDia;
        _ausentismosDia = ausents;
        _tiposAusencia = types;
        _permisosDiaMap = permisosDiaMap;
        _incapacidadesDiaMap = incapacidadesDiaMap;

        // Inicializar el estado en memoria con las novedades guardadas de la BD
        _justificacionesTemporales = {
          for (final a in ausents) a.cedulaEmpleado: a.siglaAusencia,
        };

        // Resetear y poblar controllers
        for (var c in _obsControllers.values) {
          c.dispose();
        }
        _obsControllers.clear();
        for (final a in ausents) {
          _obsControllers[a.cedulaEmpleado] = TextEditingController(
            text: a.observacion ?? '',
          );
        }

        _hasUnsavedChanges = false;
      });
    } catch (e) {
      debugPrint('Error al cargar datos en AusentismoPage: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar datos: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _syncManually() async {
    if (kIsWeb) {
      await _loadData();
      return;
    }
    if (_syncing) return;
    setState(() => _syncing = true);

    try {
      final syncService = Provider.of<SyncService>(context, listen: false);
      final result = await syncService.syncAll();

      if (mounted) {
        if (result.hasErrors) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Sincronización finalizada con errores: ${result.errors.first}',
              ),
              backgroundColor: AppColors.warning,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '¡Éxito! Sincronizados ${result.registros} registros de asistencia.',
              ),
              backgroundColor: AppColors.success,
            ),
          );
        }
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de red al sincronizar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  // Modificación del estado en memoria
  void _onJustificacionChanged(EmpleadoModel empleado, String? sigla) {
    setState(() {
      if (sigla == null || sigla.isEmpty) {
        _justificacionesTemporales.remove(empleado.cedula);
        _obsControllers[empleado.cedula]?.clear();
      } else {
        _justificacionesTemporales[empleado.cedula] = sigla;
      }
      _hasUnsavedChanges = true;
    });
  }

  // Descartar cambios locales en memoria y volver al estado de la BD
  void _discardChanges() {
    setState(() {
      _justificacionesTemporales = {
        for (final a in _ausentismosDia) a.cedulaEmpleado: a.siglaAusencia,
      };

      // Resetear controllers a los valores originales de la base de datos
      for (var c in _obsControllers.values) {
        c.dispose();
      }
      _obsControllers.clear();
      for (final a in _ausentismosDia) {
        _obsControllers[a.cedulaEmpleado] = TextEditingController(
          text: a.observacion ?? '',
        );
      }

      _hasUnsavedChanges = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cambios descartados'),
        backgroundColor: AppColors.info,
      ),
    );
  }

  // Guardar en lote todos los cambios locales en memoria
  Future<void> _saveAllChanges() async {
    setState(() => _loading = true);
    try {
      final targetDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

      // 1. Identificar registros a eliminar de la BD
      final toDelete = <AusentismoModel>[];
      for (final existing in _ausentismosDia) {
        if (!_justificacionesTemporales.containsKey(existing.cedulaEmpleado)) {
          toDelete.add(existing);
        }
      }

      // 2. Identificar registros a insertar o actualizar en la BD
      final toSave = <AusentismoModel>[];
      for (final entry in _justificacionesTemporales.entries) {
        final cedula = entry.key;
        final sigla = entry.value;
        final obsText = _obsControllers[cedula]?.text.trim() ?? '';

        final existingList = _ausentismosDia
            .where((a) => a.cedulaEmpleado == cedula)
            .toList();
        if (existingList.isNotEmpty) {
          final existing = existingList.first;
          if (existing.siglaAusencia != sigla ||
              existing.observacion != obsText) {
            toSave.add(
              existing.copyWith(
                siglaAusencia: sigla,
                observacion: obsText.isNotEmpty ? obsText : null,
                sincronizado: false,
              ),
            );
          }
        } else {
          toSave.add(
            AusentismoModel(
              id: const Uuid().v4(),
              cedulaEmpleado: cedula,
              fecha: targetDateStr,
              siglaAusencia: sigla,
              observacion: obsText.isNotEmpty ? obsText : null,
              sincronizado: false,
            ),
          );
        }
      }

      // 3. Ejecutar eliminaciones
      for (final item in toDelete) {
        await _db.deleteAusentismo(item.id);
      }

      // 4. Ejecutar inserciones/actualizaciones en lote
      if (kIsWeb) {
        if (toSave.isNotEmpty) {
          final baseUrl =
              await _db.getConfig(DbConstants.cfgUrlApi) ??
              ApiConstants.defaultBaseUrl;
          final response = await http.post(
            Uri.parse('$baseUrl/api/sync/ausentismos'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(
              toSave
                  .map((a) => a.copyWith(sincronizado: true).toMap())
                  .toList(),
            ),
          );
          if (response.statusCode != 200 && response.statusCode != 201) {
            throw Exception(
              'Error al guardar en el servidor: ${response.statusCode}',
            );
          }
        }
      } else {
        final db = await _db.database;
        await db.transaction((txn) async {
          for (final item in toSave) {
            await txn.insert(
              'ausentismos',
              item.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cambios guardados con éxito'),
            backgroundColor: AppColors.success,
          ),
        );
      }

      setState(() {
        _hasUnsavedChanges = false;
      });

      // Recargar datos desde la base de datos para refrescar estado inicial y UI
      await _loadData();
    } catch (e) {
      debugPrint('Error al guardar cambios: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar cambios: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      setState(() => _loading = false);
    }
  }

  Future<void> _procesarRetardosDia() async {
    if (await _confirmDiscardChanges() == false) return;

    setState(() => _loading = true);
    final targetDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    try {
      if (kIsWeb) {
        final baseUrl =
            await _db.getConfig(DbConstants.cfgUrlApi) ??
            ApiConstants.defaultBaseUrl;
        final response = await http.post(
          Uri.parse('$baseUrl/api/sync/generar-llt'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'fecha': targetDateStr}),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  data['message'] ?? 'Retardos procesados correctamente',
                ),
                backgroundColor: AppColors.success,
              ),
            );
          }
        } else {
          throw Exception('Error en el servidor: ${response.statusCode}');
        }
      } else {
        // Ejecución en SQLite local (offline)
        final dbHelper = DatabaseHelper();
        final db = await dbHelper.database;

        // 1. Obtener registros de entrada con retardo para la fecha seleccionada
        final registros = await db.query(
          DbConstants.tableRegistros,
          where:
              "evento = 'ENTRADA' AND tipo = 'RETARDO' AND fecha_hora LIKE ?",
          whereArgs: ['$targetDateStr%'],
        );

        int generados = 0;
        int actualizados = 0;

        await db.transaction((txn) async {
          for (final r in registros) {
            final cedula = r['cedula'] as String;
            final duracion = r['duracion'] as String?;
            final obs = duracion != null ? 'Retardo: $duracion' : 'Retardo';

            final existing = await txn.query(
              'ausentismos',
              where:
                  "cedula_empleado = ? AND fecha = ? AND sigla_ausencia = 'LLT'",
              whereArgs: [cedula, targetDateStr],
            );

            if (existing.isEmpty) {
              final newId = const Uuid().v4();
              await txn.insert('ausentismos', {
                'id': newId,
                'cedula_empleado': cedula,
                'fecha': targetDateStr,
                'sigla_ausencia': 'LLT',
                'observacion': obs,
                'sincronizado': 0,
              });
              generados++;
            } else {
              final existingId = existing.first['id'] as String;
              await txn.update(
                'ausentismos',
                {'observacion': obs, 'sincronizado': 0},
                where: 'id = ?',
                whereArgs: [existingId],
              );
              actualizados++;
            }
          }
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Completado. Generados: $generados, Actualizados: $actualizados',
              ),
              backgroundColor: AppColors.success,
            ),
          );
        }
      }

      // Recargar datos para mostrar los cambios
      await _loadData();
    } catch (e) {
      debugPrint('Error al procesar retardos del día: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al procesar retardos: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      setState(() => _loading = false);
    }
  }

  // Ventana emergente de confirmación al intentar salir/cambiar de fecha con datos modificados
  Future<bool> _confirmDiscardChanges() async {
    if (!_hasUnsavedChanges) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cambios sin guardar'),
        content: const Text(
          'Tiene cambios en las justificaciones de asistencia que no han sido guardados. ¿Desea descartar los cambios?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  String _getDiaSemana(int weekday) {
    switch (weekday) {
      case 1:
        return 'Lunes';
      case 2:
        return 'Martes';
      case 3:
        return 'Miércoles';
      case 4:
        return 'Jueves';
      case 5:
        return 'Viernes';
      case 6:
        return 'Sábado';
      case 7:
        return 'Domingo';
      default:
        return '';
    }
  }

  String _getMes(int month) {
    switch (month) {
      case 1:
        return 'Enero';
      case 2:
        return 'Febrero';
      case 3:
        return 'Marzo';
      case 4:
        return 'Abril';
      case 5:
        return 'Mayo';
      case 6:
        return 'Junio';
      case 7:
        return 'Julio';
      case 8:
        return 'Agosto';
      case 9:
        return 'Septiembre';
      case 10:
        return 'Octubre';
      case 11:
        return 'Noviembre';
      case 12:
        return 'Diciembre';
      default:
        return '';
    }
  }

  String _formatDateString(DateTime date) {
    return '${_getDiaSemana(date.weekday)}, ${date.day} de ${_getMes(date.month)} de ${date.year}';
  }

  String _formatTime(String fechaHoraStr) {
    try {
      final parsed = DateTime.parse(fechaHoraStr.replaceAll(' ', 'T'));
      return DateFormat('hh:mm a').format(parsed);
    } catch (e) {
      if (fechaHoraStr.length >= 16) {
        return fechaHoraStr.substring(11, 16);
      }
      return fechaHoraStr;
    }
  }

  List<EmpleadoModel> _getFilteredEmployees() {
    return _empleados.where((emp) {
      // 1. Filtrar por búsqueda
      final matchesSearch =
          emp.nombre.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          emp.cedula.contains(_searchQuery);
      if (!matchesSearch) return false;

      // 2. Determinar asistencia
      final isPresent = _registrosDia.any(
        (r) => r.cedula == emp.cedula && r.evento == AppConstants.eventoEntrada,
      );

      // 3. Determinar si tiene justificación en el estado temporal de memoria, permiso o incapacidad
      final currentSigla = _justificacionesTemporales[emp.cedula];
      final tienePermiso = _permisosDiaMap.containsKey(emp.cedula);
      final tieneIncapacidad = _incapacidadesDiaMap.containsKey(emp.cedula);
      final hasValidation = currentSigla != null || tienePermiso || tieneIncapacidad;

      // 4. Filtrar por pestaña
      switch (_selectedTab) {
        case _FilterTab.todos:
          return true;
        case _FilterTab.asistieron:
          return isPresent;
        case _FilterTab.ausentes:
          return !isPresent && currentSigla != 'PE' && !tienePermiso && !tieneIncapacidad;
        case _FilterTab.validados:
          return hasValidation;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    // Calcular estadísticas dinámicamente basadas en el estado temporal en memoria
    final totalCount = _empleados.length;
    final presentCount = _empleados.where((emp) {
      return _registrosDia.any(
        (r) => r.cedula == emp.cedula && r.evento == AppConstants.eventoEntrada,
      );
    }).length;

    final absentCount = _empleados.where((emp) {
      final isPresent = _registrosDia.any(
        (r) => r.cedula == emp.cedula && r.evento == AppConstants.eventoEntrada,
      );
      final currentSigla = _justificacionesTemporales[emp.cedula];
      final tienePermiso = _permisosDiaMap.containsKey(emp.cedula);
      final tieneIncapacidad = _incapacidadesDiaMap.containsKey(emp.cedula);
      return !isPresent && currentSigla != 'PE' && !tienePermiso && !tieneIncapacidad;
    }).length;

    final validatedCount = _empleados.where((emp) {
      final isAbsent = !_registrosDia.any(
        (r) => r.cedula == emp.cedula && r.evento == AppConstants.eventoEntrada,
      );
      final currentSigla = _justificacionesTemporales[emp.cedula];
      final tienePermiso = _permisosDiaMap.containsKey(emp.cedula);
      final tieneIncapacidad = _incapacidadesDiaMap.containsKey(emp.cedula);
      return isAbsent && (currentSigla != null || tienePermiso || tieneIncapacidad);
    }).length;

    final presentPercent = totalCount > 0
        ? ((presentCount / totalCount) * 100).toStringAsFixed(0)
        : '0';
    final absentPercent = totalCount > 0
        ? ((absentCount / totalCount) * 100).toStringAsFixed(0)
        : '0';

    final filteredList = _getFilteredEmployees();

    return WillPopScope(
      onWillPop: () async {
        return await _confirmDiscardChanges();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Registro de Ausentismo'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (await _confirmDiscardChanges()) {
                context.go(AppRoutes.home);
              }
            },
          ),
          actions: [
            IconButton(
              icon: Icon(
                _showStats ? Icons.analytics : Icons.analytics_outlined,
              ),
              tooltip: _showStats
                  ? 'Ocultar estadísticas'
                  : 'Mostrar estadísticas',
              color: _showStats ? Colors.amber : null,
              onPressed: () {
                setState(() {
                  _showStats = !_showStats;
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.assignment_late_rounded),
              tooltip: 'Procesar retardos de este día',
              onPressed: _loading || _isFutureDate
                  ? null
                  : _procesarRetardosDia,
            ),
            IconButton(
              icon: _syncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.refresh),
              tooltip: kIsWeb ? 'Recargar datos' : 'Sincronizar y recargar',
              onPressed: _syncing || _loading
                  ? null
                  : () async {
                      if (await _confirmDiscardChanges()) {
                        _syncManually();
                      }
                    },
            ),
          ],
        ),
        body: Column(
          children: [
            // Selector de Fecha
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      tooltip: 'Día anterior',
                      onPressed: () async {
                        if (await _confirmDiscardChanges()) {
                          setState(() {
                            _selectedDate = _selectedDate.subtract(
                              const Duration(days: 1),
                            );
                          });
                          _loadData();
                        }
                      },
                    ),
                    Expanded(
                      child: TextButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _formatDateString(_selectedDate),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        onPressed: () async {
                          if (await _confirmDiscardChanges()) {
                            final now = DateTime.now();
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate.isAfter(now)
                                  ? now
                                  : _selectedDate,
                              firstDate: now.subtract(
                                const Duration(days: 365),
                              ),
                              lastDate: now,
                            );
                            if (picked != null) {
                              setState(() {
                                _selectedDate = picked;
                              });
                              _loadData();
                            }
                          }
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      tooltip: 'Día siguiente',
                      onPressed: _isTodayOrFuture
                          ? null
                          : () async {
                              if (await _confirmDiscardChanges()) {
                                setState(() {
                                  _selectedDate = _selectedDate.add(
                                    const Duration(days: 1),
                                  );
                                });
                                _loadData();
                              }
                            },
                    ),
                  ],
                ),
              ),
            ),

            // Advertencia si es una fecha futura
            if (_isFutureDate)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.errorLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.error,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No se pueden registrar ni modificar novedades para fechas futuras.',
                        style: TextStyle(
                          color: AppColors.error,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Panel de Estadísticas Colapsable con Transición Animada
            AnimatedCrossFade(
              firstChild: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    _buildStatCard(
                      'Colaboradores',
                      '$totalCount',
                      Icons.people_outline,
                      AppColors.primary,
                    ),
                    _buildStatCard(
                      'Asistieron',
                      '$presentCount ($presentPercent%)',
                      Icons.check_circle_outline,
                      AppColors.success,
                    ),
                    _buildStatCard(
                      'Ausentes',
                      '$absentCount ($absentPercent%)',
                      Icons.highlight_off,
                      AppColors.error,
                    ),
                    _buildStatCard(
                      'Justificados',
                      '$validatedCount',
                      Icons.verified_outlined,
                      AppColors.warning,
                    ),
                  ],
                ),
              ),
              secondChild: const SizedBox.shrink(),
              crossFadeState: _showStats
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              duration: const Duration(milliseconds: 250),
            ),

            // Buscador y Pestañas de Filtro (Compactado)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Column(
                    children: [
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Buscar por nombre o cédula',
                          prefixIcon: Icon(Icons.search, size: 20),
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(vertical: 6),
                          isDense: true,
                        ),
                        onChanged: (val) {
                          setState(() {
                            _searchQuery = val;
                          });
                        },
                      ),
                      const SizedBox(height: 6),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip('Todos', _FilterTab.todos),
                            const SizedBox(width: 6),
                            _buildFilterChip(
                              'Asistieron',
                              _FilterTab.asistieron,
                            ),
                            const SizedBox(width: 6),
                            _buildFilterChip('Ausentes', _FilterTab.ausentes),
                            const SizedBox(width: 6),
                            _buildFilterChip('Validados', _FilterTab.validados),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Tabla CSS de Novedades de Asistencia
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filteredList.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.search_off,
                            size: 56,
                            color: AppColors.textDisabled,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No se encontraron colaboradores',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Cabecera de la Tabla (Estilo CSS Table Header)
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(7),
                                topRight: Radius.circular(7),
                              ),
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.grey.shade300,
                                  width: 1,
                                ),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: const Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    'Cédula',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: AppColors.primaryDark,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    'Colaborador',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: AppColors.primaryDark,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    'Tipo',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: AppColors.primaryDark,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 5,
                                  child: Text(
                                    'Asistencia',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: AppColors.primaryDark,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 4,
                                  child: Text(
                                    'Justificación / Novedad',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: AppColors.primaryDark,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 4,
                                  child: Text(
                                    'Observación',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: AppColors.primaryDark,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Filas de la Tabla (Estilo CSS Table Rows)
                          Expanded(
                            child: ListView.builder(
                              itemCount: filteredList.length,
                              itemBuilder: (context, index) {
                                final emp = filteredList[index];

                                // Verificar asistencia
                                final checkInRegs = _registrosDia
                                    .where(
                                      (r) =>
                                          r.cedula == emp.cedula &&
                                          r.evento ==
                                              AppConstants.eventoEntrada,
                                    )
                                    .toList();
                                checkInRegs.sort(
                                  (a, b) => a.fechaHora.compareTo(b.fechaHora),
                                );
                                final checkIn = checkInRegs.isNotEmpty
                                    ? checkInRegs.first
                                    : null;

                                // Obtener novedad actual de la memoria temporal
                                final currentSigla =
                                    _justificacionesTemporales[emp.cedula];

                                return _buildTableRow(
                                  emp,
                                  checkIn,
                                  currentSigla,
                                  index,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
        bottomNavigationBar: _hasUnsavedChanges
            ? SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade200, width: 1),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _discardChanges,
                          child: const Text('Descartar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _loading ? null : _saveAllChanges,
                          icon: const Icon(Icons.save),
                          label: const Text('Guardar Cambios'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : null,
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
      child: Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 1),
              Text(
                title,
                style: const TextStyle(fontSize: 9, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, _FilterTab tab) {
    final isSelected = _selectedTab == tab;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: isSelected,
      selectedColor: AppColors.primary.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: isSelected
            ? AppColors.primary
            : Theme.of(context).colorScheme.onSurface,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedTab = tab;
          });
        }
      },
    );
  }

  Widget _buildTableRow(
    EmpleadoModel emp,
    RegistroModel? checkIn,
    String? currentSigla,
    int index,
  ) {
    final isPresent = checkIn != null;
    final tienePermiso = _permisosDiaMap.containsKey(emp.cedula);

    Color statusBgColor;
    Color statusTextColor;
    String statusText;
    IconData statusIcon;

    if (isPresent) {
      final tipoStr = checkIn.tipo.toUpperCase();
      if (tipoStr == 'RETARDO') {
        statusBgColor = const Color(0xFFFFF3E0); // light orange
        statusTextColor = Colors.orange.shade800; // orange
        statusText =
            'RETARDO${checkIn.duracion != null ? ' ${checkIn.duracion}' : ''} - ${_formatTime(checkIn.fechaHora)}';
        statusIcon = Icons.warning_amber_rounded;
      } else if (tipoStr == 'PERMISO') {
        statusBgColor = const Color(0xFFF3E5F5); // light purple
        statusTextColor = const Color(0xFF7B1FA2); // purple
        statusText =
            'PERMISO${checkIn.duracion != null ? ' ${checkIn.duracion}' : ''} - ${_formatTime(checkIn.fechaHora)}';
        statusIcon = Icons.card_membership_rounded;
      } else {
        statusBgColor = AppColors.successLight;
        statusTextColor = AppColors.success;
        statusText = 'ASISTIÓ - ${_formatTime(checkIn.fechaHora)}';
        statusIcon = Icons.check_circle;
      }
    } else if (currentSigla == 'PE' || (currentSigla == null && tienePermiso)) {
      final tipoPermiso = tienePermiso
          ? _permisosDiaMap[emp.cedula]!.tipo
          : 'AUTORIZADO';
      statusBgColor = const Color(0xFFF3E5F5); // light purple
      statusTextColor = const Color(0xFF7B1FA2); // purple
      statusText = 'EN PERMISO ($tipoPermiso)';
      statusIcon = Icons.card_membership;
    } else if (_incapacidadesDiaMap.containsKey(emp.cedula)) {
      final tipoIncapacidad = _incapacidadesDiaMap[emp.cedula]!.tipo;
      statusBgColor = const Color(0xFFFCE4EC); // light pink/red
      statusTextColor = const Color(0xFFC2185B); // dark pink
      statusText = 'INCAPACITADO ($tipoIncapacidad)';
      statusIcon = Icons.medical_services_rounded;
    } else if (currentSigla != null) {
      statusBgColor = AppColors.warningLight;
      statusTextColor = AppColors.warning;
      statusText = 'VALIDADO: $currentSigla';
      statusIcon = Icons.verified;
    } else {
      statusBgColor = AppColors.errorLight;
      statusTextColor = AppColors.error;
      statusText = 'SIN ENTRADA';
      statusIcon = Icons.cancel;
    }

    String valName = '';
    if (currentSigla != null) {
      final match = _tiposAusencia.where((t) => t['sigla'] == currentSigla);
      valName = match.isNotEmpty ? match.first['nombre']! : '';
    }

    // Color alternado para simular estilo de tabla CSS (striped)
    final rowColor = index.isEven ? Colors.white : Colors.grey.shade50;

    return Container(
      decoration: BoxDecoration(
        color: rowColor,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Columna Cédula
          Expanded(
            flex: 2,
            child: Text(
              emp.cedula,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),

          // Columna Colaborador (Nombre)
          Expanded(
            flex: 3,
            child: Text(
              emp.nombre,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Columna Tipo
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  emp.tipo ?? 'ADMINISTRATIVO',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
            ),
          ),

          // Columna Asistencia
          Expanded(
            flex: 5,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(statusIcon, color: statusTextColor, size: 12),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: statusTextColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Columna Justificación
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(6),
                      color: _isFutureDate
                          ? Colors.grey.shade100
                          : Colors.white,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: currentSigla ?? '',
                        isExpanded: true,
                        style: TextStyle(
                          color: _isFutureDate
                              ? Colors.grey
                              : Theme.of(context).colorScheme.onSurface,
                          fontSize: 12,
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: '',
                            child: Text(
                              '-- Sin justificar --',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          ..._tiposAusencia.map((t) {
                            return DropdownMenuItem<String>(
                              value: t['sigla']!,
                              child: Text(
                                '${t['sigla']} - ${t['nombre']}',
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }),
                        ],
                        onChanged: _isFutureDate
                            ? null
                            : (val) {
                                _onJustificacionChanged(
                                  emp,
                                  (val == null || val.isEmpty) ? null : val,
                                );
                              },
                      ),
                    ),
                  ),
                ),
                if (currentSigla != null) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: '$currentSigla - $valName',
                    child: const Icon(
                      Icons.info_outline,
                      color: AppColors.warning,
                      size: 18,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: 16),

          // Columna Observación
          Expanded(
            flex: 4,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(
                  color: (currentSigla != null && !_isFutureDate)
                      ? Colors.grey.shade300
                      : Colors.grey.shade200,
                ),
                borderRadius: BorderRadius.circular(6),
                color: (currentSigla != null && !_isFutureDate)
                    ? Colors.white
                    : Colors.grey.shade100,
              ),
              child: Center(
                child: TextField(
                  controller: _obsControllers.putIfAbsent(
                    emp.cedula,
                    () => TextEditingController(text: ''),
                  ),
                  enabled: currentSigla != null && !_isFutureDate,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: (currentSigla != null && !_isFutureDate)
                        ? 'Escribir observación...'
                        : 'Sin justificar',
                    hintStyle: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade400,
                      fontStyle: (currentSigla != null && !_isFutureDate)
                          ? FontStyle.normal
                          : FontStyle.italic,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (val) {
                    setState(() {
                      _hasUnsavedChanges = true;
                    });
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
