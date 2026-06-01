import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/routes/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/db_constants.dart';
import '../../../data/datasources/local/database_helper.dart';
import '../../../data/models/permiso_model.dart';
import '../../../data/models/empleado_model.dart';
import '../../../services/sync_service.dart';

class PermisosPage extends StatefulWidget {
  const PermisosPage({super.key});

  @override
  State<PermisosPage> createState() => _PermisosPageState();
}

class _PermisosPageState extends State<PermisosPage> {
  final _db = DatabaseHelper();
  
  List<PermisoModel> _permisos = [];
  Map<String, EmpleadoModel> _empleadosMap = {};
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
        _loadPermisosData();
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
    _loadPermisosData();
  }

  Future<void> _loadPermisosData() async {
    setState(() => _loading = true);
    try {
      // 1. Cargar empleados para mapear nombres
      final empleados = await _db.getAllEmpleados();
      _empleadosMap = {
        for (var e in empleados) e.cedula: e
      };

      // 2. Cargar todos los permisos locales
      final dbInstance = await _db.database;
      final rows = await dbInstance.query(DbConstants.tablePermisos, orderBy: 'fecha_hora DESC');
      final list = rows.map(PermisoModel.fromMap).toList();

      setState(() {
        _permisos = list;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar permisos: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      setState(() => _loading = false);
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
        // Intentar sincronización inmediata en segundo plano
        if (mounted) {
          context.read<SyncService>().syncAll();
        }
      }
    });
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

  @override
  Widget build(BuildContext context) {
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
          : _permisos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.event_available, size: 64, color: AppColors.textDisabled),
                      const SizedBox(height: 16),
                      Text(
                        'No hay permisos registrados en el sistema',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _showAddPermisoDialog,
                        icon: const Icon(Icons.add),
                        label: const Text('Registrar Primer Permiso'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _permisos.length,
                  itemBuilder: (context, index) {
                    final p = _permisos[index];
                    final emp = _empleadosMap[p.cedulaEmpleado];
                    final color = _getPermisoColor(p.tipo);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            // Indicador visual
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.assignment_turned_in_outlined, color: color, size: 24),
                            ),
                            const SizedBox(width: 16),

                            // Detalles del permiso
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    emp?.nombre ?? 'Empleado Desconocido',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'CC: ${p.cedulaEmpleado}',
                                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: color.withValues(alpha: 0.3)),
                                        ),
                                        child: Text(
                                          p.tipo.replaceAll('_', ' ').toUpperCase(),
                                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Vence: ${_formatDateStr(p.fechaFinal)}',
                                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Desde: ${_formatDateStr(p.fechaInicio)} hasta ${_formatDateStr(p.fechaFinal)}',
                                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),

                            // Sincronización
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  p.sincronizado ? Icons.cloud_done : Icons.cloud_off,
                                  color: p.sincronizado ? AppColors.success : AppColors.textDisabled,
                                  size: 20,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  p.sincronizado ? 'Enviado' : 'Pendiente',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: p.sincronizado ? AppColors.success : Theme.of(context).colorScheme.onSurfaceVariant,
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
      floatingActionButton: _permisos.isNotEmpty
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar empleados: $e'), backgroundColor: AppColors.error),
      );
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
        usuarioRegistrador: 'admin', // Registrador por defecto
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar permiso: $e'), backgroundColor: AppColors.error),
      );
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
                value: _selectedCedula,
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
                value: _tipo,
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
