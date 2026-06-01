import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/routes/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/db_constants.dart';
import '../../../data/datasources/local/database_helper.dart';
import '../../../data/models/registro_model.dart';
import '../../../data/models/empleado_model.dart';
import '../../../services/sync_service.dart';

class HistorialPage extends StatefulWidget {
  const HistorialPage({super.key});

  @override
  State<HistorialPage> createState() => _HistorialPageState();
}

class _HistorialPageState extends State<HistorialPage> {
  final _searchCtrl = TextEditingController();
  final _db = DatabaseHelper();
  
  List<RegistroModel> _allRegistros = [];
  List<RegistroModel> _filteredRegistros = [];
  Map<String, EmpleadoModel> _empleadosMap = {};
  
  DateTime? _selectedDate;
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchCtrl.addListener(_onFilterChanged);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      // 1. Cargar empleados para mapear nombres
      final empleados = await _db.getAllEmpleados();
      _empleadosMap = {
        for (var e in empleados) e.cedula: e
      };

      // 2. Cargar todos los registros locales usando consulta directa
      // Wait, let's load all or hoy, getRegistrosHoy is perfect for default totem view. But let's load all records if possible!
      // In DatabaseHelper we have `getRegistrosHoy()` and `getRegistrosPorCedula(cedula)`.
      // Let's add a general `getAllRegistros()` query or fetch records of the selected date or today.
      // Since DatabaseHelper doesn't have `getAllRegistros()`, let's check database_helper.dart lines 259-269:
      // it does raw db query of `registros`. We can fetch all records by query of `tableRegistros` ordered by date.
      // Let's execute a raw query or write a fallback, but wait, `DatabaseHelper` has:
      // `getRegistrosHoy()`! That fetches all records of today. Let's fetch all records in database helper!
      // Wait, is there a query to get all records? Let's check `database_helper.dart` if we can use a custom query or if `getRegistrosHoy` is enough.
      // Actually, let's look at `DatabaseHelper`:
      // We can run a raw query directly if we get the database:
      // `final db = await _db.database; final rows = await db.query(DbConstants.tableRegistros, orderBy: 'fecha_hora DESC');`
      // This is perfectly valid and incredibly powerful since we have direct access to database instance!
      final dbInstance = await _db.database;
      final rows = await dbInstance.query(DbConstants.tableRegistros, orderBy: 'fecha_hora DESC');
      final listAll = rows.map(RegistroModel.fromMap).toList();

      setState(() {
        _allRegistros = listAll;
        _filteredRegistros = listAll;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar historial: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  void _onFilterChanged() {
    final query = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      _filteredRegistros = _allRegistros.where((reg) {
        final empleado = _empleadosMap[reg.cedula];
        final matchQuery = query.isEmpty ||
            reg.cedula.toLowerCase().contains(query) ||
            (empleado != null && empleado.nombre.toLowerCase().contains(query));

        final matchDate = _selectedDate == null ||
            reg.fechaHora.startsWith(DateFormat('yyyy-MM-dd').format(_selectedDate!));

        return matchQuery && matchDate;
      }).toList();
    });
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
      _onFilterChanged();
    }
  }

  void _clearDateFilter() {
    setState(() {
      _selectedDate = null;
    });
    _onFilterChanged();
  }

  Future<void> _syncManually() async {
    if (_syncing) return;
    setState(() => _syncing = true);

    try {
      final syncService = Provider.of<SyncService>(context, listen: false);
      final result = await syncService.syncAll();

      if (mounted) {
        if (result.hasErrors) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sincronización finalizada con errores: ${result.errors.first}'),
              backgroundColor: AppColors.warning,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('¡Éxito! Sincronizados ${result.registros} registros y ${result.permisos} permisos.'),
              backgroundColor: AppColors.success,
            ),
          );
        }
        // Recargar datos
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error de red al sincronizar: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  String _formatDateTime(String isoStr) {
    try {
      final dt = DateTime.parse(isoStr);
      return DateFormat('dd/MM/yyyy HH:mm:ss').format(dt);
    } catch (_) {
      return isoStr;
    }
  }

  Color _getTipoColor(String tipo) {
    switch (tipo.toUpperCase()) {
      case 'NORMAL':
        return AppColors.colorNormal;
      case 'RETARDO':
        return AppColors.colorRetardo;
      case 'ALMUERZO':
        return AppColors.colorAlmuerzo;
      case 'SALIDA':
        return AppColors.colorSalida;
      case 'PERMISO':
        return AppColors.colorPermiso;
      case 'EXTRAS':
        return AppColors.colorExtras;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Asistencia'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.home),
        ),
        actions: [
          IconButton(
            icon: _syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.sync),
            tooltip: 'Sincronizar con servidor',
            onPressed: _syncing ? null : _syncManually,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Filtros
                Container(
                  color: Theme.of(context).colorScheme.surface,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Barra de búsqueda
                      TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Buscar por cédula o nombre...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () => _searchCtrl.clear(),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Filtro de fecha
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _selectDate,
                              icon: const Icon(Icons.calendar_today, size: 18),
                              label: Text(
                                _selectedDate == null
                                    ? 'Filtrar por Fecha'
                                    : 'Fecha: ${DateFormat('dd/MM/yyyy').format(_selectedDate!)}',
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: _selectedDate != null ? AppColors.primary : Theme.of(context).dividerColor,
                                ),
                                foregroundColor: _selectedDate != null ? AppColors.primary : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          if (_selectedDate != null) ...[
                            const SizedBox(width: 12),
                            IconButton(
                              icon: const Icon(Icons.filter_alt_off_outlined, color: AppColors.error),
                              tooltip: 'Limpiar filtro de fecha',
                              onPressed: _clearDateFilter,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Lista de Registros
                Expanded(
                  child: _filteredRegistros.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.history_toggle_off, size: 64, color: AppColors.textDisabled),
                              const SizedBox(height: 16),
                              Text(
                                _allRegistros.isEmpty
                                    ? 'No hay registros de asistencia en la base de datos'
                                    : 'No se encontraron registros con los filtros activos',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredRegistros.length,
                          itemBuilder: (context, index) {
                            final reg = _filteredRegistros[index];
                            final empleado = _empleadosMap[reg.cedula];
                            final color = _getTipoColor(reg.tipo);

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  children: [
                                    // Icono del Evento
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        reg.evento == AppConstants.eventoEntrada
                                            ? Icons.login
                                            : Icons.logout,
                                        color: color,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 16),

                                    // Datos de registro
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            empleado?.nombre ?? 'Empleado Desconocido',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                              color: Theme.of(context).colorScheme.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'CC: ${reg.cedula} | ${_formatDateTime(reg.fechaHora)}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              // Chip del tipo
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: color.withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: color.withValues(alpha: 0.3)),
                                                ),
                                                child: Text(
                                                  reg.tipo.toUpperCase(),
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: color,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                                Text(
                                                  'Dispositivo: ${reg.unidadNegocio}',
                                                  style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Estado de sincronización
                                    Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          reg.sincronizado ? Icons.cloud_done : Icons.cloud_off,
                                          color: reg.sincronizado ? AppColors.success : AppColors.textDisabled,
                                          size: 22,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          reg.sincronizado ? 'Enviado' : 'Pendiente',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: reg.sincronizado ? AppColors.success : Theme.of(context).colorScheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        )
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
