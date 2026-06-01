import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import '../../../core/routes/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/db_constants.dart';
import '../../../core/constants/api_constants.dart';
import '../../../data/datasources/local/database_helper.dart';
import '../../../data/models/permiso_model.dart';
import '../../../data/models/empleado_model.dart';
import '../../../services/sync_service.dart';
import '../../../services/connectivity_service.dart';

class PermisosPage extends StatefulWidget {
  const PermisosPage({super.key});

  @override
  State<PermisosPage> createState() => _PermisosPageState();
}

class _PermisosPageState extends State<PermisosPage> {
  final _searchCtrl = TextEditingController();
  final _db = DatabaseHelper();
  
  List<PermisoModel> _allPermisos = [];
  List<PermisoModel> _filteredPermisos = [];
  Map<String, EmpleadoModel> _empleadosMap = {};
  
  // Variables para la agrupación por empleado (Cédula)
  List<String> _groupedCedulas = [];
  Map<String, List<PermisoModel>> _groupedPermisos = {};
  
  String _selectedTipo = 'TODOS';
  String _selectedSync = 'TODOS';
  bool _loading = true;
  bool _syncing = false;
  
  // Rastrear qué grupos de empleados están expandidos (cerrados por defecto)
  final Map<String, bool> _expandedGroups = {};
  
  // Rastrear operaciones de sincronización individual por ID de permiso
  final Map<String, bool> _syncingPermisos = {};

  @override
  void initState() {
    super.initState();
    _loadPermisosData();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPermisosData() async {
    setState(() => _loading = true);
    try {
      // 1. Cargar empleados para mapear nombres
      final empleados = await _db.getAllEmpleados();
      _empleadosMap = {
        for (var e in empleados) e.cedula: e
      };

      // 2. Cargar todos los permisos de forma compatible tanto nativo como Web
      final list = await _db.getAllPermisos();

      setState(() {
        _allPermisos = list;
      });
      _onSearchChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar permisos: $e'),
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
    
    // 1. Filtrar registros planos
    final filtered = _allPermisos.where((p) {
      final empleado = _empleadosMap[p.cedulaEmpleado];
      final matchQuery = query.isEmpty ||
          p.cedulaEmpleado.toLowerCase().contains(query) ||
          (empleado != null && empleado.nombre.toLowerCase().contains(query));

      final matchTipo = _selectedTipo == 'TODOS' ||
          p.tipo.toUpperCase() == _selectedTipo;

      final matchSync = _selectedSync == 'TODOS' ||
          (_selectedSync == 'ENVIADO' && p.sincronizado) ||
          (_selectedSync == 'PENDIENTE' && !p.sincronizado);

      return matchQuery && matchTipo && matchSync;
    }).toList();

    // 2. Agrupar la lista filtrada por cédula
    final groupedCedulas = <String>[];
    final groupedPermisos = <String, List<PermisoModel>>{};

    for (final p in filtered) {
      if (!groupedPermisos.containsKey(p.cedulaEmpleado)) {
        groupedCedulas.add(p.cedulaEmpleado);
        groupedPermisos[p.cedulaEmpleado] = [];
      }
      groupedPermisos[p.cedulaEmpleado]!.add(p);
    }

    setState(() {
      _filteredPermisos = filtered;
      _groupedCedulas = groupedCedulas;
      _groupedPermisos = groupedPermisos;
    });
  }

  bool get _hasActiveFilters =>
      _searchCtrl.text.isNotEmpty ||
      _selectedTipo != 'TODOS' ||
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
        _loadPermisosData();
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

  Future<void> _syncSinglePermiso(PermisoModel p) async {
    if (p.id == null || _syncingPermisos[p.id!] == true) return;

    setState(() => _syncingPermisos[p.id!] = true);

    try {
      final connected = await ConnectivityService().isConnected();
      if (!connected) {
        throw Exception('Sin conexión a internet');
      }

      final baseUrl = await _db.getConfig(DbConstants.cfgUrlApi) ?? ApiConstants.defaultBaseUrl;
      final uri = Uri.parse('$baseUrl${ApiConstants.syncPermisos}');
      final body = jsonEncode([p.toMap()]);

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        await _db.marcarPermisoSincronizado(p.id!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permiso sincronizado exitosamente con el servidor central.'),
              backgroundColor: AppColors.success,
            ),
          );
        }
        _loadPermisosData();
      } else {
        throw Exception('Código de respuesta: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fallo al sincronizar permiso: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _syncingPermisos[p.id!] = false);
      }
    }
  }

  void _showAddPermisoDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _AddPermisoDialog(),
    ).then((value) {
      if (value == true) {
        _loadPermisosData();
        if (mounted) {
          context.read<SyncService>().syncAll();
        }
      }
    });
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

  Color _getPermisoColor(String tipo) {
    switch (tipo.toUpperCase()) {
      case 'CITA_MEDICA':
        return AppColors.colorAlmuerzo;
      case 'PERSONAL':
        return AppColors.accent;
      case 'LABORAL':
        return AppColors.primary;
      case 'TRASLADO':
        return AppColors.colorSalida;
      case 'FIN_CONTRATO':
        return AppColors.colorNoRegistrar;
      default:
        return AppColors.textSecondary;
    }
  }

  String _formatDateStr(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      return DateFormat('dd/MM/yyyy').format(dt);
    } catch (_) {
      return dateStr;
    }
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

  Widget _buildTipoDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedTipo,
      decoration: InputDecoration(
        labelText: 'Tipo de Permiso',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 14,
        fontWeight: _selectedTipo != 'TODOS' ? FontWeight.bold : FontWeight.normal,
      ),
      onChanged: (String? newValue) {
        if (newValue != null) {
          setState(() => _selectedTipo = newValue);
          _onSearchChanged();
        }
      },
      items: const [
        DropdownMenuItem(value: 'TODOS', child: Text('TODOS')),
        DropdownMenuItem(value: 'CITA_MEDICA', child: Text('Cita Médica')),
        DropdownMenuItem(value: 'PERSONAL', child: Text('Asunto Personal')),
        DropdownMenuItem(value: 'LABORAL', child: Text('Comisión Laboral')),
        DropdownMenuItem(value: 'TRASLADO', child: Text('Traslado de Sede')),
        DropdownMenuItem(value: 'FIN_CONTRATO', child: Text('Término de Contrato')),
      ],
    );
  }

  Widget _buildSyncDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedSync,
      decoration: InputDecoration(
        labelText: 'Estado Sincronización',
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
          _selectedTipo = 'TODOS';
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
            width: 1.5,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: const Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              'ESTADO',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: Text(
              'TIPO DE PERMISO',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              'VIGENCIA AUTORIZADA',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'SINCRONIZACIÓN',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              'ACCIONES',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(PermisoModel p, int index) {
    final isEven = index % 2 == 0;
    final color = _getPermisoColor(p.tipo);

    return Container(
      decoration: BoxDecoration(
        color: isEven
            ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.08)
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
          left: BorderSide(
            color: color,
            width: 4,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          // Icon Cell
          SizedBox(
            width: 60,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.assignment_turned_in_rounded, color: color, size: 18),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Tipo Chip Cell
          Expanded(
            flex: 3,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    p.tipo.replaceAll('_', ' ').toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Vigencia Cell
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vence: ${_formatDateStr(p.fechaFinal)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  'Del ${_formatDateStr(p.fechaInicio)} al ${_formatDateStr(p.fechaFinal)}',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),

          // Sincronización Cell
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: p.sincronizado
                        ? AppColors.successLight
                        : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: p.sincronizado
                          ? AppColors.success.withValues(alpha: 0.3)
                          : Theme.of(context).dividerColor.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        p.sincronizado ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                        color: p.sincronizado ? AppColors.success : AppColors.textDisabled,
                        size: 13,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        p.sincronizado ? 'Enviado' : 'Pendiente',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: p.sincronizado ? AppColors.success : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Acciones Cell
          SizedBox(
            width: 120,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!p.sincronizado) ...[
                  _syncingPermisos[p.id] == true
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        )
                      : IconButton(
                          icon: const Icon(Icons.cloud_upload_rounded, color: AppColors.primary, size: 20),
                          tooltip: 'Sincronizar ahora',
                          onPressed: () => _syncSinglePermiso(p),
                        ),
                ] else ...[
                  const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileRow(PermisoModel p) {
    final color = _getPermisoColor(p.tipo);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.assignment_turned_in_rounded, color: color, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.tipo.replaceAll('_', ' ').toUpperCase(),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: color),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Vence: ${_formatDateStr(p.fechaFinal)}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                  Text(
                    'Del ${_formatDateStr(p.fechaInicio)} al ${_formatDateStr(p.fechaFinal)}',
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!p.sincronizado) ...[
                  _syncingPermisos[p.id] == true
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        )
                      : IconButton(
                          icon: const Icon(Icons.cloud_upload_rounded, color: AppColors.primary, size: 18),
                          onPressed: () => _syncSinglePermiso(p),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                ] else ...[
                  const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListArea(bool isWide) {
    if (_groupedCedulas.isEmpty) {
      return _buildEmptyState();
    }

    if (isWide) {
      return ListView.builder(
        itemCount: _groupedCedulas.length,
        itemBuilder: (context, index) {
          final cedula = _groupedCedulas[index];
          final empleado = _empleadosMap[cedula];
          final permisosList = _groupedPermisos[cedula] ?? [];
          final pendingCount = permisosList.where((p) => !p.sincronizado).length;
          final isExpanded = _expandedGroups[cedula] ?? false;

          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cabecera Clickeable para Expandir/Contraer (Cerrado por defecto)
                InkWell(
                  onTap: () {
                    setState(() {
                      _expandedGroups[cedula] = !isExpanded;
                    });
                  },
                  borderRadius: isExpanded
                      ? const BorderRadius.vertical(top: Radius.circular(12))
                      : BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                      borderRadius: isExpanded
                          ? const BorderRadius.vertical(top: Radius.circular(12))
                          : BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.person_rounded, color: AppColors.primary, size: 22),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                empleado?.nombre ?? 'Empleado Desconocido',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Cédula: $cedula',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Badges de resumen
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${permisosList.length} Autorizaciones',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (pendingCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '$pendingCount Pendientes',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.warning,
                              ),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Sincronizado',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.success,
                              ),
                            ),
                          ),
                        const SizedBox(width: 16),
                        Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: AppColors.primary,
                          size: 24,
                        ),
                      ],
                    ),
                  ),
                ),

                // Tabla Interna Abierta
                if (isExpanded) ...[
                  _buildTableHeader(),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: permisosList.length,
                    itemBuilder: (context, rIndex) {
                      final p = permisosList[rIndex];
                      return _buildRow(p, rIndex);
                    },
                  ),
                ],
              ],
            ),
          );
        },
      );
    } else {
      // Mobile accordion cards (closed by default)
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _groupedCedulas.length,
        itemBuilder: (context, index) {
          final cedula = _groupedCedulas[index];
          final empleado = _empleadosMap[cedula];
          final permisosList = _groupedPermisos[cedula] ?? [];
          final pendingCount = permisosList.where((p) => !p.sincronizado).length;
          final isExpanded = _expandedGroups[cedula] ?? false;

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Cabecera Móvil
                  InkWell(
                    onTap: () {
                      setState(() {
                        _expandedGroups[cedula] = !isExpanded;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                            child: const Icon(Icons.person_rounded, color: AppColors.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  empleado?.nombre ?? 'Empleado Desconocido',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Cédula: $cedula • ${permisosList.length} permisos',
                                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (pendingCount > 0)
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.cloud_off_rounded, color: AppColors.warning, size: 16),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.cloud_done_rounded, color: AppColors.success, size: 16),
                            ),
                          const SizedBox(width: 8),
                          Icon(
                            isExpanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Listado Desplegado
                  if (isExpanded)
                    Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: permisosList.map((p) => _buildMobileRow(p)).toList(),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.event_available, size: 64, color: AppColors.textDisabled),
            const SizedBox(height: 16),
            Text(
              _allPermisos.isEmpty
                  ? 'No hay permisos registrados en el sistema.'
                  : 'Ningún permiso coincide con la búsqueda o filtros activos.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _showAddPermisoDialog,
              icon: const Icon(Icons.add),
              label: const Text('Registrar Nuevo Permiso'),
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
    final totalFiltered = _filteredPermisos.length;
    final totalAll = _allPermisos.length;
    final totalSynced = _filteredPermisos.where((p) => p.sincronizado).length;
    final totalPending = totalFiltered - totalSynced;
    
    // Contar permisos vigentes
    final activeCount = _filteredPermisos.where((p) {
      try {
        final f = DateTime.parse(p.fechaFinal);
        final today = DateTime.now();
        final normalizedToday = DateTime(today.year, today.month, today.day);
        return f.isAfter(normalizedToday) || f.isAtSameMomentAs(normalizedToday);
      } catch (_) {
        return true;
      }
    }).length;

    final pagePadding = isWide ? const EdgeInsets.all(24) : const EdgeInsets.all(12);
    final statsAspectRatio = width > 600 ? 2.8 : (width > 420 ? 2.3 : 1.9);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Permisos'),
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
                            title: 'Permisos en Vista',
                            value: '$totalFiltered / $totalAll',
                            icon: Icons.assignment_turned_in_rounded,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildStatCard(
                            title: 'Sincronizados (Nube)',
                            value: '$totalSynced',
                            icon: Icons.cloud_done_rounded,
                            color: AppColors.success,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildStatCard(
                            title: 'Pendientes (Local)',
                            value: '$totalPending',
                            icon: Icons.cloud_off_rounded,
                            color: AppColors.warning,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildStatCard(
                            title: 'Permisos Vigentes',
                            value: '$activeCount',
                            icon: Icons.event_available_rounded,
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
                          title: 'Permisos',
                          value: '$totalFiltered / $totalAll',
                          icon: Icons.assignment_turned_in_rounded,
                          color: AppColors.primary,
                        ),
                        _buildStatCard(
                          title: 'Sincronizados',
                          value: '$totalSynced',
                          icon: Icons.cloud_done_rounded,
                          color: AppColors.success,
                        ),
                        _buildStatCard(
                          title: 'Pendientes',
                          value: '$totalPending',
                          icon: Icons.cloud_off_rounded,
                          color: AppColors.warning,
                        ),
                        _buildStatCard(
                          title: 'Vigentes',
                          value: '$activeCount',
                          icon: Icons.event_available_rounded,
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
                                Expanded(flex: 2, child: _buildTipoDropdown()),
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
                                    Expanded(child: _buildTipoDropdown()),
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

                  // 3. Listado Grupal Colapsable
                  Expanded(
                    child: _buildListArea(isWide),
                  ),
                ],
              ),
            ),
      floatingActionButton: _allPermisos.isNotEmpty
          ? FloatingActionButton(
              onPressed: _showAddPermisoDialog,
              tooltip: 'Registrar nuevo permiso',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class _AddPermisoDialog extends StatefulWidget {
  const _AddPermisoDialog();

  @override
  State<_AddPermisoDialog> createState() => _AddPermisoDialogState();
}

class _AddPermisoDialogState extends State<_AddPermisoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _db = DatabaseHelper();

  List<EmpleadoModel> _empleados = [];
  String? _selectedCedula;
  
  String _tipo = 'CITA_MEDICA';
  DateTime _fechaInicio = DateTime.now();
  DateTime _fechaFinal = DateTime.now().add(const Duration(days: 1));
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadEmpleados();
  }

  Future<void> _loadEmpleados() async {
    try {
      final list = await _db.getAllEmpleados();
      final activeList = list.where((e) => e.estado == 'ACTIVO').toList();
      setState(() {
        _empleados = activeList;
        if (activeList.isNotEmpty) {
          _selectedCedula = activeList.first.cedula;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar empleados: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _selectDate(bool esInicio) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: esInicio ? _fechaInicio : _fechaFinal,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        if (esInicio) {
          _fechaInicio = picked;
          if (_fechaFinal.isBefore(_fechaInicio)) {
            _fechaFinal = _fechaInicio.add(const Duration(days: 1));
          }
        } else {
          _fechaFinal = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCedula == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione un empleado'), backgroundColor: AppColors.warning),
      );
      return;
    }

    if (_fechaFinal.isBefore(_fechaInicio)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La fecha final no puede ser anterior a la inicial'), backgroundColor: AppColors.warning),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final permiso = PermisoModel(
        usuarioRegistrador: 'admin',
        cedulaEmpleado: _selectedCedula!,
        fechaHora: DateTime.now().toIso8601String().substring(0, 19),
        tipo: _tipo,
        fechaInicio: DateFormat('yyyy-MM-dd').format(_fechaInicio),
        fechaFinal: DateFormat('yyyy-MM-dd').format(_fechaFinal),
        sincronizado: false,
      );

      await _db.insertPermiso(permiso);
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar permiso: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar Permiso'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Selección de Empleado
              DropdownButtonFormField<String>(
                initialValue: _selectedCedula,
                decoration: const InputDecoration(labelText: 'Empleado Autorizado'),
                items: _empleados.map((e) {
                  return DropdownMenuItem<String>(
                    value: e.cedula,
                    child: Text(e.nombre),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedCedula = val);
                },
                validator: (v) => v == null ? 'Seleccione un empleado' : null,
              ),
              if (_empleados.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 8),
                  child: Text(
                    '⚠️ Cree un empleado en "Empleados" primero.',
                    style: TextStyle(color: AppColors.warning, fontSize: 11),
                  ),
                ),
              const SizedBox(height: 16),

              // Tipo de Permiso
              DropdownButtonFormField<String>(
                initialValue: _tipo,
                decoration: const InputDecoration(labelText: 'Motivo / Tipo de Permiso'),
                items: const [
                  DropdownMenuItem(value: 'CITA_MEDICA', child: Text('Cita Médica')),
                  DropdownMenuItem(value: 'PERSONAL', child: Text('Asunto Personal')),
                  DropdownMenuItem(value: 'LABORAL', child: Text('Comisión Laboral')),
                  DropdownMenuItem(value: 'TRASLADO', child: Text('Traslado de Sede')),
                  DropdownMenuItem(value: 'FIN_CONTRATO', child: Text('Término de Contrato')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _tipo = val);
                },
              ),
              const SizedBox(height: 20),

              // Rango de Fechas
              Text(
                'Rango de Vigencia',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _selectDate(true),
                      icon: const Icon(Icons.date_range, size: 16),
                      label: Text('Desde: ${DateFormat('dd/MM').format(_fechaInicio)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _selectDate(false),
                      icon: const Icon(Icons.date_range, size: 16),
                      label: Text('Hasta: ${DateFormat('dd/MM').format(_fechaFinal)}'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _saving || _empleados.isEmpty ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Autorizar Permiso'),
        ),
      ],
    );
  }
}
