import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/routes/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/local/database_helper.dart';
import '../../../data/models/convocatoria_model.dart';
import '../../../data/models/convocatoria_empleado_model.dart';
import '../../../data/models/empleado_model.dart';

class ConvocatoriasPage extends StatefulWidget {
  const ConvocatoriasPage({super.key});

  @override
  State<ConvocatoriasPage> createState() => _ConvocatoriasPageState();
}

class _ConvocatoriasPageState extends State<ConvocatoriasPage> {
  final _db = DatabaseHelper();
  List<ConvocatoriaModel> _convocatorias = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadConvocatorias();
  }

  Future<void> _loadConvocatorias() async {
    setState(() => _loading = true);
    try {
      final list = await _db.getAllConvocatorias();
      setState(() => _convocatorias = list);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar convocatorias: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _eliminarConvocatoria(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Convocatoria'),
        content: const Text(
          '¿Estás seguro de que deseas eliminar esta convocatoria y sus asignaciones?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _db.deleteConvocatoria(id);
        _loadConvocatorias();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Convocatoria eliminada con éxito.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al eliminar: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Convocatorias (Tiempo Extra)'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.home),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadConvocatorias,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _convocatorias.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.assignment_ind_outlined,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No hay convocatorias programadas.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _convocatorias.length,
              itemBuilder: (context, index) {
                final c = _convocatorias[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.primary,
                      child: Icon(Icons.event, color: Colors.white),
                    ),
                    title: Text(
                      c.descripcion,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text('Fecha: ${c.fecha}'),
                        Text('Horario: ${c.horaInicio} - ${c.horaFinal}'),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _eliminarConvocatoria(c.id),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ConvocatoriaDetallePage(convocatoria: c),
                      ),
                    ).then((_) => _loadConvocatorias()),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const NuevaConvocatoriaPage(),
          ),
        ).then((_) => _loadConvocatorias()),
      ),
    );
  }
}

class NuevaConvocatoriaPage extends StatefulWidget {
  const NuevaConvocatoriaPage({super.key});

  @override
  State<NuevaConvocatoriaPage> createState() => _NuevaConvocatoriaPageState();
}

class _NuevaConvocatoriaPageState extends State<NuevaConvocatoriaPage> {
  final _formKey = GlobalKey<FormState>();
  final _db = DatabaseHelper();
  final _descController = TextEditingController();

  DateTime? _selectedDate;
  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 12, minute: 0);

  List<EmpleadoModel> _empleados = [];
  List<Map<String, dynamic>> _secciones = [];
  final Set<String> _empleadosSeleccionados = {};
  final Map<String, String> _erroresTraslape = {};

  String _filtroNombre = '';
  String? _seccionSeleccionada;

  bool _loadingEmpleados = false;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _loadEmpleados();
  }

  Future<void> _loadEmpleados() async {
    setState(() => _loadingEmpleados = true);
    try {
      final list = await _db.getAllEmpleados();
      final seccList = await _db.getSecciones();
      setState(() {
        _empleados = list.where((e) => e.estado == 'ACTIVO').toList();
        _secciones = seccList;
      });
      _validarTraslapesTodos();
    } catch (_) {}
    setState(() => _loadingEmpleados = false);
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
      _validarTraslapesTodos();
    }
  }

  Future<void> _selectTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
      _validarTraslapesTodos();
    }
  }

  String _formatTimeOfDay(TimeOfDay tod) {
    final h = tod.hour.toString().padLeft(2, '0');
    final m = tod.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _validarTraslapesTodos() async {
    if (_selectedDate == null) return;
    _erroresTraslape.clear();
    final fechaStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
    final startStr = _formatTimeOfDay(_startTime);
    final endStr = _formatTimeOfDay(_endTime);

    for (final emp in _empleados) {
      final err = await _validarTraslape(emp, fechaStr, startStr, endStr);
      if (err != null) {
        setState(() {
          _erroresTraslape[emp.cedula] = err;
          // Deseleccionar si tiene traslape
          _empleadosSeleccionados.remove(emp.cedula);
        });
      }
    }
    setState(() {});
  }

  Future<String?> _validarTraslape(
    EmpleadoModel empleado,
    String fechaStr,
    String startStr,
    String endStr,
  ) async {
    if (empleado.horarioId == null || empleado.horarioId!.isEmpty) return null;
    final horario = await _db.getHorarioById(empleado.horarioId!);
    if (horario == null || horario.items.isEmpty) return null;

    final date = DateTime.tryParse(fechaStr);
    if (date == null) return null;

    final weekday = date.weekday;
    final itemsHoy = horario.items.where((item) {
      switch (weekday) {
        case DateTime.monday:
          return item.lunes;
        case DateTime.tuesday:
          return item.martes;
        case DateTime.wednesday:
          return item.miercoles;
        case DateTime.thursday:
          return item.jueves;
        case DateTime.friday:
          return item.viernes;
        case DateTime.saturday:
          return item.sabado;
        case DateTime.sunday:
          return item.domingo;
        default:
          return false;
      }
    }).toList();

    if (itemsHoy.isEmpty) return null;

    int toMinutes(String hhmm) {
      final parts = hhmm.split(':');
      if (parts.length < 2) return 0;
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      return h * 60 + m;
    }

    final convStart = toMinutes(startStr);
    final convEnd = toMinutes(endStr);

    for (final item in itemsHoy) {
      final shiftStart = toMinutes(item.inicio);
      final shiftEnd = toMinutes(item.finalTime);

      // Traslape de rangos horarios: [convStart, convEnd] vs [shiftStart, shiftEnd]
      if (convStart < shiftEnd && convEnd > shiftStart) {
        return 'Jornada laboral ordinaria asignada hoy de ${item.inicio} a ${item.finalTime}.';
      }
    }

    return null;
  }

  Future<void> _guardar() async {
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, selecciona una fecha primero.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_empleadosSeleccionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Selecciona al menos un empleado para la convocatoria.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _guardando = true);

    try {
      final fechaStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      final startStr = _formatTimeOfDay(_startTime);
      final endStr = _formatTimeOfDay(_endTime);
      final cId = const Uuid().v4();

      final convocatoria = ConvocatoriaModel(
        id: cId,
        fecha: fechaStr,
        horaInicio: startStr,
        horaFinal: endStr,
        descripcion: _descController.text.trim(),
      );

      await _db.insertConvocatoria(convocatoria);

      for (final cedula in _empleadosSeleccionados) {
        final convocado = ConvocatoriaEmpleadoModel(
          convocatoriaId: cId,
          cedulaEmpleado: cedula,
          asistio: false,
        );
        await _db.insertConvocado(convocado);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Convocatoria creada y personal asignado con éxito.'),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fechaStr = _selectedDate == null
        ? 'No seleccionada'
        : DateFormat('dd/MM/yyyy').format(_selectedDate!);

    // Filtrar los empleados según nombre y sección seleccionada
    final filteredEmpleados = _empleados.where((emp) {
      final matchesNombre =
          emp.nombre.toLowerCase().contains(_filtroNombre.toLowerCase()) ||
          emp.cedula.contains(_filtroNombre);
      final matchesSeccion =
          _seccionSeleccionada == null || emp.idSeccion == _seccionSeleccionada;
      return matchesNombre && matchesSeccion;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Nueva Convocatoria')),
      body: _guardando
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _descController,
                    decoration: const InputDecoration(
                      labelText: 'Descripción / Motivo',
                      hintText:
                          'Ej. Inventario general, Mantenimiento extra, etc.',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Ingresa la descripción'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.calendar_today),
                            title: const Text('Fecha de Convocatoria'),
                            subtitle: Text(fechaStr),
                            trailing: TextButton(
                              onPressed: _selectDate,
                              child: const Text('Cambiar'),
                            ),
                          ),
                          const Divider(),
                          ListTile(
                            leading: const Icon(Icons.access_time),
                            title: const Text('Hora Inicio'),
                            subtitle: Text(_formatTimeOfDay(_startTime)),
                            trailing: TextButton(
                              onPressed: () => _selectTime(true),
                              child: const Text('Cambiar'),
                            ),
                          ),
                          ListTile(
                            leading: const Icon(Icons.access_time_filled),
                            title: const Text('Hora Fin'),
                            subtitle: Text(_formatTimeOfDay(_endTime)),
                            trailing: TextButton(
                              onPressed: () => _selectTime(false),
                              child: const Text('Cambiar'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Asignar Personal Convocado:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),

                  if (_selectedDate == null)
                    Card(
                      color: Colors.amber.shade100,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.amber.shade900,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Por favor, selecciona una fecha primero para poder asignar personal y validar traslapes de horario.',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    // Filtros
                    Card(
                      color: Colors.grey.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            TextFormField(
                              decoration: const InputDecoration(
                                labelText: 'Buscar por Nombre o Cédula',
                                prefixIcon: Icon(Icons.search),
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              onChanged: (val) {
                                setState(() {
                                  _filtroNombre = val;
                                });
                              },
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: _seccionSeleccionada,
                              decoration: const InputDecoration(
                                labelText: 'Sección',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              hint: const Text('Todas las secciones'),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text('Todas las secciones'),
                                ),
                                ..._secciones.map((seccion) {
                                  return DropdownMenuItem<String>(
                                    value: seccion['id_seccion']?.toString(),
                                    child: Text(
                                      seccion['descripcion']?.toString() ?? '',
                                    ),
                                  );
                                }),
                              ],
                              onChanged: (val) {
                                setState(() {
                                  _seccionSeleccionada = val;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _loadingEmpleados
                        ? const Center(child: CircularProgressIndicator())
                        : filteredEmpleados.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: Text(
                                'No se encontraron empleados activos con los filtros aplicados.',
                                style: TextStyle(color: Colors.grey.shade600),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : Container(
                            constraints: const BoxConstraints(maxHeight: 380),
                            child: Scrollbar(
                              thumbVisibility: true,
                              child: ListView.builder(
                                itemCount: filteredEmpleados.length,
                                itemBuilder: (context, index) {
                                  final emp = filteredEmpleados[index];
                                  final err = _erroresTraslape[emp.cedula];
                                  final hasOverlap = err != null;

                                  return Card(
                                    color: hasOverlap
                                        ? Colors.red.shade50
                                        : null,
                                    child: CheckboxListTile(
                                      enabled: !hasOverlap,
                                      value: _empleadosSeleccionados.contains(
                                        emp.cedula,
                                      ),
                                      title: Text(emp.nombre),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('Cédula: ${emp.cedula}'),
                                          if (hasOverlap)
                                            Text(
                                              '⚠️ No disponible: $err',
                                              style: const TextStyle(
                                                color: Colors.red,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                        ],
                                      ),
                                      onChanged: (val) {
                                        setState(() {
                                          if (val == true) {
                                            _empleadosSeleccionados.add(
                                              emp.cedula,
                                            );
                                          } else {
                                            _empleadosSeleccionados.remove(
                                              emp.cedula,
                                            );
                                          }
                                        });
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: ElevatedButton(
            onPressed: (_guardando || _selectedDate == null) ? null : _guardar,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Programar Convocatoria',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}

class ConvocatoriaDetallePage extends StatefulWidget {
  final ConvocatoriaModel convocatoria;
  const ConvocatoriaDetallePage({super.key, required this.convocatoria});

  @override
  State<ConvocatoriaDetallePage> createState() =>
      _ConvocatoriaDetallePageState();
}

class _ConvocatoriaDetallePageState extends State<ConvocatoriaDetallePage> {
  final _db = DatabaseHelper();
  List<ConvocatoriaEmpleadoModel> _convocados = [];
  Map<String, String> _nombresEmpleados = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadConvocados();
  }

  Future<void> _loadConvocados() async {
    setState(() => _loading = true);
    try {
      final list = await _db.getConvocadosPorConvocatoria(
        widget.convocatoria.id,
      );
      final employees = await _db.getAllEmpleados();
      final Map<String, String> names = {};
      for (final e in employees) {
        names[e.cedula] = e.nombre;
      }
      setState(() {
        _convocados = list;
        _nombresEmpleados = names;
      });
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _toggleAsistenciaManual(
    ConvocatoriaEmpleadoModel c,
    bool checked,
  ) async {
    try {
      final timestamp = checked
          ? DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())
          : null;
      await _db.marcarAsistenciaConvocado(
        c.convocatoriaId,
        c.cedulaEmpleado,
        checked,
        timestamp,
      );
      _loadConvocados();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cambiar asistencia: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime? convDate;
    try {
      convDate = DateTime.parse(widget.convocatoria.fecha);
    } catch (_) {}
    final haPasado = convDate != null && convDate.isBefore(today);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de Convocatoria'),
        actions: [
          if (!haPasado)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Editar Convocatoria',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      EditarConvocatoriaPage(convocatoria: widget.convocatoria),
                ),
              ).then((_) => _loadConvocados()),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    color: Colors.deepPurple.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.convocatoria.descripcion,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.deepPurple,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Fecha: ${widget.convocatoria.fecha}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          Text(
                            'Horario: ${widget.convocatoria.horaInicio} - ${widget.convocatoria.horaFinal}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Asistencia de Convocados:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _convocados.isEmpty
                        ? const Center(
                            child: Text('No hay empleados convocados.'),
                          )
                        : ListView.builder(
                            itemCount: _convocados.length,
                            itemBuilder: (context, index) {
                              final c = _convocados[index];
                              final nombre =
                                  _nombresEmpleados[c.cedulaEmpleado] ??
                                  'Desconocido';

                              return Card(
                                child: CheckboxListTile(
                                  activeColor: Colors.deepPurple,
                                  title: Text(nombre),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Cédula: ${c.cedulaEmpleado}'),
                                      if (c.asistio &&
                                          c.fechaHoraAsistencia != null)
                                        Text(
                                          'Registrado: ${c.fechaHoraAsistencia}',
                                          style: const TextStyle(
                                            color: Colors.green,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                    ],
                                  ),
                                  value: c.asistio,
                                  onChanged: (val) =>
                                      _toggleAsistenciaManual(c, val ?? false),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

class EditarConvocatoriaPage extends StatefulWidget {
  final ConvocatoriaModel convocatoria;
  const EditarConvocatoriaPage({super.key, required this.convocatoria});

  @override
  State<EditarConvocatoriaPage> createState() => _EditarConvocatoriaPageState();
}

class _EditarConvocatoriaPageState extends State<EditarConvocatoriaPage> {
  final _formKey = GlobalKey<FormState>();
  final _db = DatabaseHelper();
  late final TextEditingController _descController;

  DateTime? _selectedDate;
  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 12, minute: 0);

  List<EmpleadoModel> _empleados = [];
  List<Map<String, dynamic>> _secciones = [];
  final Set<String> _empleadosSeleccionados = {};
  final Map<String, String> _erroresTraslape = {};

  String _filtroNombre = '';
  String? _seccionSeleccionada;

  bool _loadingEmpleados = false;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _descController = TextEditingController(
      text: widget.convocatoria.descripcion,
    );
    try {
      _selectedDate = DateTime.parse(widget.convocatoria.fecha);
    } catch (_) {}

    try {
      final startParts = widget.convocatoria.horaInicio.split(':');
      _startTime = TimeOfDay(
        hour: int.parse(startParts[0]),
        minute: int.parse(startParts[1]),
      );
    } catch (_) {}

    try {
      final endParts = widget.convocatoria.horaFinal.split(':');
      _endTime = TimeOfDay(
        hour: int.parse(endParts[0]),
        minute: int.parse(endParts[1]),
      );
    } catch (_) {}

    _loadEmpleados();
  }

  Future<void> _loadEmpleados() async {
    setState(() => _loadingEmpleados = true);
    try {
      final list = await _db.getAllEmpleados();
      final seccList = await _db.getSecciones();
      final listConvocados = await _db.getConvocadosPorConvocatoria(
        widget.convocatoria.id,
      );

      setState(() {
        _empleados = list.where((e) => e.estado == 'ACTIVO').toList();
        _secciones = seccList;
        _empleadosSeleccionados.addAll(
          listConvocados.map((c) => c.cedulaEmpleado),
        );
      });
      _validarTraslapesTodos();
    } catch (_) {}
    setState(() => _loadingEmpleados = false);
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
      _validarTraslapesTodos();
    }
  }

  Future<void> _selectTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
      _validarTraslapesTodos();
    }
  }

  String _formatTimeOfDay(TimeOfDay tod) {
    final h = tod.hour.toString().padLeft(2, '0');
    final m = tod.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _validarTraslapesTodos() async {
    if (_selectedDate == null) return;
    _erroresTraslape.clear();
    final fechaStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
    final startStr = _formatTimeOfDay(_startTime);
    final endStr = _formatTimeOfDay(_endTime);

    for (final emp in _empleados) {
      final err = await _validarTraslape(emp, fechaStr, startStr, endStr);
      if (err != null) {
        setState(() {
          _erroresTraslape[emp.cedula] = err;
          // Deseleccionar si tiene traslape
          _empleadosSeleccionados.remove(emp.cedula);
        });
      }
    }
    setState(() {});
  }

  Future<String?> _validarTraslape(
    EmpleadoModel empleado,
    String fechaStr,
    String startStr,
    String endStr,
  ) async {
    if (empleado.horarioId == null || empleado.horarioId!.isEmpty) return null;
    final horario = await _db.getHorarioById(empleado.horarioId!);
    if (horario == null || horario.items.isEmpty) return null;

    final date = DateTime.tryParse(fechaStr);
    if (date == null) return null;

    final weekday = date.weekday;
    final itemsHoy = horario.items.where((item) {
      switch (weekday) {
        case DateTime.monday:
          return item.lunes;
        case DateTime.tuesday:
          return item.martes;
        case DateTime.wednesday:
          return item.miercoles;
        case DateTime.thursday:
          return item.jueves;
        case DateTime.friday:
          return item.viernes;
        case DateTime.saturday:
          return item.sabado;
        case DateTime.sunday:
          return item.domingo;
        default:
          return false;
      }
    }).toList();

    if (itemsHoy.isEmpty) return null;

    int toMinutes(String hhmm) {
      final parts = hhmm.split(':');
      if (parts.length < 2) return 0;
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      return h * 60 + m;
    }

    final convStart = toMinutes(startStr);
    final convEnd = toMinutes(endStr);

    for (final item in itemsHoy) {
      final shiftStart = toMinutes(item.inicio);
      final shiftEnd = toMinutes(item.finalTime);

      if (convStart < shiftEnd && convEnd > shiftStart) {
        return 'Jornada laboral ordinaria asignada hoy de ${item.inicio} a ${item.finalTime}.';
      }
    }

    return null;
  }

  Future<void> _guardar() async {
    if (_selectedDate == null) return;
    if (!_formKey.currentState!.validate()) return;
    if (_empleadosSeleccionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Selecciona al menos un empleado para la convocatoria.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _guardando = true);

    try {
      final fechaStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      final startStr = _formatTimeOfDay(_startTime);
      final endStr = _formatTimeOfDay(_endTime);

      final convocatoria = ConvocatoriaModel(
        id: widget.convocatoria.id,
        fecha: fechaStr,
        horaInicio: startStr,
        horaFinal: endStr,
        descripcion: _descController.text.trim(),
      );

      // Actualizar cabecera
      await _db.insertConvocatoria(convocatoria);

      // Obtener asignaciones previas para conservar asistencia marcada
      final existing = await _db.getConvocadosPorConvocatoria(
        widget.convocatoria.id,
      );

      // Eliminar asignaciones anteriores
      final dbHelper = await _db.database;
      await dbHelper.delete(
        'itm_programacion_asistencia',
        where: 'convocatoria_id = ?',
        whereArgs: [widget.convocatoria.id],
      );

      // Re-insertar asignaciones
      for (final cedula in _empleadosSeleccionados) {
        final match = existing.cast<ConvocatoriaEmpleadoModel?>().firstWhere(
          (x) => x?.cedulaEmpleado == cedula,
          orElse: () => null,
        );

        final convocado = ConvocatoriaEmpleadoModel(
          convocatoriaId: widget.convocatoria.id,
          cedulaEmpleado: cedula,
          asistio: match?.asistio ?? false,
          fechaHoraAsistencia: match?.fechaHoraAsistencia,
        );
        await _db.insertConvocado(convocado);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Convocatoria modificada con éxito.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fechaStr = _selectedDate == null
        ? 'No seleccionada'
        : DateFormat('dd/MM/yyyy').format(_selectedDate!);

    final filteredEmpleados = _empleados.where((emp) {
      final matchesNombre =
          emp.nombre.toLowerCase().contains(_filtroNombre.toLowerCase()) ||
          emp.cedula.contains(_filtroNombre);
      final matchesSeccion =
          _seccionSeleccionada == null || emp.idSeccion == _seccionSeleccionada;
      return matchesNombre && matchesSeccion;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Modificar Convocatoria')),
      body: _guardando
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _descController,
                    decoration: const InputDecoration(
                      labelText: 'Descripción / Motivo',
                      hintText:
                          'Ej. Inventario general, Mantenimiento extra, etc.',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Ingresa la descripción'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.calendar_today),
                            title: const Text('Fecha de Convocatoria'),
                            subtitle: Text(fechaStr),
                            trailing: TextButton(
                              onPressed: _selectDate,
                              child: const Text('Cambiar'),
                            ),
                          ),
                          const Divider(),
                          ListTile(
                            leading: const Icon(Icons.access_time),
                            title: const Text('Hora Inicio'),
                            subtitle: Text(_formatTimeOfDay(_startTime)),
                            trailing: TextButton(
                              onPressed: () => _selectTime(true),
                              child: const Text('Cambiar'),
                            ),
                          ),
                          ListTile(
                            leading: const Icon(Icons.access_time_filled),
                            title: const Text('Hora Fin'),
                            subtitle: Text(_formatTimeOfDay(_endTime)),
                            trailing: TextButton(
                              onPressed: () => _selectTime(false),
                              child: const Text('Cambiar'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Asignar Personal Convocado:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),

                  if (_selectedDate == null)
                    Card(
                      color: Colors.amber.shade100,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.amber.shade900,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Por favor, selecciona una fecha primero para poder asignar personal y validar traslapes de horario.',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    Card(
                      color: Colors.grey.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            TextFormField(
                              decoration: const InputDecoration(
                                labelText: 'Buscar por Nombre o Cédula',
                                prefixIcon: Icon(Icons.search),
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              onChanged: (val) {
                                setState(() {
                                  _filtroNombre = val;
                                });
                              },
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: _seccionSeleccionada,
                              decoration: const InputDecoration(
                                labelText: 'Sección',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              hint: const Text('Todas las secciones'),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text('Todas las secciones'),
                                ),
                                ..._secciones.map((seccion) {
                                  return DropdownMenuItem<String>(
                                    value: seccion['id_seccion']?.toString(),
                                    child: Text(
                                      seccion['descripcion']?.toString() ?? '',
                                    ),
                                  );
                                }),
                              ],
                              onChanged: (val) {
                                setState(() {
                                  _seccionSeleccionada = val;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _loadingEmpleados
                        ? const Center(child: CircularProgressIndicator())
                        : filteredEmpleados.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: Text(
                                'No se encontraron empleados activos con los filtros aplicados.',
                                style: TextStyle(color: Colors.grey.shade600),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : Container(
                            constraints: const BoxConstraints(maxHeight: 380),
                            child: Scrollbar(
                              thumbVisibility: true,
                              child: ListView.builder(
                                itemCount: filteredEmpleados.length,
                                itemBuilder: (context, index) {
                                  final emp = filteredEmpleados[index];
                                  final err = _erroresTraslape[emp.cedula];
                                  final hasOverlap = err != null;

                                  return Card(
                                    color: hasOverlap
                                        ? Colors.red.shade50
                                        : null,
                                    child: CheckboxListTile(
                                      enabled: !hasOverlap,
                                      value: _empleadosSeleccionados.contains(
                                        emp.cedula,
                                      ),
                                      title: Text(emp.nombre),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('Cédula: ${emp.cedula}'),
                                          if (hasOverlap)
                                            Text(
                                              '⚠️ No disponible: $err',
                                              style: const TextStyle(
                                                color: Colors.red,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                        ],
                                      ),
                                      onChanged: (val) {
                                        setState(() {
                                          if (val == true) {
                                            _empleadosSeleccionados.add(
                                              emp.cedula,
                                            );
                                          } else {
                                            _empleadosSeleccionados.remove(
                                              emp.cedula,
                                            );
                                          }
                                        });
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: ElevatedButton(
            onPressed: (_guardando || _selectedDate == null) ? null : _guardar,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Guardar Cambios',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}
