import '../../core/constants/app_constants.dart';
import '../../core/utils/face_matcher.dart';
import '../../core/utils/horario_validator.dart';
import '../../data/datasources/local/database_helper.dart';
import '../../data/models/registro_model.dart';
import '../../data/models/empleado_model.dart';

/// Marca asistencia de forma OFFLINE:
/// 1. Recibe el vector facial detectado por ML Kit en el dispositivo.
/// 2. Busca el mejor match entre todos los empleados almacenados.
/// 3. Valida horario / permisos.
/// 4. Guarda el registro en SQLite con sincronizado=0.
class MarcarAsistenciaUseCase {
  final DatabaseHelper _db;

  MarcarAsistenciaUseCase({DatabaseHelper? db}) : _db = db ?? DatabaseHelper();

  /// FASE 1: Identificación Facial
  /// Busca el mejor match biométrico en SQLite local.
  /// Retorna al empleado y su precisión si supera el umbral, o nulo si no es reconocido.
  Future<({EmpleadoModel empleado, double distancia})?> identificarEmpleado(List<double> vectorDetectado) async {
    if (vectorDetectado.isEmpty) return null;

    final all = await _db.getAllEmpleados();
    final empleados = all.where((e) => e.estado == 'ACTIVO').toList();
    if (empleados.isEmpty) return null;

    final umbralStr = await _db.getConfig('umbral_facial') ?? '0.6';
    final umbral = double.tryParse(umbralStr) ?? AppConstants.faceMatchThreshold;
    
    final vectors = empleados.map((e) => e.mapaVectorFoto).toList();
    final match = FaceMatcher.findBestMatch(vectorDetectado, vectors, threshold: umbral);

    if (match == null) return null;
    return (empleado: empleados[match.index], distancia: match.distance);
  }

  /// Recupera todos los registros de asistencia del empleado para el día de hoy.
  Future<List<RegistroModel>> getRegistrosDeHoy(String cedula) async {
    final registros = await _db.getRegistrosPorCedula(cedula);
    final hoy = DateTime.now().toIso8601String().substring(0, 10);
    return registros.where((r) => r.fechaHora.startsWith(hoy)).toList();
  }

  /// FASE 2: Registro Manual con Validación de Secuencia y Permisos
  /// Registra de forma definitiva la acción seleccionada en SQLite local.
  Future<MarcarAsistenciaResult> registrarMarcadoManual({
    required EmpleadoModel empleado,
    required TipoRegistro tipoSeleccionado,
    double? distancia,
  }) async {
    final ahora = DateTime.now();
    final registrosHoy = await getRegistrosDeHoy(empleado.cedula);

    String evento = AppConstants.eventoEntrada;
    String descripcion = '';

    // ─── VALIDACIÓN ESPECIAL: 🟣 PERMISO ─────────────────────────────
    if (tipoSeleccionado == TipoRegistro.permiso) {
      final permiso = await _db.getPermisoActivoByCedula(empleado.cedula);
      if (permiso == null) {
        return MarcarAsistenciaResult.error('No hay permiso autorizado registrado hoy para este usuario.');
      }
      
      // Si tiene permiso, determinamos evento según registros de hoy
      final yaTieneEntrada = registrosHoy.any((r) => r.evento == AppConstants.eventoEntrada);
      evento = yaTieneEntrada ? AppConstants.eventoSalida : AppConstants.eventoEntrada;
      descripcion = 'Marcación por Permiso Autorizado registrada con éxito.';
    } 
    // ─── VALIDACIONES DE SECUENCIA DIARIA COMÚN ─────────────────────
    else {
      final yaTieneEntrada = registrosHoy.any((r) => r.tipo == TipoRegistro.normal.name.toUpperCase() || 
                                                     r.tipo == TipoRegistro.retardo.name.toUpperCase());
      final yaTieneSalida = registrosHoy.any((r) => r.tipo == TipoRegistro.salida.name.toUpperCase());
      final yaTieneAlmuerzo = registrosHoy.any((r) => r.tipo == TipoRegistro.almuerzo.name.toUpperCase());

      switch (tipoSeleccionado) {
        case TipoRegistro.normal:
        case TipoRegistro.retardo:
          // Intentando marcar ENTRADA
          if (yaTieneEntrada) {
            return MarcarAsistenciaResult.error('Registro Inválido: Ya has registrado tu Entrada el día de hoy.');
          }
          evento = AppConstants.eventoEntrada;
          descripcion = '¡Bienvenido! Entrada registrada correctamente.';
          break;

        case TipoRegistro.almuerzo:
          // Intentando marcar ALMUERZO
          if (!yaTieneEntrada) {
            return MarcarAsistenciaResult.error('Registro Inválido: No puedes registrar Almuerzo sin antes registrar Entrada hoy.');
          }
          if (yaTieneSalida) {
            return MarcarAsistenciaResult.error('Registro Inválido: Ya has registrado la Salida de tu jornada hoy.');
          }
          evento = yaTieneAlmuerzo ? AppConstants.eventoEntrada : AppConstants.eventoSalida;
          descripcion = yaTieneAlmuerzo ? 'Retorno de almuerzo registrado.' : 'Salida a almuerzo registrada.';
          break;

        case TipoRegistro.salida:
          // Intentando marcar SALIDA
          if (!yaTieneEntrada) {
            return MarcarAsistenciaResult.error('Registro Inválido: No puedes registrar Salida sin antes haber marcado tu Entrada hoy.');
          }
          if (yaTieneSalida) {
            return MarcarAsistenciaResult.error('Registro Inválido: Ya has marcado tu Salida final por el día de hoy.');
          }
          evento = AppConstants.eventoSalida;
          descripcion = 'Salida de jornada registrada correctamente. ¡Hasta mañana!';
          break;

        case TipoRegistro.extras:
          // Extras se permite en cualquier momento como jornada extraordinaria
          evento = yaTieneEntrada ? AppConstants.eventoSalida : AppConstants.eventoEntrada;
          descripcion = 'Marcación de Horas Extras registrada correctamente.';
          break;

        default:
          return MarcarAsistenciaResult.error('Tipo de registro no soportado en marcado manual.');
      }
    }

    // Obtener unidad de negocio
    final unidad = await _db.getConfig('unidad_negocio') ?? 'Principal';

    // Crear modelo de registro
    final registro = RegistroModel(
      fechaHora: ahora.toIso8601String().substring(0, 19),
      cedula: empleado.cedula,
      evento: evento,
      tipo: tipoSeleccionado.name.toUpperCase(),
      unidadNegocio: unidad,
      sincronizado: false,
    );

    // Guardar en SQLite local
    await _db.insertRegistro(registro);

    return MarcarAsistenciaResult(
      registrado: true,
      mensaje: descripcion,
      empleadoNombre: empleado.nombre,
      empleadoCedula: empleado.cedula,
      tipoRegistro: tipoSeleccionado,
      distancia: distancia,
      registro: registro,
    );
  }

  /// Método legado de ejecución directa (por compatibilidad si es necesario)
  Future<MarcarAsistenciaResult> execute(List<double> vectorDetectado) async {
    final match = await identificarEmpleado(vectorDetectado);
    if (match == null) {
      return MarcarAsistenciaResult.error('Empleado no reconocido.');
    }
    
    // Fallback: Si se ejecuta directo, asume Entrada normal
    return registrarMarcadoManual(
      empleado: match.empleado,
      tipoSeleccionado: TipoRegistro.normal,
      distancia: match.distancia,
    );
  }
}

class MarcarAsistenciaResult {
  final bool registrado;
  final String mensaje;
  final String? empleadoNombre;
  final String? empleadoCedula;
  final TipoRegistro? tipoRegistro;
  final double? distancia;
  final RegistroModel? registro;
  final String? error;

  const MarcarAsistenciaResult({
    required this.registrado,
    required this.mensaje,
    this.empleadoNombre,
    this.empleadoCedula,
    this.tipoRegistro,
    this.distancia,
    this.registro,
    this.error,
  });

  factory MarcarAsistenciaResult.error(String error) => MarcarAsistenciaResult(
        registrado: false,
        mensaje: error,
        error: error,
      );

  bool get hasError => error != null;
}
