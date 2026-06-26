import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:provider/provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:math';
import 'dart:io';

import '../../../core/theme/app_colors.dart';
import '../../../services/face_recognition_service.dart';
import '../../../services/sync_service.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/horario_validator.dart';
import '../../../core/constants/db_constants.dart';
import '../../../data/datasources/local/database_helper.dart';
import '../../../domain/usecases/marcar_asistencia_usecase.dart';
import '../../../core/routes/app_router.dart';
import '../../../data/models/empleado_model.dart';
import '../../../data/models/registro_model.dart';
import '../../../services/auth_service.dart';

class AsistenciaPage extends StatefulWidget {
  const AsistenciaPage({super.key});

  @override
  State<AsistenciaPage> createState() => _AsistenciaPageState();
}

class _AppState {
  final bool procesando;
  final String mensaje;
  final Color mensajeColor;
  final String? empleadoNombre;
  final String? empleadoCedula;
  final TipoRegistro? tipoRegistro;
  final double? distancia;

  const _AppState({
    required this.procesando,
    required this.mensaje,
    required this.mensajeColor,
    this.empleadoNombre,
    this.empleadoCedula,
    this.tipoRegistro,
    this.distancia,
  });
}

class _AsistenciaPageState extends State<AsistenciaPage> {
  bool _procesando = false;

  // Variables de control de cámara frontal
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;
  bool _initializingCamera = false;
  XFile? _capturedImage;
  String _userRole = 'OPERADOR';
  
  // Variables de exposición manual
  double _currentExposureOffset = -1.0;
  double _minExposureOffset = -2.0;
  double _maxExposureOffset = 2.0;
  bool _supportsExposureOffset = false;

  // Variables para la selección manual e identificación
  EmpleadoModel? _empleadoIdentificado;
  double? _distanciaMatch;
  List<RegistroModel> _registrosHoy = [];
  bool _mostrarPanelSeleccion = false;
  bool _permitirManual = true;
  bool _esMarcadoCedula = false;

  // Detector de caras de Google ML Kit para Prueba de Vida (Liveness)
  late final FaceDetector _faceDetector;

  // Motor TTS para notificaciones por voz (Opción 1)
  final FlutterTts _flutterTts = FlutterTts();

  _AppState _state = const _AppState(
    procesando: false,
    mensaje: 'Inicializando cámara frontal...',
    mensajeColor: Colors.white70,
  );

  late final Stream<DateTime> _clockStream;

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadConfig();
    _clockStream = Stream.periodic(
      const Duration(seconds: 1),
      (_) => DateTime.now(),
    );
    // Inicializar detector de caras de ML Kit con clasificación activa
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification:
            true, // Habilita leftEyeOpenProbability / rightEyeOpenProbability
      ),
    );
    // Inicializar la cámara de forma automática para Kiosko Tótem
    _initializeCamera();
  }

  Future<void> _initTts() async {
    try {
      await _flutterTts.setLanguage("es");
      await _flutterTts.setSpeechRate(0.55);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
    } catch (e) {
      debugPrint("Error al inicializar TTS: $e");
    }
  }

  Future<void> _speak(String text) async {
    try {
      String cleanedText = text
          .replaceAll('¡', '')
          .replaceAll('!', '')
          .replaceAll('¿', '')
          .replaceAll('?', '')
          .replaceAll(':', '')
          .replaceAll('⚠️', '')
          .replaceAll('-', ' ')
          .replaceAll('(', ' ')
          .replaceAll(')', ' ');
      await _flutterTts.speak(cleanedText);
    } catch (e) {
      debugPrint("Error en TTS speak: $e");
    }
  }

  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _userRole = prefs.getString('user_role') ?? 'OPERADOR';
      });

      final db = DatabaseHelper();
      final permitir = await db.getConfig(DbConstants.cfgPermitirManual) ?? '1';
      setState(() {
        _permitirManual = permitir == '1';
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _faceDetector.close(); // Liberar recursos del detector de caras nativo
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

  Future<void> _initializeCamera() async {
    if (_initializingCamera || _isCameraInitialized) return;

    setState(() {
      _initializingCamera = true;
      _capturedImage = null;
      _state = const _AppState(
        procesando: false,
        mensaje: 'Iniciando cámara del Tótem...',
        mensajeColor: AppColors.info,
      );
    });

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw Exception('No se detectaron cámaras en el dispositivo.');
      }

      // Priorizar la cámara frontal para el Kiosko de Asistencia
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

      // Configuración de la exposición para mitigar brillos y contraluces
      try {
        _minExposureOffset = await _cameraController!.getMinExposureOffset();
        _maxExposureOffset = await _cameraController!.getMaxExposureOffset();
        _supportsExposureOffset = _minExposureOffset < _maxExposureOffset;
        
        // Mantener el offset por defecto en -1.0 si entra en el rango.
        if (_currentExposureOffset < _minExposureOffset) {
          _currentExposureOffset = _minExposureOffset;
        } else if (_currentExposureOffset > _maxExposureOffset) {
          _currentExposureOffset = _maxExposureOffset;
        }
        
        if (_supportsExposureOffset) {
          await _cameraController!.setExposureOffset(_currentExposureOffset);
        }
        await _cameraController!.setExposureMode(ExposureMode.auto);
      } catch (e) {
        debugPrint("Error configurando brillo/exposición de la cámara: $e");
      }

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _initializingCamera = false;
          _state = const _AppState(
            procesando: false,
            mensaje: 'Listo para escanear',
            mensajeColor: Colors.white70,
          );
        });
      }
    } catch (e) {
      await _disposeCamera();
      if (mounted) {
        setState(() {
          _state = _AppState(
            procesando: false,
            mensaje:
                'Error de cámara: ${e.toString().replaceAll('Exception: ', '')}',
            mensajeColor: AppColors.error,
          );
        });
      }
    }
  }

  /// FASE 1: Captura el rostro real con la cámara y lo identifica contra SQLite.
  /// Despliega el panel de selección de registro.
  Future<void> _marcarAsistenciaReal() async {
    if (_procesando || _cameraController == null || !_isCameraInitialized)
      return;

    setState(() {
      _procesando = true;
      _capturedImage = null;
      _empleadoIdentificado = null;
      _distanciaMatch = null;
      _mostrarPanelSeleccion = false;
      _esMarcadoCedula = false;
      _state = const _AppState(
        procesando: true,
        mensaje: 'Capturando rostro...',
        mensajeColor: AppColors.primary,
      );
    });

    try {
      // 1. Capturar foto
      final image = await _cameraController!.takePicture();

      if (mounted) {
        setState(() {
          _capturedImage = image;
          _state = const _AppState(
            procesando: true,
            mensaje: 'Enviando imagen a API Node.js...',
            mensajeColor: AppColors.info,
          );
        });
      }

      // 2. Extraer vector llamando al backend Node.js
      final faceService = FaceRecognitionService();
      final vector = await faceService.generarVectorDesdeImagen(image.path);

      if (vector.isEmpty) {
        throw Exception('El servidor no devolvió una firma biométrica válida.');
      }

      if (mounted) {
        setState(() {
          _state = const _AppState(
            procesando: true,
            mensaje: 'Identificando empleado...',
            mensajeColor: AppColors.info,
          );
        });
      }

      // 3. Buscar coincidencia local en SQLite
      final useCase = MarcarAsistenciaUseCase();
      final match = await useCase.identificarEmpleado(vector);

      if (match == null) {
        throw Exception('Empleado no reconocido.');
      }

      final db = DatabaseHelper();
      final incapacidad = await db.getIncapacidadActivaByCedula(
        match.empleado.cedula,
      );
      if (incapacidad != null) {
        throw Exception(
          'El colaborador tiene una incapacidad activa registrada hoy.',
        );
      }

      // 4. Cargar historial de hoy
      final registrosHoy = await useCase.getRegistrosDeHoy(
        match.empleado.cedula,
      );

      // --- Ejecutar prueba de vida (Liveness) inmediatamente después de identificar ---
      final pasoLiveness = await _ejecutarPruebaDeVida(
        match.empleado,
        match.distancia,
      );
      if (!pasoLiveness) return;

      if (mounted) {
        setState(() {
          _procesando = false;
          _empleadoIdentificado = match.empleado;
          _distanciaMatch = match.distancia;
          _registrosHoy = registrosHoy;
          _mostrarPanelSeleccion = true;

          _state = _AppState(
            procesando: false,
            mensaje: 'Rostro Identificado. Selecciona tu registro hoy:',
            mensajeColor: AppColors.secondary,
            empleadoNombre: match.empleado.nombre,
            empleadoCedula: match.empleado.cedula,
            distancia: match.distancia,
          );
        });
      }

      // Temporizador de Kiosko: Si el empleado se va sin presionar ningún botón,
      // limpiamos el estado automáticamente después de 15 segundos.
      Future.delayed(const Duration(seconds: 15)).then((_) {
        if (mounted &&
            _mostrarPanelSeleccion &&
            _empleadoIdentificado?.cedula == match.empleado.cedula &&
            !_procesando) {
          _cancelarFlujoMarcacion();
        }
      });
    } catch (e) {
      final cleanErr = e.toString().replaceAll('Exception: ', '');
      _speak('Error. $cleanErr');
      if (mounted) {
        setState(() {
          _capturedImage = null;
          _state = _AppState(
            procesando: false,
            mensaje: 'Error: $cleanErr',
            mensajeColor: AppColors.error,
          );
        });
      }

      // Auto-limpieza tras error
      await Future.delayed(const Duration(seconds: 4));
      if (mounted && !_mostrarPanelSeleccion) {
        _cancelarFlujoMarcacion();
      }
    }
  }

  Future<void> _intentarSalirAlHome() async {
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool obscurePassword = true;
    bool validando = false;
    String? dialogError;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: AppColors.primaryLight,
          title: const Text(
            'Acceso Administrativo',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Ingresa tu contraseña para volver al panel de administración:',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  style: const TextStyle(color: Colors.black),
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    labelStyle: const TextStyle(color: Colors.black),
                    prefixIcon: const Icon(
                      Icons.lock_outline,
                      color: Colors.black,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.black,
                      ),
                      onPressed: () {
                        setStateDialog(() {
                          obscurePassword = !obscurePassword;
                        });
                      },
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.secondary),
                    ),
                  ),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Ingresa tu contraseña' : null,
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    dialogError!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: validando ? null : () => Navigator.pop(context),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
              ),
              onPressed: validando
                  ? null
                  : () async {
                      Navigator.pop(context);
                      context.go(AppRoutes.home);
                      // if (formKey.currentState!.validate()) {
                      //   setStateDialog(() {
                      //     validando = true;
                      //     dialogError = null;
                      //   });

                      //   try {
                      //     final prefs = await SharedPreferences.getInstance();
                      //     final usuario = prefs.getString('auth_usuario') ?? '';
                      //     final empresa = prefs.getString('auth_empresa_id') ?? '';
                      //     final pass = passwordController.text;

                      //     final result = await login(
                      //       usuario: usuario,
                      //       contra: pass,
                      //       empresa: empresa,
                      //       idAs: 'U100',
                      //     );

                      //     if (result == '') {
                      //       if (context.mounted) {
                      //         Navigator.pop(context);
                      //         context.go(AppRoutes.home);
                      //       }
                      //     } else {
                      //       setStateDialog(() {
                      //         validando = false;
                      //         dialogError = result;
                      //       });
                      //     }
                      //   } catch (e) {
                      //     setStateDialog(() {
                      //       validando = false;
                      //       dialogError = 'Error: $e';
                      //     });
                      //   }
                      // }
                    },
              child: validando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Ingresar',
                      style: TextStyle(color: Colors.white),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _mostrarDialogoMarcacionOffline() async {
    final cedulaController = TextEditingController();
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool obscurePassword = true;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: AppColors.primaryLight,
          title: const Text(
            'Marcación Offline',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Ingresa tu número de Cédula y la contraseña del operador logueado para marcar asistencia:',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: cedulaController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.black),
                  decoration: const InputDecoration(
                    labelText: 'Número de Cédula',
                    labelStyle: TextStyle(color: Colors.black),
                    prefixIcon: Icon(Icons.badge_outlined, color: Colors.black),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.secondary),
                    ),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Ingresa la cédula'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  style: const TextStyle(color: Colors.black),
                  decoration: InputDecoration(
                    labelText: 'Contraseña del Operador',
                    labelStyle: const TextStyle(color: Colors.black),
                    prefixIcon: const Icon(
                      Icons.lock_outline,
                      color: Colors.black,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.black,
                      ),
                      onPressed: () {
                        setStateDialog(() {
                          obscurePassword = !obscurePassword;
                        });
                      },
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.secondary),
                    ),
                  ),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Ingresa la contraseña' : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
              ),
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final cedula = cedulaController.text.trim();
                  final pass = passwordController.text;

                  // Verificar contraseña del operador logueado
                  final db = DatabaseHelper();
                  final prefs = await SharedPreferences.getInstance();
                  final operatorUser = prefs.getString('user_name') ?? '';

                  final user = await db.getUsuario(operatorUser, pass);
                  if (user == null) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Contraseña de operador incorrecta.'),
                          backgroundColor: AppColors.error,
                        ),
                      );
                    }
                    return;
                  }

                  if (context.mounted) {
                    Navigator.pop(context); // Cerrar diálogo
                    await _identificarEmpleadoOffline(cedula);
                  }
                }
              },
              child: const Text(
                'Aceptar',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _identificarEmpleadoOffline(String cedula) async {
    setState(() {
      _procesando = true;
      _capturedImage = null;
      _empleadoIdentificado = null;
      _distanciaMatch = null;
      _mostrarPanelSeleccion = false;
      _esMarcadoCedula = true;
      _state = const _AppState(
        procesando: true,
        mensaje: 'Verificando cédula local...',
        mensajeColor: AppColors.primary,
      );
    });

    try {
      final db = DatabaseHelper();
      final empleado = await db.getEmpleadoByCedula(cedula);

      if (empleado == null) {
        throw Exception('Cédula no registrada en este dispositivo.');
      }

      if (empleado.estado != 'ACTIVO') {
        throw Exception(
          'El empleado correspondiente a esta cédula se encuentra INACTIVO.',
        );
      }

      final incapacidad = await db.getIncapacidadActivaByCedula(cedula);
      if (incapacidad != null) {
        throw Exception(
          'El colaborador tiene una incapacidad activa registrada hoy.',
        );
      }

      final useCase = MarcarAsistenciaUseCase();
      final registrosHoy = await useCase.getRegistrosDeHoy(cedula);

      // --- Para marcación por cédula, omitimos la prueba de vida (Liveness) y pasamos directo ---
      if (mounted) {
        setState(() {
          _procesando = false;
          _empleadoIdentificado = empleado;
          _distanciaMatch = null;
          _registrosHoy = registrosHoy;
          _mostrarPanelSeleccion = true;

          _state = _AppState(
            procesando: false,
            mensaje: 'Cédula Identificada. Selecciona tu registro hoy:',
            mensajeColor: AppColors.secondary,
            empleadoNombre: empleado.nombre,
            empleadoCedula: empleado.cedula,
          );
        });
      }

      // Temporizador de Kiosko: 15 segundos
      Future.delayed(const Duration(seconds: 15)).then((_) {
        if (mounted &&
            _mostrarPanelSeleccion &&
            _empleadoIdentificado?.cedula == cedula &&
            !_procesando) {
          _cancelarFlujoMarcacion();
        }
      });
    } catch (e) {
      final cleanErr = e.toString().replaceAll('Exception: ', '');
      _speak('Error. $cleanErr');
      if (mounted) {
        setState(() {
          _state = _AppState(
            procesando: false,
            mensaje: 'Error: $cleanErr',
            mensajeColor: AppColors.error,
          );
        });
      }

      await Future.delayed(const Duration(seconds: 4));
      if (mounted && !_mostrarPanelSeleccion) {
        _cancelarFlujoMarcacion();
      }
    }
  }

  /// Ejecuta la prueba de vida (Liveness) detectando el movimiento de cabeza (rotación lateral).
  Future<bool> _ejecutarPruebaDeVida(
    EmpleadoModel empleado,
    double? distancia,
  ) async {
    if (_cameraController == null || !_isCameraInitialized) {
      return true;
    }

    setState(() {
      _capturedImage =
          null; // Liberamos la imagen estática para reactivar la cámara
      _procesando = true;
      _state = _AppState(
        procesando: true,
        mensaje: '¡VALIDANDO VIDA! GIRE LA CABEZA A LOS LADOS',
        mensajeColor: AppColors.secondary,
        empleadoNombre: empleado.nombre,
        empleadoCedula: empleado.cedula,
        distancia: distancia,
      );
    });
    _speak('Por favor, gire la cabeza levemente hacia los lados');

    List<XFile> rafagaFotos = [];
    List<double> headYRotations = [];

    try {
      // 1. Ejecutar ráfaga optimizada de 4 capturas rápidas
      await Future.delayed(const Duration(milliseconds: 150));
      rafagaFotos.add(await _cameraController!.takePicture());

      await Future.delayed(const Duration(milliseconds: 150));
      rafagaFotos.add(await _cameraController!.takePicture());

      await Future.delayed(const Duration(milliseconds: 150));
      rafagaFotos.add(await _cameraController!.takePicture());

      await Future.delayed(const Duration(milliseconds: 150));
      rafagaFotos.add(await _cameraController!.takePicture());

      if (mounted) {
        setState(() {
          _state = _AppState(
            procesando: true,
            mensaje: 'Procesando prueba de vida local...',
            mensajeColor: AppColors.info,
            empleadoNombre: empleado.nombre,
            empleadoCedula: empleado.cedula,
            distancia: distancia,
          );
        });
      }

      // 2. Procesar cada foto localmente
      for (final img in rafagaFotos) {
        final inputImage = InputImage.fromFilePath(img.path);
        final faces = await _faceDetector.processImage(inputImage);

        if (faces.isNotEmpty) {
          final face = faces.first;
          final rotY = face.headEulerAngleY;

          if (rotY != null) {
            headYRotations.add(rotY);
          } else {
            headYRotations.add(0.0);
          }
        } else {
          // Ignorar silenciosamente fotos borrosas en ráfaga rápida
          // para no tumbar la validación si al menos hay datos de otras fotos
          headYRotations.add(0.0);
        }
      }

      // 3. Evaluar variación del ángulo de giro lateral de cabeza
      double maxRot = -180.0;
      double minRot = 180.0;
      for (final rot in headYRotations) {
        if (rot > maxRot) maxRot = rot;
        if (rot < minRot) minRot = rot;
      }

      final deltaRot = maxRot - minRot;

      // Requerimos que la variación del giro sea de al menos 10 grados para confirmar movimiento real
      final esHumanoVivo = deltaRot >= 10.0;

      debugPrint('=== PRUEBA DE VIDA (MOVIMIENTO DE CABEZA) ===');
      debugPrint('Rotaciones de cabeza (Grados Y): $headYRotations');
      debugPrint('Rotación Máxima: ${maxRot.toStringAsFixed(1)}°');
      debugPrint('Rotación Mínima: ${minRot.toStringAsFixed(1)}°');
      debugPrint('Diferencia de Giro (Delta): ${deltaRot.toStringAsFixed(1)}°');
      debugPrint('Resultado - ¿Humano Vivo?: $esHumanoVivo');
      debugPrint('=============================================');

      // Eliminar fotos temporales de ráfaga
      for (final img in rafagaFotos) {
        try {
          final f = File(img.path);
          if (await f.exists()) {
            await f.delete();
          }
        } catch (_) {}
      }

      // 4. Si falla la prueba de vida (Rostro Estático)
      if (!esHumanoVivo) {
        setState(() {
          _procesando = false;
          _state = _AppState(
            procesando: false,
            mensaje: 'FALLO: ROSTRO ESTÁTICO DETECTADO.',
            mensajeColor: AppColors.error,
            empleadoNombre: empleado.nombre,
            empleadoCedula: empleado.cedula,
            distancia: distancia,
          );
        });
        _speak('Movimiento no detectado. Por favor, gire la cabeza.');

        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '⚠️ Seguridad: Gire levemente la cabeza a los lados para marcar asistencia.',
            ),
            backgroundColor: AppColors.error,
            duration: Duration(seconds: 4),
          ),
        );

        await Future.delayed(const Duration(seconds: 4));
        if (mounted) {
          _cancelarFlujoMarcacion();
        }
        return false;
      }

      return true;
    } catch (e) {
      // Limpieza de fotos en caso de excepción
      for (final img in rafagaFotos) {
        try {
          final f = File(img.path);
          if (await f.exists()) {
            await f.delete();
          }
        } catch (_) {}
      }

      final cleanErr = e.toString().replaceAll('Exception: ', '');
      _speak('Error. $cleanErr');
      if (mounted) {
        setState(() {
          _procesando = false;
          _state = _AppState(
            procesando: false,
            mensaje: 'Error: $cleanErr',
            mensajeColor: AppColors.error,
            empleadoNombre: empleado.nombre,
            empleadoCedula: empleado.cedula,
            distancia: distancia,
          );
        });
      }
      return false;
    }
  }

  /// FASE 2: Registra el marcado de asistencia con la opción seleccionada manualmente por el usuario.
  Future<void> _registrarMarcacionManual(TipoRegistro tipoSeleccionado) async {
    if (_empleadoIdentificado == null || _procesando) return;

    // Si es tipo Permiso, primero validamos de inmediato en SQLite local que el permiso exista.
    // Si no existe, rechazamos rápido sin necesidad de hacer parpadear al usuario.
    if (tipoSeleccionado == TipoRegistro.permiso) {
      final db = DatabaseHelper();
      final permiso = await db.getPermisoActivoByCedula(
        _empleadoIdentificado!.cedula,
      );
      if (permiso == null) {
        setState(() {
          _state = _AppState(
            procesando: false,
            mensaje:
                'No hay permiso autorizado registrado hoy para este usuario.',
            mensajeColor: AppColors.error,
            empleadoNombre: _empleadoIdentificado!.nombre,
            empleadoCedula: _empleadoIdentificado!.cedula,
            distancia: _distanciaMatch,
          );
        });
        _speak(
          'Error. No hay permiso autorizado registrado hoy para este usuario.',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Registro Inválido: No hay permiso autorizado registrado hoy para este usuario.',
            ),
            backgroundColor: AppColors.error,
            duration: Duration(seconds: 3500 ~/ 1000),
          ),
        );
        return;
      }
    }

    setState(() {
      _procesando = true;
      _state = _AppState(
        procesando: true,
        mensaje: 'Registrando marcación...',
        mensajeColor: AppColors.info,
        empleadoNombre: _empleadoIdentificado!.nombre,
        empleadoCedula: _empleadoIdentificado!.cedula,
        distancia: _distanciaMatch,
      );
    });

    try {
      final useCase = MarcarAsistenciaUseCase();
      if (_empleadoIdentificado == null) {
        debugPrint(
          '[Asistencia] El flujo fue cancelado o desidentificado antes de registrar.',
        );
        return;
      }
      final result = await useCase.registrarMarcadoManual(
        empleado: _empleadoIdentificado!,
        tipoSeleccionado: tipoSeleccionado,
        distancia: _distanciaMatch,
        metodoRegistro: _esMarcadoCedula ? 'CEDULA' : 'FACIAL',
      );

      if (!mounted) return;

      if (result.hasError) {
        // En caso de error de secuencia de hoy, mostramos SnackBar rojo
        setState(() {
          _procesando = false;
          _state = _AppState(
            procesando: false,
            mensaje: result.mensaje,
            mensajeColor: AppColors.error,
            empleadoNombre: _empleadoIdentificado?.nombre ?? '',
            empleadoCedula: _empleadoIdentificado?.cedula ?? '',
            distancia: _distanciaMatch,
          );
        });
        _speak('Error. ${result.mensaje}');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.mensaje),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        // Éxito: Determinar color según tipo
        Color color = AppColors.success;
        switch (result.tipoRegistro) {
          case TipoRegistro.normal:
            color = AppColors.success;
            break;
          case TipoRegistro.retardo:
            color = AppColors.colorRetardo;
            break;
          case TipoRegistro.almuerzo:
            color = AppColors.colorAlmuerzo;
            break;
          case TipoRegistro.salida:
            color = AppColors.colorSalida;
            break;
          case TipoRegistro.permiso:
            color = AppColors.colorPermiso;
            break;
          case TipoRegistro.extras:
            color = AppColors.colorExtras;
            break;
          default:
            color = AppColors.success;
        }

        setState(() {
          _procesando = false;
          _mostrarPanelSeleccion =
              false; // Ocultar panel de selección para éxito final
          _state = _AppState(
            procesando: false,
            mensaje: result.mensaje,
            mensajeColor: color,
            empleadoNombre: result.empleadoNombre,
            empleadoCedula: result.empleadoCedula,
            tipoRegistro: result.tipoRegistro,
            distancia: result.distancia,
          );
        });
        _speak('${result.empleadoNombre}. ${result.mensaje}');

        // Intentar sincronización inmediata en segundo plano
        context.read<SyncService>().syncAll();

        // Esperar 4 segundos y re-inicializar el Kiosko
        await Future.delayed(
          const Duration(seconds: AppConstants.resultDisplaySeconds),
        );
        if (mounted) {
          _cancelarFlujoMarcacion();
        }
      }
    } catch (e) {
      final cleanErr = e.toString().replaceAll('Exception: ', '');
      _speak('Error. $cleanErr');
      if (mounted) {
        setState(() {
          _procesando = false;
          _state = _AppState(
            procesando: false,
            mensaje: 'Error: $cleanErr',
            mensajeColor: AppColors.error,
            empleadoNombre: _empleadoIdentificado?.nombre,
            empleadoCedula: _empleadoIdentificado?.cedula,
            distancia: _distanciaMatch,
          );
        });
      }
    }
  }

  /// Limpia todos los estados y vuelve a encender la previsualización de la cámara frontal.
  void _cancelarFlujoMarcacion() {
    if (!mounted) return;
    setState(() {
      _capturedImage = null;
      _empleadoIdentificado = null;
      _distanciaMatch = null;
      _registrosHoy = [];
      _mostrarPanelSeleccion = false;
      _procesando = false;
      _state = const _AppState(
        procesando: false,
        mensaje: 'Listo para escanear',
        mensajeColor: Colors.white70,
      );
    });
  }

  /// Método legado de depuración offline (simula el paso de identificación)
  Future<void> procesarVector(List<double> vectorDetectado) async {
    if (_procesando) return;
    setState(() {
      _procesando = true;
      _state = const _AppState(
        procesando: true,
        mensaje: 'Buscando coincidencia (Debug)...',
        mensajeColor: AppColors.info,
      );
    });

    try {
      final useCase = MarcarAsistenciaUseCase();
      final match = await useCase.identificarEmpleado(vectorDetectado);

      if (match == null) {
        throw Exception('Empleado no reconocido.');
      }

      final registrosHoy = await useCase.getRegistrosDeHoy(
        match.empleado.cedula,
      );

      if (mounted) {
        setState(() {
          _procesando = false;
          _empleadoIdentificado = match.empleado;
          _distanciaMatch = match.distancia;
          _registrosHoy = registrosHoy;
          _mostrarPanelSeleccion = true;

          _state = _AppState(
            procesando: false,
            mensaje: 'Identificado (Debug). Selecciona tu registro:',
            mensajeColor: AppColors.secondary,
            empleadoNombre: match.empleado.nombre,
            empleadoCedula: match.empleado.cedula,
            distancia: match.distancia,
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _AppState(
            procesando: false,
            mensaje: 'Error debug: $e',
            mensajeColor: AppColors.error,
          );
        });
      }
    }
  }

  /// Simulación interactiva: obtiene un empleado de SQLite y le añade ruido al vector
  /// para emular una detección de cámara real.
  Future<void> _simularEscaneoFacial() async {
    final db = DatabaseHelper();
    final empleados = await db.getAllEmpleados();

    if (!mounted) return;

    if (empleados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No hay empleados en base de datos. Crea uno en la sección "Empleados".',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Buscar alguno que tenga vector registrado
    final conVector = empleados
        .where((e) => e.mapaVectorFoto.isNotEmpty)
        .toList();
    if (conVector.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ninguno de los empleados tiene rostro enrolado. Por favor, edita o registra uno con foto.',
          ),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    // Seleccionar aleatorio
    final emp = conVector[Random().nextInt(conVector.length)];

    // Simular vector con pequeña variación (ruido euclidiano leve < 0.1)
    final vectorSimulado = emp.mapaVectorFoto.map((v) {
      final ruido = (Random().nextDouble() - 0.5) * 0.04;
      return (v + ruido).clamp(-1.0, 1.0);
    }).toList();

    await procesarVector(vectorSimulado);
  }

  String _getTipoRegistroLabel(TipoRegistro tipo) {
    switch (tipo) {
      case TipoRegistro.normal:
        return 'ENTRADA NORMAL';
      case TipoRegistro.retardo:
        return 'RETARDO REGISTRADO';
      case TipoRegistro.almuerzo:
        return 'REGISTRO DE ALMUERZO';
      case TipoRegistro.salida:
        return 'SALIDA REGISTRADA';
      case TipoRegistro.permiso:
        return 'PERMISO AUTORIZADO';
      case TipoRegistro.extras:
        return 'HORAS EXTRAS';
      case TipoRegistro.noRegistrar:
        return 'REGISTRO RECHAZADO';
    }
  }

  Widget _buildBotonPanel({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    final isDisabled = onPressed == null;
    return Opacity(
      opacity: isDisabled ? 0.35 : 1.0,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: isDisabled ? 0 : 4,
          textStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    // --- ELEMENTOS COMPARTIDOS ---

    // 1. Reloj / Fecha
    Widget buildClockSection() {
      return StreamBuilder<DateTime>(
        stream: _clockStream,
        builder: (context, snap) {
          final now = snap.data ?? DateTime.now();
          return Container(
            padding: EdgeInsets.symmetric(vertical: isLandscape ? 12 : 24),
            child: Column(
              children: [
                Text(
                  DateFormat('HH:mm:ss').format(now),
                  style: TextStyle(
                    fontSize: isLandscape ? 36 : 64,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat(
                    'EEEE, d \'de\' MMMM \'de\' yyyy',
                    'es',
                  ).format(now).toUpperCase(),
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: isLandscape ? 11 : 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    // 2. Panel de Información (Izquierda en Landscape / Abajo en Portrait)
    Widget buildInfoPanel() {
      final hasIdentified =
          _mostrarPanelSeleccion && _empleadoIdentificado != null;
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: _state.mensajeColor.withValues(
            alpha: isLandscape ? 0.0 : 0.12,
          ),
          borderRadius: isLandscape ? BorderRadius.circular(16) : null,
          border: isLandscape
              ? Border.all(color: _state.mensajeColor.withValues(alpha: 0.15))
              : Border(
                  top: BorderSide(
                    color: _state.mensajeColor.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: hasIdentified
            ? Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '¡ROSTRO IDENTIFICADO!'.toUpperCase(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _state.mensajeColor,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _empleadoIdentificado!.nombre,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'CÉDULA: ${_empleadoIdentificado!.cedula}',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const SizedBox(height: 18),

                  // Estado de la secuencia actual (Ayuda visual)
                  Builder(
                    builder: (context) {
                      final yaTieneEntrada = _registrosHoy.any(
                        (r) =>
                            r.evento == 'ENTRADA' &&
                            (r.tipo == 'NORMAL' ||
                                r.tipo == 'RETARDO' ||
                                r.tipo == 'PERMISO'),
                      );
                      final yaTieneSalida = _registrosHoy.any(
                        (r) =>
                            r.evento == 'SALIDA' &&
                            (r.tipo == 'SALIDA' || r.tipo == 'PERMISO'),
                      );

                      String statusText = 'Secuencia: Esperando Entrada';
                      if (yaTieneEntrada)
                        statusText = 'Secuencia: Dentro / Esperando Salida';
                      if (yaTieneSalida)
                        statusText = 'Secuencia: Jornada Finalizada';

                      return Text(
                        statusText,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      );
                    },
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_state.procesando) ...[
                    const CircularProgressIndicator(color: AppColors.info),
                    const SizedBox(height: 16),
                  ] else ...[
                    Icon(
                      _state.empleadoNombre != null
                          ? Icons.check_circle_outline
                          : Icons.sensors_rounded,
                      size: 48,
                      color: _state.mensajeColor,
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    _state.mensaje.toUpperCase(),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _state.mensajeColor,
                      letterSpacing: 1.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_state.empleadoNombre != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _state.empleadoNombre!,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'CÉDULA DE CIUDADANÍA: ${_state.empleadoCedula}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (_state.tipoRegistro != null) ...[
                      const SizedBox(height: 12),
                      Chip(
                        backgroundColor: _state.mensajeColor.withValues(
                          alpha: 0.25,
                        ),
                        label: Text(
                          _getTipoRegistroLabel(_state.tipoRegistro!),
                          style: TextStyle(
                            color: _state.mensajeColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        side: BorderSide(color: _state.mensajeColor),
                      ),
                    ],
                    if (_state.distancia != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Precisión facial: ${(100 - _state.distancia! * 100).toStringAsFixed(1)}% (dist. ${_state.distancia!.toStringAsFixed(3)})',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
      );
    }

    // 3. Panel de Opciones/Botones (Derecha en Landscape / Abajo en Portrait)
    Widget buildOptionsPanel() {
      final hasIdentified =
          _mostrarPanelSeleccion && _empleadoIdentificado != null;
      if (hasIdentified) {
        final yaTieneEntrada = _registrosHoy.any(
          (r) =>
              r.evento == 'ENTRADA' &&
              (r.tipo == 'NORMAL' ||
                  r.tipo == 'RETARDO' ||
                  r.tipo == 'PERMISO'),
        );
        final yaTieneSalida = _registrosHoy.any(
          (r) =>
              r.evento == 'SALIDA' &&
              (r.tipo == 'SALIDA' || r.tipo == 'PERMISO'),
        );

        return Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              direction: isLandscape ? Axis.vertical : Axis.horizontal,
              children: [
                SizedBox(
                  width: isLandscape ? 160 : null,
                  child: _buildBotonPanel(
                    label: 'ENTRADA',
                    icon: Icons.login_rounded,
                    color: Colors.green,
                    onPressed: (yaTieneEntrada || _procesando)
                        ? null
                        : () => _registrarMarcacionManual(TipoRegistro.normal),
                  ),
                ),
                SizedBox(
                  width: isLandscape ? 160 : null,
                  child: _buildBotonPanel(
                    label: 'SALIDA',
                    icon: Icons.logout_rounded,
                    color: Colors.red,
                    onPressed: (!yaTieneEntrada || yaTieneSalida || _procesando)
                        ? null
                        : () => _registrarMarcacionManual(TipoRegistro.salida),
                  ),
                ),
                SizedBox(
                  width: isLandscape ? 160 : null,
                  child: _buildBotonPanel(
                    label: 'PERMISO',
                    icon: Icons.card_membership_rounded,
                    color: Colors.purple,
                    onPressed: _procesando
                        ? null
                        : () => _registrarMarcacionManual(TipoRegistro.permiso),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _procesando ? null : _cancelarFlujoMarcacion,
              icon: const Icon(
                Icons.cancel_outlined,
                color: Colors.white54,
                size: 16,
              ),
              label: const Text(
                'No soy yo, Cancelar',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ],
        );
      } else {
        if (isLandscape && !_procesando) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: (!_isCameraInitialized)
                    ? null
                    : _marcarAsistenciaReal,
                icon: const Icon(Icons.face_unlock_rounded),
                label: const Text('MARCAR CON ROSTRO'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 8,
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
              if (_permitirManual) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _mostrarDialogoMarcacionOffline,
                  icon: const Icon(
                    Icons.keyboard_alt_outlined,
                    color: Colors.white70,
                  ),
                  label: const Text('MARCAR CON CÉDULA'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24, width: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ],
          );
        }
        return const SizedBox.shrink();
      }
    }

    // 4. El Contenedor de la Cámara / Foto
    Widget buildCameraBox() {
      return Container(
        width: isLandscape ? 480 : MediaQuery.sizeOf(context).width * 0.9,
        height: isLandscape ? 480 : null,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.kioskSurface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white24, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_isCameraInitialized &&
                  _cameraController != null &&
                  _capturedImage == null)
                Positioned.fill(
                  child: AspectRatio(
                    aspectRatio: _cameraController!.value.aspectRatio,
                    child: CameraPreview(_cameraController!),
                  ),
                ),
              if (_capturedImage != null)
                Positioned.fill(
                  child: Image.file(
                    File(_capturedImage!.path),
                    fit: BoxFit.cover,
                  ),
                ),
              if (!_isCameraInitialized && _capturedImage == null)
                const Positioned.fill(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.videocam_off_outlined,
                        size: 80,
                        color: Colors.white10,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'CÁMARA INICIALIZANDO...',
                        style: TextStyle(
                          color: Colors.white30,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_isCameraInitialized &&
                  _cameraController != null &&
                  _capturedImage == null &&
                  !_procesando)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColors.secondary.withValues(alpha: 0.3),
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Center(
                      child: Container(
                        width: isLandscape ? 200 : 180,
                        height: isLandscape ? 200 : 180,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppColors.secondary.withValues(alpha: 0.7),
                            width: 2,
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              // Control manual de brillo flotante sobre la cámara
              if (_isCameraInitialized &&
                  _cameraController != null &&
                  _capturedImage == null &&
                  !_procesando &&
                  _supportsExposureOffset)
                Positioned(
                  bottom: isLandscape ? 12 : 80,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.brightness_low, color: Colors.white70, size: 18),
                        Expanded(
                          child: Slider(
                            value: _currentExposureOffset,
                            min: _minExposureOffset,
                            max: _maxExposureOffset,
                            activeColor: AppColors.secondary,
                            inactiveColor: Colors.white24,
                            onChanged: (value) async {
                              setState(() {
                                _currentExposureOffset = value;
                              });
                              try {
                                await _cameraController!.setExposureOffset(value);
                              } catch (e) {
                                debugPrint("Error cambiando exposición manual: $e");
                              }
                            },
                          ),
                        ),
                        const Icon(Icons.brightness_high, color: Colors.white70, size: 18),
                      ],
                    ),
                  ),
                ),
              if (_procesando)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.secondary.withValues(alpha: 0.0),
                          AppColors.secondary.withValues(alpha: 0.1),
                          AppColors.secondary.withValues(alpha: 0.3),
                          AppColors.secondary.withValues(alpha: 0.1),
                          AppColors.secondary.withValues(alpha: 0.0),
                        ],
                        stops: const [0.0, 0.4, 0.5, 0.6, 1.0],
                      ),
                    ),
                  ),
                ),
              if (_procesando && _state.mensaje.contains('PARPADEA'))
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.75),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            const SizedBox(
                              width: 90,
                              height: 90,
                              child: CircularProgressIndicator(
                                strokeWidth: 4,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.secondaryLight,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.remove_red_eye_rounded,
                              size: 48,
                              color: AppColors.secondaryLight,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '¡PRUEBA DE SEGURIDAD!',
                          style: TextStyle(
                            color: AppColors.secondaryLight,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '👀 ¡PARPADEE! 👀',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                blurRadius: 15,
                                color: AppColors.secondary,
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              if (!isLandscape && !_mostrarPanelSeleccion && !_procesando)
                Positioned(
                  bottom: 24,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton.icon(
                        onPressed: (!_isCameraInitialized)
                            ? null
                            : _marcarAsistenciaReal,
                        icon: const Icon(Icons.face_unlock_rounded),
                        label: const Text('MARCAR CON ROSTRO'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.secondary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 30,
                            vertical: 20,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 8,
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (_permitirManual) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _mostrarDialogoMarcacionOffline,
                          icon: const Icon(
                            Icons.keyboard_alt_outlined,
                            color: Colors.white70,
                            size: 16,
                          ),
                          label: const Text('MARCAR CON CÉDULA (OFFLINE)'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(
                              color: Colors.white24,
                              width: 1.5,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // --- CONSTRUCCIÓN DEL LAYOUT ADAPTATIVO ---

    final mainContent = isLandscape
        ? Scaffold(
            backgroundColor: AppColors.kioskBackground,
            appBar: AppBar(
              title: const Text('Tótem de Asistencia'),
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: _userRole == 'ADMIN'
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: _intentarSalirAlHome,
                    )
                  : IconButton(
                      icon: const Icon(Icons.exit_to_app, color: Colors.white),
                      tooltip: 'Salir de la aplicación',
                      onPressed: () => SystemNavigator.pop(),
                    ),
              actions: [
                IconButton(
                  icon: const Icon(
                    Icons.psychology_outlined,
                    color: Colors.white30,
                  ),
                  tooltip: 'Simular marcación (Offline Debug)',
                  onPressed: _procesando ? null : _simularEscaneoFacial,
                ),
              ],
            ),
            body: SafeArea(
              child: Column(
                children: [
                  buildClockSection(),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        children: [
                          // Lado izquierdo: Mensajes de estado e info
                          Expanded(
                            flex: 4,
                            child: Center(
                              child: SingleChildScrollView(
                                child: buildInfoPanel(),
                              ),
                            ),
                          ),
                          // Centro: Caja de la cámara / Foto
                          Center(child: buildCameraBox()),
                          // Lado derecho: Botones de Entrada/Salida u Opciones
                          Expanded(
                            flex: 4,
                            child: Center(
                              child: SingleChildScrollView(
                                child: buildOptionsPanel(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          )
        : Scaffold(
            backgroundColor: AppColors.kioskBackground,
            appBar: AppBar(
              title: const Text('Tótem de Asistencia'),
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: _userRole == 'ADMIN'
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: _intentarSalirAlHome,
                    )
                  : IconButton(
                      icon: const Icon(Icons.exit_to_app, color: Colors.white),
                      tooltip: 'Salir de la aplicación',
                      onPressed: () => SystemNavigator.pop(),
                    ),
            ),
            body: Column(
              children: [
                buildClockSection(),
                Expanded(child: Center(child: buildCameraBox())),
                const SizedBox(height: 16),
                buildInfoPanel(),
                buildOptionsPanel(),
                const SizedBox(height: 16),
              ],
            ),
          );

    return WillPopScope(
      onWillPop: () async {
        if (_userRole != 'ADMIN') {
          await SystemNavigator.pop();
          return false;
        }
        await _intentarSalirAlHome();
        return false;
      },
      child: mainContent,
    );
  }
}
