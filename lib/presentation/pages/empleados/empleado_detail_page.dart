import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/routes/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/local/database_helper.dart';
import '../../../data/models/empleado_model.dart';
import '../../../data/models/horario_model.dart';
import '../../../data/models/registro_model.dart';
import '../../../services/sync_service.dart';

class EmpleadoDetailPage extends StatefulWidget {
  final String cedula;
  const EmpleadoDetailPage({super.key, required this.cedula});

  @override
  State<EmpleadoDetailPage> createState() => _EmpleadoDetailPageState();
}

class _EmpleadoDetailPageState extends State<EmpleadoDetailPage> {
  final _db = DatabaseHelper();

  EmpleadoModel? _empleado;
  HorarioModel? _horario;
  List<RegistroModel> _registros = [];
  bool _loading = true;
  String? _seccionDescripcion;

  // Variables para el modo de edición
  bool _isEditing = false;
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _fechaIniCtrl = TextEditingController();
  final _fechaFinCtrl = TextEditingController();
  String? _selectedHorarioId;
  String? _selectedTipo;
  String? _selectedSeccionId;

  List<HorarioModel> _allHorarios = [];
  List<Map<String, dynamic>> _allSecciones = [];

  @override
  void initState() {
    super.initState();
    _loadEmpleadoData();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _fechaIniCtrl.dispose();
    _fechaFinCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEmpleadoData() async {
    setState(() => _loading = true);
    try {
      final emp = await _db.getEmpleadoByCedula(widget.cedula);
      if (emp != null) {
        _empleado = emp;
        if (emp.horarioId != null) {
          final h = await _db.getHorarioById(emp.horarioId!);
          if (h != null) _horario = h;
        }
        if (emp.idSeccion != null) {
          _seccionDescripcion = await _db.getSeccionDescripcion(emp.idSeccion!);
        }
        _registros = await _db.getRegistrosPorCedula(widget.cedula);

        // Cargar listas completas para la edición
        _allHorarios = await _db.getAllHorarios();
        _allSecciones = await _db.getSecciones();

        // Inicializar controladores con la información actual
        _nombreCtrl.text = emp.nombre;
        _fechaIniCtrl.text = emp.fechaIniContrato ?? '';
        _fechaFinCtrl.text = emp.fechaFinContrato ?? '';
        _selectedHorarioId = emp.horarioId;
        _selectedTipo = emp.tipo ?? 'OPERATIVO';
        _selectedSeccionId = emp.idSeccion;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar datos: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveEmployeeChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final updated = _empleado!.copyWith(
        nombre: _nombreCtrl.text.trim(),
        horarioId: _selectedHorarioId,
        fechaIniContrato: _fechaIniCtrl.text.trim().isNotEmpty
            ? _fechaIniCtrl.text.trim()
            : null,
        fechaFinContrato: _fechaFinCtrl.text.trim().isNotEmpty
            ? _fechaFinCtrl.text.trim()
            : null,
        idSeccion: _selectedTipo == 'OPERATIVO' ? _selectedSeccionId : null,
        tipo: _selectedTipo,
        sincronizado: false,
      );

      final success = await _db.updateEmpleado(updated);
      if (success > 0) {
        if (!kIsWeb) {
          final syncService = Provider.of<SyncService>(context, listen: false);
          syncService.syncAll();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Colaborador actualizado con éxito'),
            backgroundColor: AppColors.success,
          ),
        );
        setState(() {
          _empleado = updated;
          _isEditing = false;
        });
        await _loadEmpleadoData();
      } else {
        throw Exception('No se pudo actualizar en la base de datos');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al actualizar colaborador: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      setState(() => _loading = false);
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

  Color _getTipoRegistroColor(String tipo) {
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
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detalle de Empleado')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_empleado == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detalle de Empleado')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: AppColors.error),
              const SizedBox(height: 16),
              const Text(
                'Empleado no encontrado',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => context.go(AppRoutes.empleados),
                child: const Text('Volver a la lista'),
              ),
            ],
          ),
        ),
      );
    }

    final tieneVector = _empleado!.mapaVectorFoto.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar Colaborador' : _empleado!.nombre),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_isEditing) {
              setState(() => _isEditing = false);
            } else {
              context.go(AppRoutes.empleados);
            }
          },
        ),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar Colaborador',
              onPressed: () {
                setState(() {
                  _isEditing = true;
                  _nombreCtrl.text = _empleado!.nombre;
                  _fechaIniCtrl.text = _empleado!.fechaIniContrato ?? '';
                  _fechaFinCtrl.text = _empleado!.fechaFinContrato ?? '';
                  _selectedHorarioId = _empleado!.horarioId;
                  _selectedTipo = _empleado!.tipo ?? 'OPERATIVO';
                  _selectedSeccionId = _empleado!.idSeccion;
                });
              },
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.check_rounded, color: Colors.white),
              tooltip: 'Guardar Cambios',
              onPressed: _saveEmployeeChanges,
            ),

            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              tooltip: 'Cancelar',
              onPressed: () => setState(() => _isEditing = false),
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ficha principal del empleado
            if (_isEditing)
              Form(
                key: _formKey,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Cédula y Avatar (Solo lectura)
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 36,
                              backgroundColor: tieneVector
                                  ? AppColors.success.withValues(alpha: 0.1)
                                  : AppColors.warning.withValues(alpha: 0.1),
                              child: Icon(
                                tieneVector
                                    ? Icons.face
                                    : Icons.face_retouching_off,
                                color: tieneVector
                                    ? AppColors.success
                                    : AppColors.warning,
                                size: 38,
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Cédula (No editable)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _empleado!.cedula,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 32),

                        // Nombre
                        TextFormField(
                          controller: _nombreCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Nombre Completo',
                            prefixIcon: Icon(Icons.person),
                            border: OutlineInputBorder(),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'El nombre es requerido';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Horario
                        DropdownButtonFormField<String>(
                          value:
                              _allHorarios.any(
                                (h) => h.idHorario == _selectedHorarioId,
                              )
                              ? _selectedHorarioId
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'Horario Asignado',
                            prefixIcon: Icon(Icons.schedule),
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Sin horario asignado'),
                            ),
                            ..._allHorarios.map((h) {
                              return DropdownMenuItem<String>(
                                value: h.idHorario,
                                child: Text('${h.descripcion}'),
                              );
                            }),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _selectedHorarioId = val;
                            });
                          },
                        ),
                        const SizedBox(height: 16),

                        // Tipo
                        DropdownButtonFormField<String>(
                          value: _selectedTipo,
                          decoration: const InputDecoration(
                            labelText: 'Tipo de Empleado',
                            prefixIcon: Icon(Icons.badge_outlined),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem<String>(
                              value: 'OPERATIVO',
                              child: Text('OPERATIVO'),
                            ),
                            DropdownMenuItem<String>(
                              value: 'ADMINISTRATIVO',
                              child: Text('ADMINISTRATIVO'),
                            ),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _selectedTipo = val;
                              if (val == 'ADMINISTRATIVO') {
                                _selectedSeccionId = null;
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 16),

                        // Sección (Solo si es OPERATIVO)
                        if (_selectedTipo == 'OPERATIVO') ...[
                          DropdownButtonFormField<String>(
                            value:
                                _allSecciones.any(
                                  (s) => s['id_seccion'] == _selectedSeccionId,
                                )
                                ? _selectedSeccionId
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Sección Asignada',
                              prefixIcon: Icon(Icons.view_quilt_outlined),
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem<String>(
                                value: null,
                                child: Text('Sin sección asignada'),
                              ),
                              ..._allSecciones.map((s) {
                                return DropdownMenuItem<String>(
                                  value: s['id_seccion'] as String?,
                                  child: Text(s['descripcion'] as String),
                                );
                              }),
                            ],
                            onChanged: (val) {
                              setState(() {
                                _selectedSeccionId = val;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Inicio Contrato
                        TextFormField(
                          controller: _fechaIniCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Inicio de Contrato',
                            prefixIcon: Icon(Icons.calendar_today),
                            border: OutlineInputBorder(),
                            hintText: 'yyyy-MM-dd',
                          ),
                          readOnly: true,
                          onTap: () async {
                            final initial =
                                DateTime.tryParse(_fechaIniCtrl.text) ??
                                DateTime.now();
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: initial,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              _fechaIniCtrl.text = DateFormat(
                                'yyyy-MM-dd',
                              ).format(picked);
                            }
                          },
                        ),
                        const SizedBox(height: 16),

                        // Fin Contrato
                        TextFormField(
                          controller: _fechaFinCtrl,
                          decoration: InputDecoration(
                            labelText: 'Fin de Contrato (Opcional)',
                            prefixIcon: const Icon(Icons.calendar_month),
                            border: const OutlineInputBorder(),
                            hintText: 'Indefinido',
                            suffixIcon: _fechaFinCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      setState(() {
                                        _fechaFinCtrl.clear();
                                      });
                                    },
                                  )
                                : null,
                          ),
                          readOnly: true,
                          onTap: () async {
                            final initial =
                                DateTime.tryParse(_fechaFinCtrl.text) ??
                                DateTime.now();
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: initial,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              _fechaFinCtrl.text = DateFormat(
                                'yyyy-MM-dd',
                              ).format(picked);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 36,
                            backgroundColor: tieneVector
                                ? AppColors.success.withValues(alpha: 0.1)
                                : AppColors.warning.withValues(alpha: 0.1),
                            child: Icon(
                              tieneVector
                                  ? Icons.face
                                  : Icons.face_retouching_off,
                              color: tieneVector
                                  ? AppColors.success
                                  : AppColors.warning,
                              size: 38,
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _empleado!.nombre,
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Cédula: ${_empleado!.cedula}',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 32),

                      // Datos de contrato y horario
                      _InfoRow(
                        icon: Icons.schedule,
                        label: 'Horario Asignado',
                        value: _horario != null
                            ? '${_horario!.descripcion}'
                            : 'Sin horario asignado',
                      ),
                      const SizedBox(height: 12),
                      _InfoRow(
                        icon: Icons.badge_outlined,
                        label: 'Tipo de Empleado',
                        value: _empleado!.tipo ?? 'No especificado',
                      ),

                      if (_empleado!.tipo == 'OPERATIVO' ||
                          _empleado!.tipo == null) ...[
                        const SizedBox(height: 12),
                        _InfoRow(
                          icon: Icons.view_quilt_outlined,
                          label: 'Sección asignada',
                          value:
                              _seccionDescripcion ??
                              _empleado!.idSeccion ??
                              'Sin sección asignada',
                        ),
                      ],
                      const SizedBox(height: 12),
                      _InfoRow(
                        icon: Icons.calendar_today,
                        label: 'Inicio de Contrato',
                        value: _empleado!.fechaIniContrato ?? 'No registrada',
                      ),
                      const SizedBox(height: 12),
                      _InfoRow(
                        icon: Icons.calendar_month,
                        label: 'Fin de Contrato',
                        value: _empleado!.fechaFinContrato ?? 'Indefinido',
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),

            // Tarjeta de Enrolamiento Facial
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.fingerprint, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Datos Biométricos',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (tieneVector) ...[
                      Text(
                        'Vector facial de 128 dimensiones registrado. Listo para autenticación local en modo Tótem sin conexión a internet.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Visualización Premium de Sparkline del vector biométrico
                      Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(64, (index) {
                            // Muestra una barra proporcional a los valores del vector
                            final val = _empleado!.mapaVectorFoto[index * 2]
                                .abs();
                            final h = (val * 30).clamp(2.0, 32.0);
                            return Container(
                              width: 3,
                              height: h,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(1),
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Center(
                        child: Text(
                          'Representación gráfica de la firma facial única (64 de 128 puntos mostrados)',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textDisabled,
                          ),
                        ),
                      ),
                    ] else ...[
                      Text(
                        'Este empleado no tiene datos faciales enrolados en este dispositivo. Para que pueda marcar asistencia en el Tótem, debe registrar su rostro desde la opción de Editar o Registrar Nuevo Empleado.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Historial de asistencia del empleado
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'Registros de Asistencia Recientes',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),

            if (_registros.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(
                          Icons.history_toggle_off,
                          size: 48,
                          color: AppColors.textDisabled,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No hay registros de asistencia para este empleado hoy.',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _registros.length,
                itemBuilder: (context, index) {
                  final reg = _registros[index];
                  final color = _getTipoRegistroColor(reg.tipo);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          reg.evento == AppConstants.eventoEntrada
                              ? Icons.login
                              : Icons.logout,
                          color: color,
                        ),
                      ),
                      title: Text(
                        '${reg.evento} - ${reg.tipo.toUpperCase()}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(_formatDateTime(reg.fechaHora)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            reg.sincronizado
                                ? Icons.cloud_done
                                : Icons.cloud_off,
                            color: reg.sincronizado
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outline,
                            size: 20,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            reg.sincronizado ? 'Sincronizado' : 'Pendiente',
                            style: TextStyle(
                              fontSize: 11,
                              color: reg.sincronizado
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          size: 20,
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
