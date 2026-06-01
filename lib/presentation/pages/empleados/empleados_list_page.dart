import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import '../../../core/routes/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/constants/db_constants.dart';
import '../../../data/datasources/local/database_helper.dart';
import '../../../data/models/empleado_model.dart';
import '../../../data/models/horario_model.dart';
import '../../../services/sync_service.dart';

class EmpleadosListPage extends StatefulWidget {
  const EmpleadosListPage({super.key});

  @override
  State<EmpleadosListPage> createState() => _EmpleadosListPageState();
}

class _EmpleadosListPageState extends State<EmpleadosListPage> {
  final _searchCtrl = TextEditingController();
  final _db = DatabaseHelper();
  
  List<EmpleadoModel> _allEmpleados = [];
  List<EmpleadoModel> _filteredEmpleados = [];
  Map<String, HorarioModel> _horariosMap = {};
  bool _loading = true;
  bool _syncing = false;

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
        // Recargar datos locales
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

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      // 1. Cargar todos los horarios en un mapa para acceso rápido
      final horariosList = await _db.getAllHorarios();
      _horariosMap = {
        for (var h in horariosList) h.idHorario!: h
      };

      // 2. Cargar todos los empleados activos
      final list = await _db.getAllEmpleados();
      final activeList = list.where((e) => e.estado == 'ACTIVO').toList();
      setState(() {
        _allEmpleados = activeList;
        _filteredEmpleados = activeList;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar datos: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  void _onSearchChanged() {
    final query = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredEmpleados = _allEmpleados;
      } else {
        _filteredEmpleados = _allEmpleados.where((e) {
          return e.nombre.toLowerCase().contains(query) ||
              e.cedula.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  Future<void> _deleteEmpleado(String cedula, String nombre) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Inactivación'),
        content: Text('¿Está seguro de que desea inactivar al empleado $nombre?\nNo podrá marcar asistencia en el Kiosko, pero se conservará todo su historial de registros en el sistema.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Inactivar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // 1. Intentar inactivar en SQL Server central si hay conexión
        final baseUrl = await _db.getConfig(DbConstants.cfgUrlApi) ?? ApiConstants.defaultBaseUrl;
        final uri = Uri.parse('$baseUrl/api/sync/empleados/$cedula');
        
        try {
          final response = await http.delete(uri).timeout(const Duration(seconds: 4));
          if (response.statusCode != 200) {
            debugPrint('No se pudo inactivar en el servidor (status: ${response.statusCode})');
          }
        } catch (e) {
          debugPrint('Error de red al inactivar en el servidor (offline): $e');
        }

        // 2. Inactivar localmente en SQLite para conservar historial de registros
        final localEmp = await _db.getEmpleadoByCedula(cedula);
        if (localEmp != null) {
          final updatedEmp = localEmp.copyWith(estado: 'INACTIVO', sincronizado: true);
          await _db.updateEmpleado(updatedEmp);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Empleado inactivado con éxito (Historial preservado).'), backgroundColor: AppColors.success),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al inactivar: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Empleados'),
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
            tooltip: 'Sincronizar todo',
            onPressed: _syncing ? null : _syncManually,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Barra de búsqueda
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Buscar empleado por nombre o cédula...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => _searchCtrl.clear(),
                            )
                          : null,
                    ),
                  ),
                ),

                // Lista de empleados
                Expanded(
                  child: _filteredEmpleados.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.people_outline, size: 64, color: AppColors.textDisabled),
                              const SizedBox(height: 16),
                              Text(
                                _allEmpleados.isEmpty
                                    ? 'No hay empleados registrados en el sistema'
                                    : 'No se encontraron empleados que coincidan con la búsqueda',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredEmpleados.length,
                          itemBuilder: (context, index) {
                            final emp = _filteredEmpleados[index];
                            final horario = emp.horarioId != null ? _horariosMap[emp.horarioId] : null;
                            final tieneVector = emp.mapaVectorFoto.isNotEmpty;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    // Avatar
                                    CircleAvatar(
                                      radius: 26,
                                      backgroundColor: tieneVector
                                          ? AppColors.success.withValues(alpha: 0.1)
                                          : AppColors.warning.withValues(alpha: 0.1),
                                      child: Icon(
                                        tieneVector ? Icons.face : Icons.face_retouching_off,
                                        color: tieneVector ? AppColors.success : AppColors.warning,
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(width: 16),

                                    // Información principal
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            emp.nombre,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context).colorScheme.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'CC: ${emp.cedula}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              // Chip del estado facial
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: tieneVector
                                                      ? AppColors.successLight
                                                      : AppColors.warningLight,
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: tieneVector
                                                        ? AppColors.success.withValues(alpha: 0.3)
                                                        : AppColors.warning.withValues(alpha: 0.3),
                                                  ),
                                                ),
                                                child: Text(
                                                  tieneVector ? 'ROSTRO REGISTRADO' : 'SIN ROSTRO',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: tieneVector ? AppColors.success : AppColors.warning,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),

                                              // Nombre de horario
                                              Expanded(
                                                child: Text(
                                                  horario != null
                                                      ? 'Horario: ${horario.tipo} (${horario.horaInicio} - ${horario.horaFinal})'
                                                      : 'Sin horario asignado',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Botones de acción
                                    Column(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.chevron_right, color: AppColors.primary),
                                          tooltip: 'Ver detalle',
                                          onPressed: () => context.go('${AppRoutes.empleados}/${emp.cedula}'),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: AppColors.error),
                                          tooltip: 'Eliminar',
                                          onPressed: () => _deleteEmpleado(emp.cedula, emp.nombre),
                                        ),
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go(AppRoutes.registroEmpleado),
        tooltip: 'Registrar nuevo empleado',
        child: const Icon(Icons.person_add),
      ),
    );
  }
}
