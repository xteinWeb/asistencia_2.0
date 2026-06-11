import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:math';
import 'dart:io';

import '../../../core/routes/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/local/database_helper.dart';
import '../../../data/models/empleado_model.dart';
import 'package:provider/provider.dart';
import '../../../data/models/horario_model.dart';
import '../../../domain/usecases/registrar_empleado_usecase.dart';
import '../../../services/sync_service.dart';

class RegistroEmpleadoPage extends StatefulWidget {
  const RegistroEmpleadoPage({super.key});

  @override
  State<RegistroEmpleadoPage> createState() => _RegistroEmpleadoPageState();
}

class _AppState {
  final bool enrolando;
  final bool rostroRegistrado;
  final List<double> vectorBiometrico;
  final String statusText;
  final Color statusColor;

  const _AppState({
    required this.enrolando,
    required this.rostroRegistrado,
    required this.vectorBiometrico,
    required this.statusText,
    required this.statusColor,
  });
}

class _RegistroEmpleadoPageState extends State<RegistroEmpleadoPage> {
  final _formKey = GlobalKey<FormState>();
  final _db = DatabaseHelper();

  final _cedulaCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _fechaIniCtrl = TextEditingController();
  final _fechaFinCtrl = TextEditingController();

  List<HorarioModel> _horarios = [];
  String? _selectedHorarioId;

  List<Map<String, dynamic>> _secciones = [];
  String? _selectedSeccionId;

  String? _selectedTipo = 'OPERATIVO'; // Default is OPERATIVO

  // Modos de enrolamiento: REAL (con API) o SIMULADO (local offline)
  bool _modoReal = true;

  // Control de cámara en vivo y galería
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;
  bool _initializingCamera = false;
  XFile? _capturedImage;

  _AppState _state = const _AppState(
    enrolando: false,
    rostroRegistrado: false,
    vectorBiometrico: [],
    statusText: 'Esperando captura de rostro',
    statusColor: Colors.grey,
  );

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadHorarios();
    _loadSecciones();
    // Valor de inicio de contrato por defecto: Hoy
    _fechaIniCtrl.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
  }

  Future<void> _loadSecciones() async {
    try {
      final list = await _db.getSecciones();
      setState(() {
        _secciones = list;
        if (list.isNotEmpty) {
          _selectedSeccionId = list.first['id_seccion'] as String?;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar secciones: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _cedulaCtrl.dispose();
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

  Future<void> _loadHorarios() async {
    try {
      final list = await _db.getAllHorarios();
      setState(() {
        _horarios = list;
        if (list.isNotEmpty) {
          _selectedHorarioId = list.first.idHorario;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar horarios: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _selectDate(TextEditingController controller) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        controller.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<void> _initializeCamera() async {
    if (_initializingCamera || _isCameraInitialized) return;

    setState(() {
      _initializingCamera = true;
      _capturedImage = null;
      _state = const _AppState(
        enrolando: false,
        rostroRegistrado: false,
        vectorBiometrico: [],
        statusText: 'Iniciando cámara...',
        statusColor: AppColors.info,
      );
    });

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw Exception('No se detectaron cámaras en el dispositivo.');
      }

      // Priorizar la cámara frontal para el registro del empleado
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
          _state = const _AppState(
            enrolando: false,
            rostroRegistrado: false,
            vectorBiometrico: [],
            statusText: 'Cámara lista. Enmarque el rostro.',
            statusColor: AppColors.primary,
          );
        });
      }
    } catch (e) {
      await _disposeCamera();
      if (mounted) {
        setState(() {
          _state = _AppState(
            enrolando: false,
            rostroRegistrado: false,
            vectorBiometrico: [],
            statusText:
                'Error al iniciar cámara: ${e.toString().replaceAll('Exception: ', '')}',
            statusColor: AppColors.error,
          );
        });
      }
    }
  }

  Future<void> _procesarImagen(String path) async {
    setState(() {
      _state = const _AppState(
        enrolando: true,
        rostroRegistrado: false,
        vectorBiometrico: [],
        statusText: 'Procesando imagen y validando rostro...',
        statusColor: AppColors.primary,
      );
    });

    try {
      if (_modoReal) {
        final useCase = RegistrarEmpleadoUseCase();

        final empTemp = await useCase.execute(
          cedula: _cedulaCtrl.text.trim().isEmpty
              ? 'test_temp'
              : _cedulaCtrl.text.trim(),
          nombre: _nombreCtrl.text.trim().isEmpty
              ? 'Empleado de Prueba'
              : _nombreCtrl.text.trim(),
          imagePath: path,
          horarioId: _selectedHorarioId,
          fechaIniContrato: _fechaIniCtrl.text,
          fechaFinContrato: _fechaFinCtrl.text.isNotEmpty
              ? _fechaFinCtrl.text
              : null,
          sedePrincipal: null,
          idSeccion: _selectedTipo == 'OPERATIVO' ? _selectedSeccionId : null,
          tipo: _selectedTipo,
        );

        if (mounted) {
          setState(() {
            _state = _AppState(
              enrolando: false,
              rostroRegistrado: true,
              vectorBiometrico: empTemp.mapaVectorFoto,
              statusText: '¡ROSTRO CAPTURADO Y VALIDADO CON API EXITOSAMENTE!',
              statusColor: AppColors.success,
            );
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('¡Rostro validado en el servidor con éxito!'),
              backgroundColor: AppColors.success,
            ),
          );
        }

        // Eliminar del SQLite el registro temporal creado por el caso de uso
        await _db.deleteEmpleado(empTemp.cedula);
      } else {
        // MODO SIMULADO (Offline de desarrollo)
        await Future.delayed(const Duration(milliseconds: 1500));
        final random = Random();
        final mockVector = List.generate(
          128,
          (_) => (random.nextDouble() * 2 - 1) * 0.4,
        );

        if (mounted) {
          setState(() {
            _state = _AppState(
              enrolando: false,
              rostroRegistrado: true,
              vectorBiometrico: mockVector,
              statusText: '¡ROSTRO CAPTURADO CORRECTAMENTE (SIMULADO OFFLINE)!',
              statusColor: AppColors.success,
            );
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '¡Firma biométrica simulada de 128 floats generada localmente!',
              ),
              backgroundColor: AppColors.success,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _capturedImage = null;
          _state = _AppState(
            enrolando: false,
            rostroRegistrado: false,
            vectorBiometrico: [],
            statusText:
                'Error en validación de rostro: ${e.toString().replaceAll('Exception: ', '')}',
            statusColor: AppColors.error,
          );
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
      _capturedImage = null;
      _state = const _AppState(
        enrolando: false,
        rostroRegistrado: false,
        vectorBiometrico: [],
        statusText: 'Esperando captura de rostro',
        statusColor: Colors.grey,
      );
    });
  }

  Future<void> _guardarEmpleado() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_state.rostroRegistrado || _state.vectorBiometrico.isEmpty) {
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

    setState(() => _saving = true);
    try {
      // 1. Comprobar duplicidad de Cédula
      final existente = await _db.getEmpleadoByCedula(_cedulaCtrl.text.trim());
      if (existente != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Error: Ya existe un empleado registrado con esta Cédula.',
            ),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }

      // 2. Crear modelo definitivo
      final empleado = EmpleadoModel(
        cedula: _cedulaCtrl.text.trim(),
        nombre: _nombreCtrl.text.trim(),
        mapaVectorFoto: _state.vectorBiometrico,
        horarioId: _selectedHorarioId,
        fechaIniContrato: _fechaIniCtrl.text.isNotEmpty
            ? _fechaIniCtrl.text
            : null,
        fechaFinContrato: _fechaFinCtrl.text.isNotEmpty
            ? _fechaFinCtrl.text
            : null,
        sedePrincipal: null,
        idSeccion: _selectedTipo == 'OPERATIVO' ? _selectedSeccionId : null,
        tipo: _selectedTipo,
        fechaRegistro: DateTime.now().toIso8601String(),
      );

      // 3. Guardar en SQLite local
      await _db.insertEmpleado(empleado);

      // Sincronizar de fondo inmediatamente ya que el registro de empleados requiere internet de todos modos
      if (mounted) {
        context.read<SyncService>().syncAll();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Empleado y datos biométricos registrados correctamente en SQLite.',
            ),
            backgroundColor: AppColors.success,
          ),
        );
        context.go(AppRoutes.empleados);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar empleado: $e'),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar Nuevo Empleado'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.empleados),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ficha del Formulario
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Datos del Empleado',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Cédula
                      TextFormField(
                        controller: _cedulaCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Cédula de Identidad (CC)',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Ingrese la cédula del empleado'
                            : null,
                      ),
                      const SizedBox(height: 16),

                      // Nombre
                      TextFormField(
                        controller: _nombreCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Nombre Completo',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Ingrese el nombre del empleado'
                            : null,
                      ),
                      const SizedBox(height: 16),

                      // Selección de Horario
                      DropdownButtonFormField<String>(
                        initialValue:
                            _horarios.any(
                              (h) => h.idHorario == _selectedHorarioId,
                            )
                            ? _selectedHorarioId
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Horario Asignado',
                          prefixIcon: Icon(Icons.schedule_outlined),
                        ),
                        items: _horarios.map((h) {
                          return DropdownMenuItem<String>(
                            value: h.idHorario,
                            child: Text('${h.descripcion}'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedHorarioId = val;
                          });
                        },
                        validator: (v) => v == null
                            ? 'Seleccione un horario para el empleado'
                            : null,
                      ),
                      if (_horarios.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, left: 8),
                          child: Text(
                            '⚠️ No hay horarios creados. Ve a "Horarios" primero.',
                            style: TextStyle(
                              color: AppColors.warning,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),

                      // Tipo de Empleado
                      DropdownButtonFormField<String>(
                        initialValue: _selectedTipo,
                        decoration: const InputDecoration(
                          labelText: 'Tipo de Empleado',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'OPERATIVO',
                            child: Text('OPERATIVO'),
                          ),
                          DropdownMenuItem(
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
                        validator: (v) =>
                            v == null ? 'Seleccione el tipo de empleado' : null,
                      ),

                      if (_selectedTipo == 'OPERATIVO') ...[
                        const SizedBox(height: 16),
                        // Selección de Sección
                        DropdownButtonFormField<String>(
                          initialValue: _selectedSeccionId,
                          decoration: const InputDecoration(
                            labelText: 'Sección asignada',
                            prefixIcon: Icon(Icons.view_quilt_outlined),
                          ),
                          items: _secciones.map((s) {
                            return DropdownMenuItem<String>(
                              value: s['id_seccion'] as String,
                              child: Text(s['descripcion'] as String),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedSeccionId = val;
                            });
                          },
                          validator: (v) =>
                              (_selectedTipo == 'OPERATIVO' && v == null)
                              ? 'Seleccione una sección para el empleado'
                              : null,
                        ),
                        if (_secciones.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6, left: 8),
                            child: Text(
                              '⚠️ No hay secciones cargadas. Sincronice primero.',
                              style: TextStyle(
                                color: AppColors.warning,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],

                      const SizedBox(height: 16),

                      // Fechas de Contrato
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _fechaIniCtrl,
                              readOnly: true,
                              decoration: const InputDecoration(
                                labelText: 'Inicio Contrato',
                                prefixIcon: Icon(Icons.date_range),
                              ),
                              onTap: () => _selectDate(_fechaIniCtrl),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _fechaFinCtrl,
                              readOnly: true,
                              decoration: const InputDecoration(
                                labelText: 'Fin Contrato (Opcional)',
                                prefixIcon: Icon(Icons.date_range),
                              ),
                              onTap: () => _selectDate(_fechaFinCtrl),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Tarjeta de Escaneo Facial
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Enrolamiento Biométrico Facial',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),

                          // Selector de Modo de Enrolamiento
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _modoReal
                            ? 'El Tótem enviará la foto de la cámara de forma segura a la API de Node.js en internet para validarla y generar su vector de 128 flotantes.'
                            : 'Genera una firma biométrica local de 128 floats de forma instantánea. Ideal para pruebas sin internet ni servidores Node.js levantados.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Caja interactiva de cámara y vista previa
                      Center(
                        child: Container(
                          width: double.infinity,
                          height: 240,
                          decoration: BoxDecoration(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _state.statusColor.withValues(alpha: 0.5),
                              width: 2,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // 1. Mostrar Cámara Activa si está inicializada
                                if (_isCameraInitialized &&
                                    _cameraController != null &&
                                    _capturedImage == null)
                                  Positioned.fill(
                                    child: AspectRatio(
                                      aspectRatio:
                                          _cameraController!.value.aspectRatio,
                                      child: CameraPreview(_cameraController!),
                                    ),
                                  ),

                                // 2. Mostrar la foto capturada o seleccionada si existe
                                if (_capturedImage != null)
                                  Positioned.fill(
                                    child: kIsWeb
                                        ? Image.network(
                                            _capturedImage!.path,
                                            fit: BoxFit.cover,
                                          )
                                        : Image.file(
                                            File(_capturedImage!.path),
                                            fit: BoxFit.cover,
                                          ),
                                  ),

                                // 3. Overlay para estado de procesamiento/cargando
                                if (_state.enrolando ||
                                    _initializingCamera) ...[
                                  Positioned.fill(
                                    child: Container(color: Colors.black54),
                                  ),
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      CircularProgressIndicator(
                                        color: _state.statusColor,
                                      ),
                                      const SizedBox(height: 16),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        child: Text(
                                          _state.statusText,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ],
                                  ),
                                ]
                                // 4. Estado de éxito (Rostro registrado)
                                else if (_state.rostroRegistrado) ...[
                                  Positioned.fill(
                                    child: Container(color: Colors.black38),
                                  ),
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.check_circle,
                                        size: 54,
                                        color: _state.statusColor,
                                      ),
                                      const SizedBox(height: 10),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        child: Text(
                                          _state.statusText,
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
                                        _state.statusText,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: _state.statusColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],

                                // Overlay estético de marco/mira de escaneo facial cuando la cámara está activa
                                if (_isCameraInitialized &&
                                    _cameraController != null &&
                                    _capturedImage == null &&
                                    !_state.enrolando)
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
                                onPressed: _state.enrolando
                                    ? null
                                    : _capturarFoto,
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
                                onPressed: _state.enrolando
                                    ? null
                                    : _cancelarAcciones,
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
                                onPressed: _state.enrolando || _saving
                                    ? null
                                    : _initializeCamera,
                                icon: const Icon(Icons.camera_alt_outlined),
                                label: Text(
                                  _state.rostroRegistrado
                                      ? 'Re-tomar Foto'
                                      : 'Activar Cámara',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _state.enrolando || _saving
                                    ? null
                                    : _seleccionarDeGaleria,
                                icon: const Icon(Icons.photo_library_outlined),
                                label: Text(
                                  _state.rostroRegistrado
                                      ? 'Subir Otra'
                                      : 'Subir Foto',
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_state.rostroRegistrado) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _cancelarAcciones,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Limpiar Captura'),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: _state.statusColor),
                                foregroundColor: _state.statusColor,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Botón Guardar
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving || _state.enrolando
                      ? null
                      : _guardarEmpleado,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Guardar Empleado'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
