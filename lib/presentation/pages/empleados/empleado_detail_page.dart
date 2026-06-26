import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/routes/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/local/database_helper.dart';
import '../../../data/models/empleado_model.dart';
import '../../../data/models/horario_model.dart';
import '../../../data/models/registro_model.dart';
import '../../../services/face_recognition_service.dart';
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

  // Variables de biometría en edición
  List<double>? _newVectorBiometrico;
  final List<double> _vectoresAcumulados = [];
  bool _enrolando = false;
  String _biometricStatusText = 'Esperando captura de rostro';
  Color _biometricStatusColor = Colors.grey;
  bool _rostroRegistrado = false;
  List<String>? _photoUris; // List to store photo URIs
  XFile? _capturedImage;
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;
  bool _initializingCamera = false;

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
    _disposeCamera();
    super.dispose();
  }

  Future<void> _disposeCamera() async {
    if (_cameraController != null) {
      await _cameraController!.dispose();
      _cameraController = null;
    }
    if (mounted) {
      setState(() {
        _isCameraInitialized = false;
        _initializingCamera = false;
      });
    }
  }

  Future<void> _resetBiometricsEditingState() async {
    await _disposeCamera();
    setState(() {
      _vectoresAcumulados.clear();
      _newVectorBiometrico = null;
      _enrolando = false;
      _biometricStatusText = 'Esperando captura de rostro';
      _biometricStatusColor = Colors.grey;
      _rostroRegistrado = _empleado?.mapaVectorFoto.isNotEmpty ?? false;
      _capturedImage = null;
    });
  }

  Future<void> _initializeCamera() async {
    if (_initializingCamera || _isCameraInitialized) return;

    setState(() {
      _initializingCamera = true;
      _capturedImage = null;
      _enrolando = false;
      _biometricStatusText = 'Iniciando cámara...';
      _biometricStatusColor = AppColors.info;
    });

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw Exception('No se detectaron cámaras en el dispositivo.');
      }

      CameraDescription selectedCamera = _cameras.first;
      for (final cam in _cameras) {
        if (cam.lensDirection == CameraLensDirection.front) {
          selectedCamera = cam;
          break;
        }
      }

      _cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _initializingCamera = false;
          _biometricStatusText = _vectoresAcumulados.isNotEmpty
              ? 'Cámara lista. Puedes tomar otra foto (${_vectoresAcumulados.length ~/ 512} registradas) o guardar.'
              : 'Cámara lista. Enmarque el rostro.';
          _biometricStatusColor = AppColors.primary;
        });
      }
    } catch (e) {
      await _disposeCamera();
      if (mounted) {
        setState(() {
          _enrolando = false;
          _biometricStatusText = 'Error al iniciar cámara: ${e.toString().replaceAll('Exception: ', '')}';
          _biometricStatusColor = AppColors.error;
        });
      }
    }
  }

  Future<void> _procesarImagen(String path) async {
    setState(() {
      _enrolando = true;
      _biometricStatusText = 'Procesando imagen y generando vector...';
      _biometricStatusColor = AppColors.primary;
    });

    try {
      final faceService = FaceRecognitionService();
      final vector = await faceService.generarVectorDesdeImagen(
        path,
        cedula: widget.cedula,
      );

      if (mounted) {
        setState(() {
          _vectoresAcumulados.addAll(vector);
          _newVectorBiometrico = _vectoresAcumulados;
          
          if (_capturedImage != null) {
            _photoUris ??= [];
            _photoUris!.add(_capturedImage!.path);
          }
          _enrolando = false;
          _rostroRegistrado = true;
          final numFotos = _vectoresAcumulados.length ~/ 512;
          _biometricStatusText = '¡Foto $numFotos registrada! Puedes tomar otra foto para mayor precisión o guardar ahora.';
          _biometricStatusColor = AppColors.success;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('¡Foto ${_vectoresAcumulados.length ~/ 512} validada con éxito!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _capturedImage = null;
          _enrolando = false;
          _biometricStatusText = 'Error en validación de rostro: ${e.toString().replaceAll('Exception: ', '')}';
          _biometricStatusColor = AppColors.error;
        });
      }
    }
  }

  Future<void> _capturarFoto() async {
    if (_cameraController == null || !_isCameraInitialized) return;
    try {
      final image = await _cameraController!.takePicture();
      await _disposeCamera();

      setState(() {
        _capturedImage = image;
      });

      await _procesarImagen(image.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al capturar foto: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _seleccionarDeGaleria() async {
    await _disposeCamera();
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1000,
        maxHeight: 1000,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _capturedImage = XFile(pickedFile.path);
        });
        await _procesarImagen(pickedFile.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al seleccionar imagen: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _cancelarAcciones() async {
    await _disposeCamera();
    setState(() {
      _vectoresAcumulados.clear();
      _newVectorBiometrico = null;
      _capturedImage = null;
      _enrolando = false;
      _rostroRegistrado = false;
      _biometricStatusText = 'Esperando captura de rostro';
      _biometricStatusColor = Colors.grey;
    });
  }

  Future<void> _loadEmpleadoData() async {
    setState(() => _loading = true);
    try {
      final emp = await _db.getEmpleadoByCedula(widget.cedula);
      if (emp != null) {
        _empleado = emp;
        _photoUris = emp.fotoUris;
        if (emp.horarioId != null) {
          final h = await _db.getHorarioById(emp.horarioId!);
          if (h != null) _horario = h;
        }
        if (emp.idSeccion != null) {
          _seccionDescripcion = await _db.getSeccionDescripcion(emp.idSeccion!);
        }
        _registros = await _db.getRegistrosPorCedula(widget.cedula);

        _allHorarios = await _db.getAllHorarios();
        _allSecciones = await _db.getSecciones();

        _nombreCtrl.text = emp.nombre;
        _fechaIniCtrl.text = emp.fechaIniContrato ?? '';
        _fechaFinCtrl.text = emp.fechaFinContrato ?? '';
        _selectedHorarioId = emp.horarioId;
        final rawTipo = (emp.tipo ?? 'OPERATIVO').trim().toUpperCase();
        _selectedTipo = (rawTipo == 'OPERATIVO' || rawTipo == 'ADMINISTRATIVO' || rawTipo == 'LIDER') ? rawTipo : 'OPERATIVO';
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

    if (!_rostroRegistrado) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Por favor, registre y valide los datos faciales antes de guardar.',
          ),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

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
        idSeccion: (_selectedTipo == 'OPERATIVO' || _selectedTipo == 'LIDER') ? _selectedSeccionId : null,
        tipo: _selectedTipo,
        sincronizado: false,
        mapaVectorFoto: _newVectorBiometrico ?? _empleado!.mapaVectorFoto,
        fotoUris: _photoUris,
      );

      final success = await _db.updateEmpleado(updated);
      if (success > 0) {
        await _disposeCamera();
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

  // Returns the appropriate color for a given registro tipo
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
          onPressed: () async {
            if (_isEditing) {
              await _resetBiometricsEditingState();
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
                  final rawTipo = (_empleado!.tipo ?? 'OPERATIVO').trim().toUpperCase();
                  _selectedTipo = (rawTipo == 'OPERATIVO' || rawTipo == 'ADMINISTRATIVO' || rawTipo == 'LIDER') ? rawTipo : 'OPERATIVO';
                  _selectedSeccionId = _empleado!.idSeccion;

                  _vectoresAcumulados.clear();
                  _photoUris = List<String>.from(_empleado!.fotoUris ?? []);
                  if (tieneVector) {
                    _vectoresAcumulados.addAll(_empleado!.mapaVectorFoto);
                  }
                  _newVectorBiometrico = null;
                  _rostroRegistrado = tieneVector;
                  final numFotos = _vectoresAcumulados.length ~/ 512;
                  _biometricStatusText = tieneVector
                      ? 'Rostro ya registrado ($numFotos fotos). Puede re-tomar o subir otra foto si desea actualizarlo.'
                      : 'Esperando captura de rostro';
                  _biometricStatusColor = tieneVector ? AppColors.success : Colors.grey;
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
              onPressed: () async {
                await _resetBiometricsEditingState();
                setState(() => _isEditing = false);
              },
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isEditing)
              Form(
                key: _formKey,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 36,
                              backgroundColor: tieneVector
                                  ? AppColors.success.withValues(alpha: 0.1)
                                  : AppColors.warning.withValues(alpha: 0.1),
                              child: Icon(
                                tieneVector ? Icons.face : Icons.face_retouching_off,
                                color: tieneVector ? AppColors.success : AppColors.warning,
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
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 32),
                        TextFormField(
                          controller: _nombreCtrl,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Nombre Completo (No editable)',
                            prefixIcon: Icon(Icons.person),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: _allHorarios.any((h) => h.idHorario == _selectedHorarioId) ? _selectedHorarioId : null,
                          decoration: const InputDecoration(
                            labelText: 'Horario Asignado',
                            prefixIcon: Icon(Icons.schedule),
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem<String>(value: null, child: Text('Sin horario asignado')),
                            ..._allHorarios.map((h) => DropdownMenuItem<String>(value: h.idHorario, child: Text('${h.descripcion}'))),
                          ],
                          onChanged: (val) => setState(() => _selectedHorarioId = val),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: _selectedTipo,
                          decoration: const InputDecoration(
                            labelText: 'Tipo de Empleado',
                            prefixIcon: Icon(Icons.badge_outlined),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem<String>(value: 'OPERATIVO', child: Text('OPERATIVO')),
                            DropdownMenuItem<String>(value: 'ADMINISTRATIVO', child: Text('ADMINISTRATIVO')),
                            DropdownMenuItem<String>(value: 'LIDER', child: Text('LIDER')),
                          ],
                          onChanged: (val) => setState(() {
                            _selectedTipo = val;
                            if (val == 'ADMINISTRATIVO') _selectedSeccionId = null;
                          }),
                        ),
                        const SizedBox(height: 16),
                        if (_selectedTipo == 'OPERATIVO' || _selectedTipo == 'LIDER') ...[
                          DropdownButtonFormField<String>(
                            value: _allSecciones.any((s) => s['id_seccion'] == _selectedSeccionId) ? _selectedSeccionId : null,
                            decoration: const InputDecoration(
                              labelText: 'Sección Asignada',
                              prefixIcon: Icon(Icons.view_quilt_outlined),
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem<String>(value: null, child: Text('Sin sección asignada')),
                              ..._allSecciones.map((s) => DropdownMenuItem<String>(value: s['id_seccion'] as String?, child: Text(s['descripcion'] as String))),
                            ],
                            onChanged: (val) => setState(() => _selectedSeccionId = val),
                          ),
                          const SizedBox(height: 16),
                        ],
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
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.tryParse(_fechaIniCtrl.text) ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) _fechaIniCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _fechaFinCtrl,
                          decoration: InputDecoration(
                            labelText: 'Fin de Contrato (Opcional)',
                            prefixIcon: const Icon(Icons.calendar_month),
                            border: const OutlineInputBorder(),
                            hintText: 'Indefinido',
                            suffixIcon: _fechaFinCtrl.text.isNotEmpty
                                ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _fechaFinCtrl.clear()))
                                : null,
                          ),
                          readOnly: true,
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.tryParse(_fechaFinCtrl.text) ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) _fechaFinCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
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
                            backgroundColor: tieneVector ? AppColors.success.withValues(alpha: 0.1) : AppColors.warning.withValues(alpha: 0.1),
                            child: Icon(tieneVector ? Icons.face : Icons.face_retouching_off, color: tieneVector ? AppColors.success : AppColors.warning, size: 38),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_empleado!.nombre, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                                const SizedBox(height: 4),
                                Text('Cédula: ${_empleado!.cedula}', style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 32),
                      _InfoRow(icon: Icons.schedule, label: 'Horario Asignado', value: _horario != null ? '${_horario!.descripcion}' : 'Sin horario asignado'),
                      const SizedBox(height: 12),
                      _InfoRow(icon: Icons.badge_outlined, label: 'Tipo de Empleado', value: _empleado!.tipo ?? 'No especificado'),
                      if (_empleado!.tipo == 'OPERATIVO' || _empleado!.tipo == 'LIDER' || _empleado!.tipo == null) ...[
                        const SizedBox(height: 12),
                        _InfoRow(icon: Icons.view_quilt_outlined, label: 'Sección asignada', value: _seccionDescripcion ?? _empleado!.idSeccion ?? 'Sin sección asignada'),
                      ],
                      const SizedBox(height: 12),
                      _InfoRow(icon: Icons.calendar_today, label: 'Inicio de Contrato', value: _empleado!.fechaIniContrato ?? 'No registrada'),
                      const SizedBox(height: 12),
                      _InfoRow(icon: Icons.calendar_month, label: 'Fin de Contrato', value: _empleado!.fechaFinContrato ?? 'Indefinido'),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
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
                        Text(_isEditing ? 'Enrolamiento Biométrico Facial' : 'Datos Biométricos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_isEditing) ...[
                      Center(
                        child: Container(
                          width: double.infinity,
                          height: 240,
                          decoration: BoxDecoration(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _biometricStatusColor.withValues(alpha: 0.5), width: 2),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                if (_isCameraInitialized && _cameraController != null && _capturedImage == null)
                                  Positioned.fill(
                                    child: AspectRatio(aspectRatio: _cameraController!.value.aspectRatio, child: CameraPreview(_cameraController!)),
                                  ),
                                if (_capturedImage != null)
                                  Positioned.fill(
                                    child: kIsWeb ? Image.network(_capturedImage!.path, fit: BoxFit.cover) : Image.file(File(_capturedImage!.path), fit: BoxFit.cover),
                                  ),
                                if (_enrolando || _initializingCamera) ...[
                                  Positioned.fill(child: Container(color: Colors.black54)),
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      CircularProgressIndicator(color: _biometricStatusColor),
                                      const SizedBox(height: 16),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        child: Text(
                                          _biometricStatusText,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ],
                                  ),
                                ]
                                // 5. Estado inicial (Esperando foto)
                                else if (!_isCameraInitialized &&
                                    _capturedImage == null) ...[
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.face,
                                        size: 54,
                                        color: AppColors.textDisabled,
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        _biometricStatusText,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: _biometricStatusColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],

                                // Overlay estético de marco/mira de escaneo facial cuando la cámara está activa
                                if (_isCameraInitialized &&
                                    _cameraController != null &&
                                    _capturedImage == null &&
                                    !_enrolando)
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: AppColors.primary.withValues(
                                            alpha: 0.4,
                                          ),
                                          width: 3,
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Center(
                                        child: Container(
                                          width: 140,
                                          height: 140,
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: AppColors.secondary
                                                  .withValues(alpha: 0.8),
                                              width: 2,
                                              style: BorderStyle.solid,
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Botones de acción dinámicos
                      if (_isCameraInitialized &&
                          _cameraController != null &&
                          _capturedImage == null) ...[
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _enrolando ? null : _capturarFoto,
                                icon: const Icon(Icons.camera),
                                label: const Text('Tomar Foto'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _enrolando ? null : _cancelarAcciones,
                                icon: const Icon(Icons.cancel),
                                label: const Text('Cancelar'),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: AppColors.error,
                                  ),
                                  foregroundColor: AppColors.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _enrolando
                                    ? null
                                    : _initializeCamera,
                                icon: const Icon(Icons.camera_alt_outlined),
                                label: Text(
                                  _rostroRegistrado
                                      ? 'Re-tomar Foto'
                                      : 'Activar Cámara',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _enrolando
                                    ? null
                                    : _seleccionarDeGaleria,
                                icon: const Icon(Icons.photo_library_outlined),
                                label: Text(
                                  _rostroRegistrado
                                      ? 'Subir Otra'
                                      : 'Subir Foto',
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_rostroRegistrado && _capturedImage != null) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _cancelarAcciones,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Limpiar Captura'),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: _biometricStatusColor),
                                foregroundColor: _biometricStatusColor,
                              ),
                            ),
                          ),
                        ],
                      ],
                      const SizedBox(height: 16),
if (_isEditing && _photoUris != null && _photoUris!.isNotEmpty) ...[
  Text('Fotos registradas (${_photoUris!.length})', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
  const SizedBox(height: 8),
  GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 4,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
    ),
    itemCount: _photoUris!.length,
    itemBuilder: (context, index) {
      final uri = _photoUris![index];
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(File(uri), fit: BoxFit.cover),
      );
    },
  ),
  const SizedBox(height: 16),
],
                    ],

                    // Vector preview (either existing or new vector)
                    if (_newVectorBiometrico != null || (tieneVector && !_isEditing)) ...[
                      Text(
                        _newVectorBiometrico != null
                            ? 'Nuevo(s) vector(es) facial(es) (${_vectoresAcumulados.length ~/ 512} foto(s)) generado(s). Guarde los cambios para registrar.'
                            : 'Vector(es) facial(es) registrado(s) (${_empleado!.mapaVectorFoto.length ~/ 512} foto(s)). Listo para autenticación local en modo Tótem.',
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
                            final vectorSource = _newVectorBiometrico ?? _empleado!.mapaVectorFoto;
                            // Muestra una barra proporcional a los valores del vector
                            final val = (index * 2 < vectorSource.length) ? vectorSource[index * 2].abs() : 0.0;
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
                          'Representación gráfica de la firma facial única (puntos de control mostrados)',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textDisabled,
                          ),
                        ),
                      ),
                    ] else if (!_isEditing) ...[
                      Text(
                        'Este empleado no tiene datos faciales enrolados en este dispositivo. Para que pueda marcar asistencia en el Tótem, debe registrar su rostro desde la opción de Editar o Registrar Nuevo Empleado.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ] else if (_newVectorBiometrico == null && !tieneVector) ...[
                      Text(
                        'No hay datos faciales registrados para este colaborador. Active la cámara o suba una foto para realizar el enrolamiento.',
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
