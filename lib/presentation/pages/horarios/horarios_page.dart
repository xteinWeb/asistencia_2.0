import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/routes/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/local/database_helper.dart';
import '../../../data/models/horario_model.dart';
import '../../../services/sync_service.dart';

class HorariosPage extends StatefulWidget {
  const HorariosPage({super.key});

  @override
  State<HorariosPage> createState() => _HorariosPageState();
}

class _HorariosPageState extends State<HorariosPage> {
  final _db = DatabaseHelper();
  
  List<HorarioModel> _horarios = [];
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
        _loadHorarios();
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
    _loadHorarios();
  }

  Future<void> _loadHorarios() async {
    setState(() => _loading = true);
    try {
      final list = await _db.getAllHorarios();
      setState(() {
        _horarios = list;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar horarios: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _deleteHorario(String id, String tipo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: Text('¿Está seguro de que desea eliminar este horario de tipo $tipo?\nAsegúrese de que ningún empleado esté usando este horario.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _db.deleteHorario(id);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Horario eliminado con éxito'), backgroundColor: AppColors.success),
        );
        _loadHorarios();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar horario: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _showAddHorarioDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _AddHorarioDialog(),
    ).then((value) {
      if (value == true) {
        _loadHorarios();
      }
    });
  }

  Color _getTipoColor(String tipo) {
    switch (tipo.toUpperCase()) {
      case 'LABORAL':
        return AppColors.primary;
      case 'ALMUERZO':
        return AppColors.colorAlmuerzo;
      case 'DESCANSO':
        return AppColors.colorSalida;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Horarios'),
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
          : _horarios.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.schedule, size: 64, color: AppColors.textDisabled),
                      const SizedBox(height: 16),
                      const Text(
                        'No hay horarios registrados en el sistema',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _showAddHorarioDialog,
                        icon: const Icon(Icons.add),
                        label: const Text('Crear Primer Horario'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _horarios.length,
                  itemBuilder: (context, index) {
                    final h = _horarios[index];
                    final color = _getTipoColor(h.tipo);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            // Icono del tipo de horario
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                h.tipo.toUpperCase() == 'LABORAL'
                                    ? Icons.work_outline
                                    : h.tipo.toUpperCase() == 'ALMUERZO'
                                        ? Icons.restaurant_menu
                                        : Icons.coffee,
                                color: color,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 16),

                            // Detalles del horario
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        h.tipo.toUpperCase(),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: color,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Horas: ${h.horaInicio} - ${h.horaFinal}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: h.diasList.map((d) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.border.withValues(alpha: 0.5),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          d,
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),

                            // Botón de eliminar
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppColors.error),
                              tooltip: 'Eliminar Horario',
                              onPressed: () => _deleteHorario(h.idHorario!, h.tipo),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: _horarios.isNotEmpty
          ? FloatingActionButton(
              onPressed: _showAddHorarioDialog,
              tooltip: 'Crear nuevo horario',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class _AddHorarioDialog extends StatefulWidget {
  const _AddHorarioDialog();

  @override
  State<_AddHorarioDialog> createState() => _AddHorarioDialogState();
}

class _AddHorarioDialogState extends State<_AddHorarioDialog> {
  final _formKey = GlobalKey<FormState>();
  final _db = DatabaseHelper();

  String _tipo = 'LABORAL';
  TimeOfDay _horaInicio = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _horaFinal = const TimeOfDay(hour: 17, minute: 0);
  
  final List<String> _diasDisponibles = ['L', 'M', 'Mi', 'J', 'V', 'S', 'D'];
  final Set<String> _diasSeleccionados = {'L', 'M', 'Mi', 'J', 'V'};
  bool _saving = false;

  Color _getTipoColor(String tipo) {
    switch (tipo.toUpperCase()) {
      case 'LABORAL':
        return AppColors.primary;
      case 'ALMUERZO':
        return AppColors.colorAlmuerzo;
      case 'DESCANSO':
        return AppColors.colorSalida;
      default:
        return AppColors.textSecondary;
    }
  }

  Future<void> _selectTime(bool esInicio) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: esInicio ? _horaInicio : _horaFinal,
    );
    if (picked != null) {
      setState(() {
        if (esInicio) {
          _horaInicio = picked;
        } else {
          _horaFinal = picked;
        }
      });
    }
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_diasSeleccionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione al menos un día de la semana'), backgroundColor: AppColors.warning),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      // Unir los días seleccionados manteniendo el orden
      final diasListOrdered = _diasDisponibles.where((d) => _diasSeleccionados.contains(d)).join(',');

      final horario = HorarioModel(
        tipo: _tipo,
        horaInicio: _formatTimeOfDay(_horaInicio),
        horaFinal: _formatTimeOfDay(_horaFinal),
        dias: diasListOrdered,
      );

      await _db.insertHorario(horario);
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar horario: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo Horario'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tipo de Horario
              DropdownButtonFormField<String>(
                value: _tipo,
                decoration: const InputDecoration(labelText: 'Tipo de Horario'),
                items: const [
                  DropdownMenuItem(value: 'LABORAL', child: Text('Laboral')),
                  DropdownMenuItem(value: 'ALMUERZO', child: Text('Almuerzo')),
                  DropdownMenuItem(value: 'DESCANSO', child: Text('Descanso')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _tipo = val);
                },
              ),
              const SizedBox(height: 16),

              // Hora Inicio y Hora Fin
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _selectTime(true),
                      icon: const Icon(Icons.access_time, size: 18),
                      label: Text('Inicio: ${_formatTimeOfDay(_horaInicio)}'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _selectTime(false),
                      icon: const Icon(Icons.access_time, size: 18),
                      label: Text('Fin: ${_formatTimeOfDay(_horaFinal)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Días de la semana
              Text(
                'Días Laborales',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _diasDisponibles.map((dia) {
                  final isSelected = _diasSeleccionados.contains(dia);
                  return FilterChip(
                    label: Text(dia),
                    selected: isSelected,
                    selectedColor: _getTipoColor(_tipo).withValues(alpha: 0.2),
                    checkmarkColor: _getTipoColor(_tipo),
                    labelStyle: TextStyle(
                      color: isSelected ? _getTipoColor(_tipo) : Theme.of(context).colorScheme.onSurface,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _diasSeleccionados.add(dia);
                        } else {
                          _diasSeleccionados.remove(dia);
                        }
                      });
                    },
                  );
                }).toList(),
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
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Crear Horario'),
        ),
      ],
    );
  }
}
