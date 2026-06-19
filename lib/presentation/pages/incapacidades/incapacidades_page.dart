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
import '../../../data/models/incapacidad_model.dart';
import '../../../data/models/empleado_model.dart';
import '../../../services/sync_service.dart';
import '../../../services/connectivity_service.dart';

class IncapacidadesPage extends StatefulWidget {
  const IncapacidadesPage({super.key});

  @override
  State<IncapacidadesPage> createState() => _IncapacidadesPageState();
}

class _IncapacidadesPageState extends State<IncapacidadesPage> {
  final _searchCtrl = TextEditingController();
  final _db = DatabaseHelper();

  List<IncapacidadModel> _allIncapacidades = [];
  List<IncapacidadModel> _filteredIncapacidades = [];
  Map<String, EmpleadoModel> _empleadosMap = {};

  // Variables para la agrupación por empleado (Cédula)
  List<String> _groupedCedulas = [];
  Map<String, List<IncapacidadModel>> _groupedIncapacidades = {};

  String _selectedTipo = 'TODOS';
  String _selectedSync = 'TODOS';
  bool _loading = true;
  bool _syncing = false;

  // Rastrear qué grupos de empleados están expandidos (cerrados por defecto)
  final Map<String, bool> _expandedGroups = {};

  // Rastrear operaciones de sincronización individual por ID de incapacidad
  final Map<String, bool> _syncingIncapacidades = {};

  @override
  void initState() {
    super.initState();
    _loadIncapacidadesData();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadIncapacidadesData() async {
    setState(() => _loading = true);
    try {
      // 1. Cargar empleados para mapear nombres
      final empleados = await _db.getAllEmpleados();
      _empleadosMap = {for (var e in empleados) e.cedula: e};

      // 2. Cargar todas las incapacidades
      final list = await _db.getAllIncapacidades();

      setState(() {
        _allIncapacidades = list;
      });
      _onSearchChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar incapacidades: $e'),
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
    final filtered = _allIncapacidades.where((p) {
      final empleado = _empleadosMap[p.cedulaEmpleado];
      final matchQuery =
          query.isEmpty ||
          p.cedulaEmpleado.toLowerCase().contains(query) ||
          (empleado != null && empleado.nombre.toLowerCase().contains(query));

      final matchTipo =
          _selectedTipo == 'TODOS' || p.tipo.toUpperCase() == _selectedTipo;

      final matchSync =
          _selectedSync == 'TODOS' ||
          (_selectedSync == 'ENVIADO' && p.sincronizado) ||
          (_selectedSync == 'PENDIENTE' && !p.sincronizado);

      return matchQuery && matchTipo && matchSync;
    }).toList();

    // 2. Agrupar la lista filtrada por cédula
    final groupedCedulas = <String>[];
    final groupedIncapacidades = <String, List<IncapacidadModel>>{};

    for (final p in filtered) {
      if (!groupedIncapacidades.containsKey(p.cedulaEmpleado)) {
        groupedCedulas.add(p.cedulaEmpleado);
        groupedIncapacidades[p.cedulaEmpleado] = [];
      }
      groupedIncapacidades[p.cedulaEmpleado]!.add(p);
    }

    setState(() {
      _filteredIncapacidades = filtered;
      _groupedCedulas = groupedCedulas;
      _groupedIncapacidades = groupedIncapacidades;
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
              content: Text(
                'Sincronización finalizada con errores: ${result.errors.first}',
              ),
              backgroundColor: AppColors.warning,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('¡Éxito! Sincronización bidireccional completada.'),
              backgroundColor: AppColors.success,
            ),
          );
        }
        _loadIncapacidadesData();
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

  Future<void> _syncSingleIncapacidad(IncapacidadModel p) async {
    if (p.id == null || _syncingIncapacidades[p.id!] == true) return;

    setState(() => _syncingIncapacidades[p.id!] = true);

    try {
      final connected = await ConnectivityService().isConnected();
      if (!connected) {
        throw Exception('Sin conexión a internet');
      }

      final baseUrl =
          await _db.getConfig(DbConstants.cfgUrlApi) ??
          ApiConstants.defaultBaseUrl;
      final uri = Uri.parse('$baseUrl/api/sync/incapacidades');
      final body = jsonEncode([p.toMap()]);

      final response = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        await _db.marcarIncapacidadSincronizada(p.id!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Incapacidad sincronizada exitosamente con el servidor.',
              ),
              backgroundColor: AppColors.success,
            ),
          );
        }
        _loadIncapacidadesData();
      } else {
        throw Exception('Código de respuesta: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fallo al sincronizar incapacidad: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _syncingIncapacidades[p.id!] = false);
      }
    }
  }

  void _showAddIncapacidadDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _AddIncapacidadDialog(),
    ).then((value) {
      if (value == true) {
        _loadIncapacidadesData();
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
        border: Border.all(color: color.withValues(alpha: 0.15), width: 1.5),
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

  Color _getIncapacidadColor(String tipo) {
    switch (tipo.toUpperCase()) {
      case 'EG':
        return Colors.red.shade700;
      case 'AL':
        return Colors.orange.shade700;
      case 'EL':
        return Colors.brown.shade600;
      case 'LM':
        return Colors.purple.shade700;
      default:
        return AppColors.textSecondary;
    }
  }

  String _getTipoLabel(String tipo) {
    switch (tipo.toUpperCase()) {
      case 'EG':
        return 'Enfermedad General';
      case 'AL':
        return 'Accidente Laboral';
      case 'EL':
        return 'Enfermedad laboral';
      case 'LM':
        return 'Maternidad / Paternidad';
      default:
        return tipo;
    }
  }

  String _formatDateStr(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      return DateFormat('dd/MM/yyyy hh:mm a').format(dt);
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
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      onChanged: (_) => _onSearchChanged(),
    );
  }

  Widget _buildTipoDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedTipo,
      decoration: InputDecoration(
        labelText: 'Tipo de Incapacidad',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 14,
        fontWeight: _selectedTipo != 'TODOS'
            ? FontWeight.bold
            : FontWeight.normal,
      ),
      onChanged: (String? newValue) {
        if (newValue != null) {
          setState(() => _selectedTipo = newValue);
          _onSearchChanged();
        }
      },
      items: const [
        DropdownMenuItem(value: 'TODOS', child: Text('TODOS')),
        DropdownMenuItem(value: 'EG', child: Text('Enfermedad General (EG)')),
        DropdownMenuItem(value: 'AL', child: Text('Accidente Laboral (AL)')),
        DropdownMenuItem(
          value: 'EL',
          child: Text('Enfermedad Profesional (EL)'),
        ),
        DropdownMenuItem(
          value: 'LM',
          child: Text('Maternidad / Paternidad (LM)'),
        ),
      ],
    );
  }

  Widget _buildSyncDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedSync,
      decoration: InputDecoration(
        labelText: 'Estado Sincronización',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 14,
        fontWeight: _selectedSync != 'TODOS'
            ? FontWeight.bold
            : FontWeight.normal,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
          SizedBox(
            width: 60,
            child: Text(
              'Estado',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: AppColors.primaryDark,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: Text(
              'Tipo de Incapacidad',
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
              'Vigencia Autorizada',
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
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 120,
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

  Widget _buildRow(IncapacidadModel p, int index) {
    final isEven = index % 2 == 0;
    final color = _getIncapacidadColor(p.tipo);
    final rowColor = isEven ? Colors.white : Colors.grey.shade50;

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
                child: Icon(
                  Icons.medical_services_rounded,
                  color: color,
                  size: 18,
                ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _getTipoLabel(p.tipo).toUpperCase(),
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
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Del ${_formatDateStr(p.fechaInicio)} al ${_formatDateStr(p.fechaFinal)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (p.observacion != null && p.observacion!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Obs: ${p.observacion}',
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: p.sincronizado
                        ? AppColors.successLight
                        : Theme.of(context).colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: p.sincronizado
                          ? AppColors.success.withValues(alpha: 0.3)
                          : Theme.of(
                              context,
                            ).dividerColor.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        p.sincronizado
                            ? Icons.cloud_done_rounded
                            : Icons.cloud_off_rounded,
                        color: p.sincronizado
                            ? AppColors.success
                            : AppColors.textDisabled,
                        size: 13,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        p.sincronizado ? 'Enviado' : 'Pendiente',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: p.sincronizado
                              ? AppColors.success
                              : AppColors.textSecondary,
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
                  _syncingIncapacidades[p.id] == true
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : IconButton(
                          icon: const Icon(
                            Icons.cloud_upload_rounded,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          tooltip: 'Sincronizar ahora',
                          onPressed: () => _syncSingleIncapacidad(p),
                        ),
                ] else ...[
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                    size: 20,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileRow(IncapacidadModel p) {
    final color = _getIncapacidadColor(p.tipo);

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
              child: Icon(
                Icons.medical_services_rounded,
                color: color,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getTipoLabel(p.tipo).toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Vence: ${_formatDateStr(p.fechaFinal)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    'Del ${_formatDateStr(p.fechaInicio)} al ${_formatDateStr(p.fechaFinal)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (p.observacion != null && p.observacion!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Obs: ${p.observacion}',
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!p.sincronizado) ...[
                  _syncingIncapacidades[p.id] == true
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : IconButton(
                          icon: const Icon(
                            Icons.cloud_upload_rounded,
                            color: AppColors.primary,
                            size: 18,
                          ),
                          onPressed: () => _syncSingleIncapacidad(p),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                ] else ...[
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                    size: 18,
                  ),
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
          final incapacidadesList = _groupedIncapacidades[cedula] ?? [];
          final pendingCount = incapacidadesList
              .where((p) => !p.sincronizado)
              .length;
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
                // Cabecera Clickeable para Expandir/Contraer
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.25),
                      borderRadius: isExpanded
                          ? const BorderRadius.vertical(
                              top: Radius.circular(12),
                            )
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
                          child: const Icon(
                            Icons.person_rounded,
                            color: AppColors.primary,
                            size: 22,
                          ),
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
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Badges de resumen
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${incapacidadesList.length} Registros',
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
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
                    itemCount: incapacidadesList.length,
                    itemBuilder: (context, rIndex) {
                      final p = incapacidadesList[rIndex];
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
      // Mobile accordion cards
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _groupedCedulas.length,
        itemBuilder: (context, index) {
          final cedula = _groupedCedulas[index];
          final empleado = _empleadosMap[cedula];
          final incapacidadesList = _groupedIncapacidades[cedula] ?? [];
          final pendingCount = incapacidadesList
              .where((p) => !p.sincronizado)
              .length;
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: AppColors.primary.withValues(
                              alpha: 0.1,
                            ),
                            child: const Icon(
                              Icons.person_rounded,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  empleado?.nombre ?? 'Empleado Desconocido',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Cédula: $cedula • ${incapacidadesList.length} registros',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (pendingCount > 0)
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(
                                  alpha: 0.15,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.cloud_off_rounded,
                                color: AppColors.warning,
                                size: 16,
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(
                                  alpha: 0.15,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.cloud_done_rounded,
                                color: AppColors.success,
                                size: 16,
                              ),
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
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.15),
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: incapacidadesList
                            .map((p) => _buildMobileRow(p))
                            .toList(),
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
            const Icon(
              Icons.medical_services_outlined,
              size: 64,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: 16),
            Text(
              _allIncapacidades.isEmpty
                  ? 'No hay incapacidades registradas en el sistema.'
                  : 'Ninguna incapacidad coincide con la búsqueda.',
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
    final totalFiltered = _filteredIncapacidades.length;
    final totalAll = _allIncapacidades.length;
    final totalSynced = _filteredIncapacidades
        .where((p) => p.sincronizado)
        .length;
    final totalPending = totalFiltered - totalSynced;

    // Contar incapacidades vigentes
    final activeCount = _filteredIncapacidades.where((p) {
      try {
        final f = DateTime.parse(p.fechaFinal);
        final today = DateTime.now();
        final normalizedToday = DateTime(today.year, today.month, today.day);
        return f.isAfter(normalizedToday) ||
            f.isAtSameMomentAs(normalizedToday);
      } catch (_) {
        return true;
      }
    }).length;

    final pagePadding = isWide
        ? const EdgeInsets.all(24)
        : const EdgeInsets.all(12);
    final statsAspectRatio = width > 600 ? 2.8 : (width > 420 ? 2.3 : 1.9);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Incapacidades'),
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
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
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
                  // 1. Dashboard de Métricas Clave
                  if (isWide)
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            title: 'Incapacidades en Vista',
                            value: '$totalFiltered / $totalAll',
                            icon: Icons.medical_services_rounded,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildStatCard(
                            title: 'Incapacidades Vigentes',
                            value: '$activeCount',
                            icon: Icons.event_available_rounded,
                            color: AppColors.info,
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            title: 'Incapacidades',
                            value: '$totalFiltered / $totalAll',
                            icon: Icons.medical_services_rounded,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            title: 'Vigentes',
                            value: '$activeCount',
                            icon: Icons.event_available_rounded,
                            color: AppColors.info,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 20),

                  // 2. Barra de Filtros
                  Card(
                    elevation: 1.5,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
                  Expanded(child: _buildListArea(isWide)),
                ],
              ),
            ),
      floatingActionButton: null,
    );
  }
}

class _AddIncapacidadDialog extends StatefulWidget {
  const _AddIncapacidadDialog();

  @override
  State<_AddIncapacidadDialog> createState() => _AddIncapacidadDialogState();
}

class _AddIncapacidadDialogState extends State<_AddIncapacidadDialog> {
  final _formKey = GlobalKey<FormState>();
  final _db = DatabaseHelper();
  final _observacionCtrl = TextEditingController();

  List<EmpleadoModel> _empleados = [];
  String? _selectedCedula;

  String _tipo = 'EG';
  DateTime _fechaInicio = DateTime.now();
  DateTime _fechaFinal = DateTime.now().add(const Duration(days: 1));
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadEmpleados();
  }

  @override
  void dispose() {
    _observacionCtrl.dispose();
    super.dispose();
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
          SnackBar(
            content: Text('Error al cargar empleados: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _selectDateTime(bool esInicio) async {
    final initialDateTime = esInicio ? _fechaInicio : _fechaFinal;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDateTime,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (pickedDate != null) {
      if (!mounted) return;
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initialDateTime),
      );
      if (pickedTime != null) {
        setState(() {
          final combined = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
          if (esInicio) {
            _fechaInicio = combined;
            if (_fechaFinal.isBefore(_fechaInicio)) {
              _fechaFinal = _fechaInicio.add(const Duration(days: 1));
            }
          } else {
            _fechaFinal = combined;
          }
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCedula == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleccione un empleado'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    if (_fechaFinal.isBefore(_fechaInicio)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La fecha y hora final no puede ser anterior a la inicial',
          ),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final incapacidad = IncapacidadModel(
        usuarioRegistrador: 'admin',
        cedulaEmpleado: _selectedCedula!,
        fechaHora: DateTime.now()
            .toIso8601String()
            .substring(0, 19)
            .replaceAll('T', ' '),
        tipo: _tipo,
        fechaInicio: DateFormat('yyyy-MM-dd HH:mm:ss').format(_fechaInicio),
        fechaFinal: DateFormat('yyyy-MM-dd HH:mm:ss').format(_fechaFinal),
        observacion: _observacionCtrl.text.trim(),
        sincronizado: false,
      );

      await _db.insertIncapacidad(incapacidad);
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar incapacidad: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar Incapacidad'),
      content: SingleChildScrollView(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Selección de Empleado
                DropdownButtonFormField<String>(
                  initialValue: _selectedCedula,
                  decoration: const InputDecoration(
                    labelText: 'Empleado Autorizado',
                  ),
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
                  const Padding(
                    padding: EdgeInsets.only(top: 4, left: 8),
                    child: Text(
                      '⚠️ Cree un empleado en "Empleados" primero.',
                      style: TextStyle(color: AppColors.warning, fontSize: 11),
                    ),
                  ),
                const SizedBox(height: 16),

                // Tipo de Incapacidad
                DropdownButtonFormField<String>(
                  initialValue: _tipo,
                  decoration: const InputDecoration(
                    labelText: 'Motivo / Tipo de Incapacidad',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'EG',
                      child: Text('Enfermedad General (EG)'),
                    ),
                    DropdownMenuItem(
                      value: 'AL',
                      child: Text('Accidente Laboral (AL)'),
                    ),
                    DropdownMenuItem(
                      value: 'EL',
                      child: Text('Enfermedad Profesional (EL)'),
                    ),
                    DropdownMenuItem(
                      value: 'LM',
                      child: Text('Maternidad / Paternidad (LM)'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _tipo = val);
                  },
                ),
                const SizedBox(height: 20),

                // Rango de Fechas
                const Text(
                  'Vigencia de Incapacidad',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _selectDateTime(true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 8,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Desde',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                DateFormat(
                                  'dd/MM/yy hh:mm a',
                                ).format(_fechaInicio),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () => _selectDateTime(false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 8,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Hasta',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                DateFormat(
                                  'dd/MM/yy hh:mm a',
                                ).format(_fechaFinal),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Observación
                TextFormField(
                  controller: _observacionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones / Diagnóstico',
                    hintText: 'Ej. Descanso médico de EPS...',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
