import 'dart:convert';
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
import '../../../services/connectivity_service.dart';

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
  Map<String, String> _seccionesMap = {};
  
  String _selectedFacial = 'TODOS';
  String _selectedSync = 'TODOS';
  bool _loading = true;
  bool _syncing = false;
  
  
  
  // Rastrear operaciones de sincronización individual por Cédula
  final Map<String, bool> _syncingEmployees = {};

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

      // 2. Cargar secciones en un mapa para traducción rápida
      final seccionesList = await _db.getSecciones();
      _seccionesMap = {
        for (var s in seccionesList) s['id_seccion'] as String: s['descripcion'] as String
      };

      // 3. Cargar todos los empleados activos
      final list = await _db.getAllEmpleados();
      final activeList = list.where((e) => e.estado == 'ACTIVO').toList();
      
      setState(() {
        _allEmpleados = activeList;
      });
      _onSearchChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar datos: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  void _onSearchChanged() {
    final query = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      _filteredEmpleados = _allEmpleados.where((e) {
        final matchQuery = query.isEmpty ||
            e.nombre.toLowerCase().contains(query) ||
            e.cedula.toLowerCase().contains(query);

        final tieneRostro = e.mapaVectorFoto.isNotEmpty;
        final matchFacial = _selectedFacial == 'TODOS' ||
            (_selectedFacial == 'REGISTRADO' && tieneRostro) ||
            (_selectedFacial == 'SIN_ROSTRO' && !tieneRostro);

        final matchSync = _selectedSync == 'TODOS' ||
            (_selectedSync == 'ENVIADO' && e.sincronizado) ||
            (_selectedSync == 'PENDIENTE' && !e.sincronizado);

        return matchQuery && matchFacial && matchSync;
      }).toList();
    });
  }

  bool get _hasActiveFilters =>
      _searchCtrl.text.isNotEmpty ||
      _selectedFacial != 'TODOS' ||
      _selectedSync != 'TODOS';

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

  Future<void> _syncSingleEmpleado(EmpleadoModel emp) async {
    if (_syncingEmployees[emp.cedula] == true) return;
    setState(() => _syncingEmployees[emp.cedula] = true);

    try {
      final connected = await ConnectivityService().isConnected();
      if (!connected) {
        throw Exception('Sin conexión a internet');
      }

      final baseUrl = await _db.getConfig(DbConstants.cfgUrlApi) ?? ApiConstants.defaultBaseUrl;
      final uri = Uri.parse('$baseUrl/api/sync/empleados');
      final body = jsonEncode([emp.toMap()]);

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final updated = emp.copyWith(sincronizado: true);
        await _db.updateEmpleado(updated);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Enrolamiento facial sincronizado con el servidor central.'),
              backgroundColor: AppColors.success,
            ),
          );
        }
        _loadData();
      } else {
        throw Exception('Código de respuesta: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fallo al sincronizar enrolamiento: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _syncingEmployees[emp.cedula] = false);
      }
    }
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

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchCtrl,
      decoration: InputDecoration(
        labelText: 'Buscar empleado por nombre o CC',
        hintText: 'Ingresa nombre o cédula...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchCtrl.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchCtrl.clear();
                  _onSearchChanged();
                },
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      onChanged: (_) => _onSearchChanged(),
    );
  }

  Widget _buildFacialDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedFacial,
      decoration: InputDecoration(
        labelText: 'Estado Facial',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 14,
        fontWeight: _selectedFacial != 'TODOS' ? FontWeight.bold : FontWeight.normal,
      ),
      onChanged: (String? newValue) {
        if (newValue != null) {
          setState(() => _selectedFacial = newValue);
          _onSearchChanged();
        }
      },
      items: const [
        DropdownMenuItem(value: 'TODOS', child: Text('TODOS')),
        DropdownMenuItem(value: 'REGISTRADO', child: Text('Con Rostro')),
        DropdownMenuItem(value: 'SIN_ROSTRO', child: Text('Sin Rostro')),
      ],
    );
  }

  Widget _buildSyncDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedSync,
      decoration: InputDecoration(
        labelText: 'Sincronización en Nube',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 14,
        fontWeight: _selectedSync != 'TODOS' ? FontWeight.bold : FontWeight.normal,
      ),
      onChanged: (String? newValue) {
        if (newValue != null) {
          setState(() => _selectedSync = newValue);
          _onSearchChanged();
        }
      },
      items: const [
        DropdownMenuItem(value: 'TODOS', child: Text('TODOS')),
        DropdownMenuItem(value: 'ENVIADO', child: Text('Sincronizados')),
        DropdownMenuItem(value: 'PENDIENTE', child: Text('Pendientes')),
      ],
    );
  }

  Widget _buildClearFiltersButton() {
    return OutlinedButton.icon(
      onPressed: () {
        _searchCtrl.clear();
        setState(() {
          _selectedFacial = 'TODOS';
          _selectedSync = 'TODOS';
        });
        _onSearchChanged();
      },
      icon: const Icon(Icons.filter_alt_off, color: AppColors.error, size: 18),
      label: const Text(
        'Limpiar Filtros',
        style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        side: const BorderSide(color: AppColors.error, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(7),
          topRight: Radius.circular(7),
        ),
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            flex: 2,
            child: Text(
              'Firma Facial',
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
              'Horario / Sección',
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
              'Sincronización',
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
              'Acciones',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: AppColors.primaryDark,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(EmpleadoModel emp, int index) {
    final tieneRostro = emp.mapaVectorFoto.isNotEmpty;
    final colorRostro = tieneRostro ? AppColors.success : AppColors.warning;
    final bgRostro = tieneRostro ? AppColors.successLight : AppColors.warningLight;
    final textRostro = tieneRostro ? 'ENROLADO' : 'SIN ROSTRO';
    final iconRostro = tieneRostro ? Icons.face_rounded : Icons.face_retouching_off_rounded;

    final horario = emp.horarioId != null ? _horariosMap[emp.horarioId] : null;
    final horarioText = horario != null
        ? '${horario.tipo} (${horario.horaInicio} - ${horario.horaFinal})'
        : 'Sin Horario';
    
    final seccionText = (emp.tipo == 'OPERATIVO' || emp.tipo == null) && emp.idSeccion != null
        ? _seccionesMap[emp.idSeccion] ?? emp.idSeccion!
        : null;

    final colorSync = emp.sincronizado ? AppColors.success : AppColors.warning;
    final bgSync = emp.sincronizado ? AppColors.successLight : AppColors.warningLight;
    final textSync = emp.sincronizado ? 'NUBE AL DÍA' : 'PENDIENTE';
    final iconSync = emp.sincronizado ? Icons.cloud_done_rounded : Icons.cloud_off_rounded;

    final rowColor = index.isEven ? Colors.white : Colors.grey.shade50;

    return Container(
      decoration: BoxDecoration(
        color: rowColor,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Cédula
          Expanded(
            flex: 2,
            child: Text(
              emp.cedula,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),

          // Colaborador
          Expanded(
            flex: 3,
            child: Text(
              emp.nombre,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Tipo
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

          // Firma Facial
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: bgRostro,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorRostro.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(iconRostro, color: colorRostro, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      textRostro,
                      style: TextStyle(
                        color: colorRostro,
                        fontWeight: FontWeight.bold,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Horario / Sección
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  horarioText,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (seccionText != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Sección: $seccionText',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // Sincronización
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: bgSync,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorSync.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(iconSync, color: colorSync, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      textSync,
                      style: TextStyle(
                        color: colorSync,
                        fontWeight: FontWeight.bold,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Acciones
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Ver Detalles / Editar
                IconButton(
                  icon: const Icon(Icons.visibility_outlined, color: AppColors.primary, size: 18),
                  tooltip: 'Ver Detalles',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => context.go('${AppRoutes.empleados}/${emp.cedula}'),
                ),
                const SizedBox(width: 8),

                // Sincronizar individual (Solo si tiene rostro y no está sincronizado)
                if (tieneRostro && !emp.sincronizado) ...[
                  _syncingEmployees[emp.cedula] == true
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        )
                      : IconButton(
                          icon: const Icon(Icons.cloud_upload_rounded, color: AppColors.success, size: 18),
                          tooltip: 'Sincronizar Nube',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _syncSingleEmpleado(emp),
                        ),
                  const SizedBox(width: 8),
                ],

                // Inactivar
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 18),
                  tooltip: 'Inactivar Empleado',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _deleteEmpleado(emp.cedula, emp.nombre),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_outline, size: 64, color: AppColors.textDisabled),
            const SizedBox(height: 16),
            Text(
              _allEmpleados.isEmpty
                  ? 'No hay empleados registrados en el sistema.'
                  : 'Ningún empleado coincide con la búsqueda o filtros activos.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 900;
    final width = MediaQuery.of(context).size.width;

    // Calcular estadísticas
    final totalFiltered = _filteredEmpleados.length;
    final totalAll = _allEmpleados.length;
    final totalEnrolled = _filteredEmpleados.where((e) => e.mapaVectorFoto.isNotEmpty).length;
    final totalUnenrolled = totalFiltered - totalEnrolled;
    final totalSynced = _filteredEmpleados.where((e) => e.sincronizado).length;

    final pagePadding = isWide ? const EdgeInsets.all(24) : const EdgeInsets.all(12);
    final statsAspectRatio = width > 600 ? 2.8 : (width > 420 ? 2.3 : 1.9);

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
          : Padding(
              padding: pagePadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Dashboard de Métricas Clave (Top Row)
                  if (isWide)
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            title: 'Empleados en Vista',
                            value: '$totalFiltered / $totalAll',
                            icon: Icons.people_rounded,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildStatCard(
                            title: 'Rostros Registrados',
                            value: '$totalEnrolled',
                            icon: Icons.face_rounded,
                            color: AppColors.success,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildStatCard(
                            title: 'Sin Rostro Registrado',
                            value: '$totalUnenrolled',
                            icon: Icons.face_retouching_off_rounded,
                            color: AppColors.warning,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildStatCard(
                            title: 'Sincronizados en Nube',
                            value: '$totalSynced',
                            icon: Icons.cloud_done_rounded,
                            color: AppColors.info,
                          ),
                        ),
                      ],
                    )
                  else
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: statsAspectRatio,
                      children: [
                        _buildStatCard(
                          title: 'Empleados',
                          value: '$totalFiltered / $totalAll',
                          icon: Icons.people_rounded,
                          color: AppColors.primary,
                        ),
                        _buildStatCard(
                          title: 'Con Rostro',
                          value: '$totalEnrolled',
                          icon: Icons.face_rounded,
                          color: AppColors.success,
                        ),
                        _buildStatCard(
                          title: 'Sin Rostro',
                          value: '$totalUnenrolled',
                          icon: Icons.face_retouching_off_rounded,
                          color: AppColors.warning,
                        ),
                        _buildStatCard(
                          title: 'Sincronizados',
                          value: '$totalSynced',
                          icon: Icons.cloud_done_rounded,
                          color: AppColors.info,
                        ),
                      ],
                    ),
                  const SizedBox(height: 20),

                  // 2. Barra de Filtros Dinámicos
                  Card(
                    elevation: 1.5,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: isWide
                          ? Row(
                              children: [
                                Expanded(flex: 3, child: _buildSearchField()),
                                const SizedBox(width: 12),
                                Expanded(flex: 2, child: _buildFacialDropdown()),
                                const SizedBox(width: 12),
                                Expanded(flex: 2, child: _buildSyncDropdown()),
                                if (_hasActiveFilters) ...[
                                  const SizedBox(width: 12),
                                  _buildClearFiltersButton(),
                                ],
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildSearchField(),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(child: _buildFacialDropdown()),
                                    const SizedBox(width: 10),
                                    Expanded(child: _buildSyncDropdown()),
                                  ],
                                ),
                                if (_hasActiveFilters) ...[
                                  const SizedBox(height: 10),
                                  _buildClearFiltersButton(),
                                ],
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 3. Listado de Empleados (Estilo CSS Table)
                  Expanded(
                    child: _filteredEmpleados.isEmpty
                        ? _buildEmptyState()
                        : Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300, width: 1),
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
                                _buildTableHeader(),
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: _filteredEmpleados.length,
                                    itemBuilder: (context, index) {
                                      final emp = _filteredEmpleados[index];
                                      return _buildTableRow(emp, index);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'btn_registro_masivo',
            onPressed: () => context.go(AppRoutes.registroMasivo),
            tooltip: 'Importación Masiva (Excel/CSV)',
            backgroundColor: AppColors.info,
            child: const Icon(Icons.file_upload),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'btn_registro_individual',
            onPressed: () => context.go(AppRoutes.registroEmpleado),
            tooltip: 'Registrar nuevo empleado',
            child: const Icon(Icons.person_add),
          ),
        ],
      ),
    );
  }
}
