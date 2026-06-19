import '../../core/constants/app_constants.dart';
import '../../core/utils/face_matcher.dart';
import '../../core/utils/horario_validator.dart';
import '../../data/datasources/local/database_helper.dart';
import '../../data/models/registro_model.dart';
import '../../data/models/empleado_model.dart';
import '../../data/models/permiso_model.dart';

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
    if (empleados.isEmpty) {
      print('[Biometria] No hay empleados ACTIVOS registrados localmente.');
      return null;
    }

    final umbralStr = await _db.getConfig('umbral_facial') ?? '0.6';
    final umbral = double.tryParse(umbralStr) ?? AppConstants.faceMatchThreshold;
    
    print('[Biometria] Comparando rostro contra ${empleados.length} empleados activos (Umbral Máximo Distancia: $umbral)...');
    
    // Comparar e imprimir diagnósticos de todos los empleados
    for (final e in empleados) {
      if (e.mapaVectorFoto.isEmpty) {
        print('  - ${e.nombre} (${e.cedula}): Sin vector registrado.');
        continue;
      }
      final dist = FaceMatcher.euclideanDistance(vectorDetectado, e.mapaVectorFoto);
      final sim = FaceMatcher.similarityPercent(dist, threshold: umbral);
      print('  - Comparación con ${e.nombre} (${e.cedula}) -> Distancia: ${dist.toStringAsFixed(4)} (Similitud: ${sim.toStringAsFixed(2)}%)');
    }

    final vectors = empleados.map((e) => e.mapaVectorFoto).toList();
    final match = FaceMatcher.findBestMatch(vectorDetectado, vectors, threshold: umbral);

    if (match == null) {
      print('[Biometria] RESULTADO: Ningún empleado superó el umbral de coincidencia.');
      return null;
    }
    
    final empMatch = empleados[match.index];
    final matchSim = FaceMatcher.similarityPercent(match.distance, threshold: umbral);
    print('[Biometria] RESULTADO: Match encontrado con ${empMatch.nombre} (${empMatch.cedula}) - Distancia: ${match.distance.toStringAsFixed(4)} (Similitud: ${matchSim.toStringAsFixed(2)}%)');
    
    return (empleado: empMatch, distancia: match.distance);
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
    String metodoRegistro = 'FACIAL',
  }) async {
    final ahora = DateTime.now();
    final registrosHoy = await getRegistrosDeHoy(empleado.cedula);

    String evento = AppConstants.eventoEntrada;
    String descripcion = '';
    String tipoFinal = tipoSeleccionado.name.toUpperCase();
    String? duracionFinal;

    final yaTieneEntrada = registrosHoy.any((r) => r.tipo == TipoRegistro.normal.name.toUpperCase() || 
                                                   r.tipo == TipoRegistro.retardo.name.toUpperCase() ||
                                                   r.tipo == TipoRegistro.permiso.name.toUpperCase());
    final yaTieneSalida = registrosHoy.any((r) => r.evento == AppConstants.eventoSalida);
    final yaTieneAlmuerzo = registrosHoy.any((r) => r.tipo == TipoRegistro.almuerzo.name.toUpperCase());

    // 1. Obtener todos los permisos del empleado para el día de hoy
    final hoyStr = ahora.toIso8601String().substring(0, 10);
    final permisos = await _db.getPermisosByCedula(empleado.cedula);
    PermisoModel? permisoHoy;
    for (final p in permisos) {
      if (p.fechaInicio.length >= 10 && p.fechaFinal.length >= 10) {
        final startDay = p.fechaInicio.substring(0, 10);
        final endDay = p.fechaFinal.substring(0, 10);
        if (hoyStr.compareTo(startDay) >= 0 && hoyStr.compareTo(endDay) <= 0) {
          permisoHoy = p;
          break;
        }
      }
    }

    // ─── CASO 1: SALIDA ──────────────────────────────────────────────
    if (tipoSeleccionado == TipoRegistro.salida) {
      if (!yaTieneEntrada) {
        return MarcarAsistenciaResult.error('Registro Inválido: No puedes registrar Salida sin antes haber marcado tu Entrada hoy.');
      }
      if (yaTieneSalida) {
        return MarcarAsistenciaResult.error('Registro Inválido: Ya has marcado tu Salida final por el día de hoy.');
      }

      // Validar salida anticipada u tardía frente al horario del turno
      if (empleado.horarioId != null) {
        final horario = await _db.getHorarioById(empleado.horarioId!);
        if (horario != null && horario.items.isNotEmpty) {
          // Filtrar items del horario activos para el día de hoy y de tipo PRODUCTIVA
          final itemsHoyProductivos = horario.items.where((item) {
            bool activeToday = false;
            switch (ahora.weekday) {
              case DateTime.monday: activeToday = item.lunes; break;
              case DateTime.tuesday: activeToday = item.martes; break;
              case DateTime.wednesday: activeToday = item.miercoles; break;
              case DateTime.thursday: activeToday = item.jueves; break;
              case DateTime.friday: activeToday = item.viernes; break;
              case DateTime.saturday: activeToday = item.sabado; break;
              case DateTime.sunday: activeToday = item.domingo; break;
            }
            return activeToday && item.tipo.toUpperCase() == 'PRODUCTIVA';
          }).toList();

          String horaFinalStr = horario.horaFinal; // Fallback al final general
          if (itemsHoyProductivos.isNotEmpty) {
            // Ordenar por hora de finalización y tomar la más tardía
            itemsHoyProductivos.sort((a, b) => a.finalTime.compareTo(b.finalTime));
            horaFinalStr = itemsHoyProductivos.last.finalTime;
          }

          if (horaFinalStr.isNotEmpty) {
            final parts = horaFinalStr.split(':');
            if (parts.length >= 2) {
              final hour = int.tryParse(parts[0]);
              final minute = int.tryParse(parts[1]);
              if (hour != null && minute != null) {
                final finTurno = DateTime(ahora.year, ahora.month, ahora.day, hour, minute);
                if (ahora.isBefore(finTurno)) {
                  // Se requiere un permiso activo en este momento para poder salir temprano
                  final permisoActivo = await _db.getPermisoActivoByCedula(empleado.cedula);
                  if (permisoActivo == null) {
                    final horaFinalMostrada = horaFinalStr.length >= 5 ? horaFinalStr.substring(0, 5) : horaFinalStr;
                    return MarcarAsistenciaResult.error(
                      'No se puede marcar salida antes de la hora de finalización del turno ($horaFinalMostrada) a menos que exista un permiso activo.',
                    );
                  }
                } else if (ahora.isAfter(finTurno)) {
                  final diff = ahora.difference(finTurno);
                  if (diff.inMinutes > 0) {
                    duracionFinal = '${diff.inMinutes} minutos';
                    final horaFinalMostrada = horaFinalStr.length >= 5 ? horaFinalStr.substring(0, 5) : horaFinalStr;
                    descripcion = 'Salida de jornada registrada correctamente (${diff.inMinutes} minutos después de la hora del turno $horaFinalMostrada). ¡Hasta mañana!';
                  }
                }
              }
            }
          }
        }
      }

      evento = AppConstants.eventoSalida;
      if (descripcion.isEmpty) {
        descripcion = 'Salida de jornada registrada correctamente. ¡Hasta mañana!';
      }
    }
    // ─── CASO 2: SALIDA POR PERMISO (Botón Permiso con Entrada ya registrada) ───
    else if (tipoSeleccionado == TipoRegistro.permiso && yaTieneEntrada) {
      final permiso = await _db.getPermisoActivoByCedula(empleado.cedula);
      if (permiso == null) {
        return MarcarAsistenciaResult.error('No hay permiso autorizado registrado hoy para este usuario.');
      }
      if (yaTieneSalida) {
        return MarcarAsistenciaResult.error('Registro Inválido: Ya has marcado tu Salida final por el día de hoy.');
      }
      evento = AppConstants.eventoSalida;
      tipoFinal = 'PERMISO';
      descripcion = 'Marcación por Permiso Autorizado (Salida) registrada con éxito.';
    }
    // ─── CASO 3: ENTRADAS (Normal, Retardo, o Permiso de Entrada) ──────
    else if (tipoSeleccionado == TipoRegistro.normal || 
             tipoSeleccionado == TipoRegistro.retardo || 
             (tipoSeleccionado == TipoRegistro.permiso && !yaTieneEntrada)) {
      if (yaTieneEntrada) {
        return MarcarAsistenciaResult.error('Registro Inválido: Ya has registrado tu Entrada el día de hoy.');
      }

      evento = AppConstants.eventoEntrada;

      if (permisoHoy != null) {
        final inicioPermiso = DateTime.tryParse(permisoHoy.fechaInicio);
        final finPermiso = DateTime.tryParse(permisoHoy.fechaFinal);

        if (inicioPermiso != null && finPermiso != null) {
          if (ahora.isBefore(inicioPermiso)) {
            // Aún no inicia el periodo del permiso. Evaluar según horario normal:
            tipoFinal = 'NORMAL';
            descripcion = '¡Bienvenido! Entrada registrada correctamente (Permiso programado para más tarde).';
            if (empleado.horarioId != null) {
              final horario = await _db.getHorarioById(empleado.horarioId!);
              if (horario != null && horario.horaInicio.isNotEmpty) {
                final parts =
                    horario.horaInicio.split(':');
                if (parts.length >= 2) {
                  final hour = int.tryParse(parts[0]);
                  final minute = int.tryParse(parts[1]);
                  if (hour != null && minute != null) {
                    final inicioTurno = DateTime(
                        ahora.year,
                        ahora.month,
                        ahora.day,
                        hour,
                        minute);
                    if (ahora.isAfter(inicioTurno)) {
                      final diff = ahora.difference(inicioTurno);
                      if (diff.inMinutes > 0) {
                        tipoFinal = 'RETARDO';
                        duracionFinal = '${diff.inMinutes} minutos';
                        descripcion =
                            'Retardo de ${diff.inMinutes} minutos registrado (Permiso programado para más tarde).';
                      }
                    }
                  }
                }
              }
            }
          } else if (ahora.isAfter(finPermiso)) {
            // Llegó después de la hora final del permiso -> Permiso con retardo
            tipoFinal = 'PERMISO';
            final diff = ahora.difference(finPermiso);
            duracionFinal = '${diff.inMinutes} minutos';
            descripcion =
                'Entrada con permiso y retardo de ${diff.inMinutes} minutos registrada.';
          } else {
            // Llegó dentro del tiempo del permiso -> Entrada normal, permiso finalizado
            tipoFinal = 'NORMAL';
            descripcion =
                '¡Bienvenido! Entrada registrada (Permiso finalizado).';
          }
        } else {
          // Fallback de parseo de permiso: evaluar según horario normal
          tipoFinal = 'NORMAL';
          descripcion = '¡Bienvenido! Entrada registrada correctamente.';
          if (empleado.horarioId != null) {
            final horario = await _db.getHorarioById(empleado.horarioId!);
            if (horario != null && horario.horaInicio.isNotEmpty) {
              final parts = horario.horaInicio.split(':');
              if (parts.length >= 2) {
                final hour = int.tryParse(parts[0]);
                final minute = int.tryParse(parts[1]);
                if (hour != null && minute != null) {
                  final inicioTurno = DateTime(
                      ahora.year,
                      ahora.month,
                      ahora.day,
                      hour,
                      minute);
                  if (ahora.isAfter(inicioTurno)) {
                    final diff = ahora.difference(inicioTurno);
                    if (diff.inMinutes > 0) {
                      tipoFinal = 'RETARDO';
                      duracionFinal = '${diff.inMinutes} minutos';
                      descripcion =
                          'Retardo de ${diff.inMinutes} minutos registrado.';
                    }
                  }
                }
              }
            }
          }
        }
      } else {
        // No tiene permiso hoy. Si presionó el botón 'PERMISO', error inmediato.
        if (tipoSeleccionado == TipoRegistro.permiso) {
          return MarcarAsistenciaResult.error(
              'No hay permiso autorizado registrado hoy para este usuario.');
        }

        // Evaluar entrada normal o retardo según su horario
        tipoFinal = 'NORMAL';
        descripcion = '¡Bienvenido! Entrada registrada correctamente.';
        if (empleado.horarioId != null) {
          final horario = await _db.getHorarioById(empleado.horarioId!);
          if (horario != null && horario.horaInicio.isNotEmpty) {
            final parts = horario.horaInicio.split(':');
            if (parts.length >= 2) {
              final hour = int.tryParse(parts[0]);
              final minute = int.tryParse(parts[1]);
              if (hour != null && minute != null) {
                final inicioTurno = DateTime(
                    ahora.year,
                    ahora.month,
                    ahora.day,
                    hour,
                    minute);
                if (ahora.isAfter(inicioTurno)) {
                  final diff = ahora.difference(inicioTurno);
                  if (diff.inMinutes > 0) {
                    tipoFinal = 'RETARDO';
                    duracionFinal = '${diff.inMinutes} minutos';
                    descripcion =
                        'Retardo de ${diff.inMinutes} minutos registrado.';
                  }
                }
              }
            }
          }
        }
      }
    }
    // ─── CASO 4: ALMUERZO O EXTRAS ────────────────────────────────────
    else {
      switch (tipoSeleccionado) {
        case TipoRegistro.almuerzo:
          if (!yaTieneEntrada) {
            return MarcarAsistenciaResult.error('Registro Inválido: No puedes registrar Almuerzo sin antes registrar Entrada hoy.');
          }
          if (yaTieneSalida) {
            return MarcarAsistenciaResult.error('Registro Inválido: Ya has registrado la Salida de tu jornada hoy.');
          }
          evento = yaTieneAlmuerzo ? AppConstants.eventoEntrada : AppConstants.eventoSalida;
          descripcion = yaTieneAlmuerzo ? 'Retorno de almuerzo registrado.' : 'Salida a almuerzo registrada.';
          break;

        case TipoRegistro.extras:
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
      duracion: duracionFinal,
      tipo: tipoFinal,
      unidadNegocio: unidad,
      metodoRegistro: metodoRegistro,
      sincronizado: false,
    );

    // Guardar en SQLite local
    await _db.insertRegistro(registro);

    // Mapeamos el tipo final al enum TipoRegistro para el resultado
    TipoRegistro tipoResultado = tipoSeleccionado;
    if (tipoFinal == 'PERMISO') {
      tipoResultado = TipoRegistro.permiso;
    } else if (tipoFinal == 'NORMAL') {
      tipoResultado = TipoRegistro.normal;
    }

    return MarcarAsistenciaResult(
      registrado: true,
      mensaje: descripcion,
      empleadoNombre: empleado.nombre,
      empleadoCedula: empleado.cedula,
      tipoRegistro: tipoResultado,
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
