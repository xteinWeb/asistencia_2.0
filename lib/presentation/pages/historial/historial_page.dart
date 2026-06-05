import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import '../../../core/routes/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/db_constants.dart';
import '../../../core/constants/api_constants.dart';
import '../../../data/datasources/local/database_helper.dart';
import '../../../data/models/registro_model.dart';
import '../../../data/models/empleado_model.dart';
import '../../../services/sync_service.dart';
import '../../../services/connectivity_service.dart';

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
  String _selectedTipo = 'TODOS';
  String _selectedSyncState = 'TODOS';
  bool _loading = true;
  bool _syncing = false;
  
  // Rastrear operaciones de sincronización individual por ID de registro
  final Map<String, bool> _syncingRows = {};
  


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

      // 2. Cargar todos los registros de forma compatible tanto nativo como Web
      final listAll = await _db.getAllRegistros();
      listAll.sort((a, b) => b.fechaHora.compareTo(a.fechaHora));

      setState(() {
        _allRegistros = listAll;
      });
      _onFilterChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar historial: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  void _onFilterChanged() {
    final query = _searchCtrl.text.toLowerCase().trim();
    
    // 1. Filtrar registros planos primero
    final filtered = _allRegistros.where((reg) {
      final empleado = _empleadosMap[reg.cedula];
      final matchQuery = query.isEmpty ||
          reg.cedula.toLowerCase().contains(query) ||
          (empleado != null && empleado.nombre.toLowerCase().contains(query));

      final matchDate = _selectedDate == null ||
          reg.fechaHora.startsWith(DateFormat('yyyy-MM-dd').format(_selectedDate!));

      final matchTipo = _selectedTipo == 'TODOS' ||
          reg.tipo.toUpperCase() == _selectedTipo;

      final matchSync = _selectedSyncState == 'TODOS' ||
          (_selectedSyncState == 'ENVIADO' && reg.sincronizado) ||
          (_selectedSyncState == 'PENDIENTE' && !reg.sincronizado);

      return matchQuery && matchDate && matchTipo && matchSync;
    }).toList();

    setState(() {
      _filteredRegistros = filtered;
    });
  }

  bool get _hasActiveFilters =>
      _searchCtrl.text.isNotEmpty ||
      _selectedDate != null ||
      _selectedTipo != 'TODOS' ||
      _selectedSyncState != 'TODOS';

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

  Future<void> _syncSingleRegistro(RegistroModel reg) async {
    if (reg.id == null || _syncingRows[reg.id!] == true) return;

    setState(() => _syncingRows[reg.id!] = true);

    try {
      final connected = await ConnectivityService().isConnected();
      if (!connected) {
        throw Exception('Sin conexión a internet');
      }

      final baseUrl = await _db.getConfig(DbConstants.cfgUrlApi) ?? ApiConstants.defaultBaseUrl;
      final uri = Uri.parse('$baseUrl${ApiConstants.syncRegistros}');
      final body = jsonEncode([reg.toMap()]);

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(milliseconds: ApiConstants.receiveTimeoutMs));

      if (response.statusCode == 200 || response.statusCode == 201) {
        await _db.marcarRegistrosSincronizados([reg.id!]);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Registro sincronizado exitosamente con el servidor.'),
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
            content: Text('Fallo al sincronizar registro: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _syncingRows[reg.id!] = false);
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

  void _showDetailsDialog(RegistroModel reg) {
    final empleado = _empleadosMap[reg.cedula];
    final typeColor = _getTipoColor(reg.tipo);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.assignment_ind_rounded, color: AppColors.primary),
              SizedBox(width: 8),
              Text('Detalle de Marcación'),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDetailRow('ID de Registro', reg.id ?? 'N/A'),
                  _buildDetailRow('Empleado', empleado?.nombre ?? 'Empleado Desconocido'),
                  _buildDetailRow('Cédula de Identidad', reg.cedula),
                  _buildDetailRow('Evento Detectado', reg.evento.toUpperCase()),
                  _buildDetailRow('Fecha y Hora Local', _formatDateTime(reg.fechaHora)),
                  _buildDetailRow('Tipo de Jornada', reg.tipo.toUpperCase(), valueColor: typeColor),
                  _buildDetailRow('Duración de Evento', reg.duracion ?? 'N/A'),
                  _buildDetailRow('Unidad de Negocio / Dispositivo', reg.unidadNegocio),
                  _buildDetailRow(
                    'Estado de Sincronización',
                    reg.sincronizado ? 'Sincronizado con Servidor Central' : 'Pendiente de Envío Local',
                    valueColor: reg.sincronizado ? AppColors.success : AppColors.warning,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: valueColor != null ? FontWeight.bold : FontWeight.normal,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
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
        labelText: 'Buscar empleado o cédula',
        hintText: 'Ingresa nombre o cédula...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchCtrl.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchCtrl.clear();
                  _onFilterChanged();
                },
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      onChanged: (_) => _onFilterChanged(),
    );
  }

  Widget _buildDatePickerButton() {
    final active = _selectedDate != null;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _selectDate,
            icon: Icon(
              active ? Icons.calendar_today : Icons.calendar_today_outlined,
              size: 18,
              color: active ? AppColors.primary : null,
            ),
            label: Text(
              active
                  ? DateFormat('dd/MM/yyyy').format(_selectedDate!)
                  : 'Filtrar por Fecha',
              style: TextStyle(
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                color: active ? AppColors.primary : null,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              side: BorderSide(
                color: active ? AppColors.primary : Theme.of(context).dividerColor,
                width: active ? 1.8 : 1.0,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        if (active) ...[
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.filter_alt_off_outlined, color: AppColors.error),
            tooltip: 'Limpiar filtro de fecha',
            onPressed: _clearDateFilter,
          ),
        ],
      ],
    );
  }

  Widget _buildTipoDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedTipo,
      decoration: InputDecoration(
        labelText: 'Tipo de Asistencia',
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
          _onFilterChanged();
        }
      },
      items: <String>[
        'TODOS',
        'NORMAL',
        'RETARDO',
        'ALMUERZO',
        'SALIDA',
        'PERMISO',
        'EXTRAS'
      ].map<DropdownMenuItem<String>>((String value) {
        return DropdownMenuItem<String>(
          value: value,
          child: Text(value),
        );
      }).toList(),
    );
  }

  Widget _buildSyncDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedSyncState,
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
        fontWeight: _selectedSyncState != 'TODOS' ? FontWeight.bold : FontWeight.normal,
      ),
      onChanged: (String? newValue) {
        if (newValue != null) {
          setState(() => _selectedSyncState = newValue);
          _onFilterChanged();
        }
      },
      items: <String>[
        'TODOS',
        'ENVIADO',
        'PENDIENTE'
      ].map<DropdownMenuItem<String>>((String value) {
        return DropdownMenuItem<String>(
          value: value,
          child: Text(value == 'TODOS' ? 'TODOS' : (value == 'ENVIADO' ? 'Enviados' : 'Pendientes')),
        );
      }).toList(),
    );
  }

  Widget _buildClearFiltersButton() {
    return OutlinedButton.icon(
      onPressed: () {
        _searchCtrl.clear();
        setState(() {
          _selectedDate = null;
          _selectedTipo = 'TODOS';
          _selectedSyncState = 'TODOS';
        });
        _onFilterChanged();
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
              'Evento',
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
              'Fecha y Hora',
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
              'Dispositivo',
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

  Widget _buildRow(RegistroModel reg, int index) {
    final empleado = _empleadosMap[reg.cedula];
    final typeColor = _getTipoColor(reg.tipo);
    final isEven = index % 2 == 0;
    final rowColor = isEven ? Colors.white : Colors.grey.shade50;

    final isEntrada = reg.evento == AppConstants.eventoEntrada;
    final eventoColor = isEntrada ? AppColors.success : AppColors.error;
    final eventoBg = isEntrada ? AppColors.successLight : AppColors.errorLight;
    final eventoText = isEntrada ? 'ENTRADA' : 'SALIDA';
    final eventoIcon = isEntrada ? Icons.login_rounded : Icons.logout_rounded;

    final colorSync = reg.sincronizado ? AppColors.success : AppColors.warning;
    final bgSync = reg.sincronizado ? AppColors.successLight : AppColors.warningLight;
    final textSync = reg.sincronizado ? 'ENVIADO' : 'PENDIENTE';
    final iconSync = reg.sincronizado ? Icons.cloud_done_rounded : Icons.cloud_off_rounded;

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
              reg.cedula,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),

          // Colaborador
          Expanded(
            flex: 3,
            child: Text(
              empleado?.nombre ?? 'Empleado Desconocido',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Evento
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: eventoBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: eventoColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(eventoIcon, color: eventoColor, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      eventoText,
                      style: TextStyle(
                        color: eventoColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Fecha y Hora
          Expanded(
            flex: 3,
            child: Text(
              _formatDateTime(reg.fechaHora),
              style: const TextStyle(fontSize: 13),
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
                  color: typeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: typeColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  reg.tipo.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: typeColor,
                  ),
                ),
              ),
            ),
          ),

          // Dispositivo
          Expanded(
            flex: 2,
            child: Text(
              reg.unidadNegocio,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
                // Ver Detalles
                IconButton(
                  icon: const Icon(Icons.info_outline_rounded, color: AppColors.textSecondary, size: 18),
                  tooltip: 'Ver Detalles',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _showDetailsDialog(reg),
                ),
                const SizedBox(width: 8),

                // Sincronizar individual (Solo si no está sincronizado)
                if (!reg.sincronizado) ...[
                  _syncingRows[reg.id] == true
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        )
                      : IconButton(
                          icon: const Icon(Icons.cloud_upload_rounded, color: AppColors.primary, size: 18),
                          tooltip: 'Sincronizar ahora',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _syncSingleRegistro(reg),
                        ),
                ] else ...[
                  const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListArea(bool isWide) {
    if (_filteredRegistros.isEmpty) {
      return _buildEmptyState();
    }

    return Container(
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
              itemCount: _filteredRegistros.length,
              itemBuilder: (context, index) {
                final reg = _filteredRegistros[index];
                return _buildRow(reg, index);
              },
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
            const Icon(Icons.history_toggle_off, size: 64, color: AppColors.textDisabled),
            const SizedBox(height: 16),
            Text(
              _allRegistros.isEmpty
                  ? 'No hay registros de asistencia guardados localmente.'
                  : 'Ninguna marcación coincide con los filtros aplicados.',
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

    // Adaptar espaciados según el ancho de pantalla
    final pagePadding = isWide ? const EdgeInsets.all(24) : const EdgeInsets.all(12);
    final statsAspectRatio = width > 600 ? 2.8 : (width > 420 ? 2.3 : 1.9);
    
    // Calcular estadísticas de la vista actual
    final totalFiltered = _filteredRegistros.length;
    final totalAll = _allRegistros.length;
    final totalSynced = _filteredRegistros.where((r) => r.sincronizado).length;
    final totalPending = _filteredRegistros.where((r) => !r.sincronizado).length;
    final totalLate = _filteredRegistros.where((r) => r.tipo.toUpperCase() == 'RETARDO').length;

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
            tooltip: 'Sincronización Bidireccional Completa',
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
                  // 1. Dashboard de Métricas Clave (Fila de Estadísticas)
                  if (isWide)
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            title: 'Marcaciones en Vista',
                            value: '$totalFiltered / $totalAll',
                            icon: Icons.assessment_rounded,
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
                            title: 'Retardos / Demoras',
                            value: '$totalLate',
                            icon: Icons.warning_amber_rounded,
                            color: AppColors.error,
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
                          title: 'Marcaciones',
                          value: '$totalFiltered / $totalAll',
                          icon: Icons.assessment_rounded,
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
                          title: 'Retardos',
                          value: '$totalLate',
                          icon: Icons.warning_amber_rounded,
                          color: AppColors.error,
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
                                Expanded(flex: 2, child: _buildDatePickerButton()),
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
                                    Expanded(child: _buildDatePickerButton()),
                                    const SizedBox(width: 10),
                                    Expanded(child: _buildTipoDropdown()),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(child: _buildSyncDropdown()),
                                    if (_hasActiveFilters) ...[
                                      const SizedBox(width: 10),
                                      _buildClearFiltersButton(),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 3. Grid / Tabla de Datos (Desktop) o Lista de Tarjetas (Mobile)
                  Expanded(
                    child: _buildListArea(isWide),
                  ),
                ],
              ),
            ),
    );
  }
}

