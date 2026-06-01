class AppConstants {
  // Reconocimiento facial
  static const double faceMatchThreshold = 0.6;
  static const int faceVectorDimensions = 128;

  // Horarios
  static const int toleranciaRetardoMinutos = 15;

  // Sincronización
  static const int syncIntervalMinutes = 15;

  // Sesión
  static const int sessionTimeoutMinutes = 60;

  // Cámara
  static const int cameraResolutionWidth = 640;
  static const int cameraResolutionHeight = 480;

  // UI
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1024;

  // Resultado asistencia (segundos que se muestra el resultado)
  static const int resultDisplaySeconds = 4;

  // Roles
  static const String rolAdmin = 'ADMIN';
  static const String rolOperador = 'OPERADOR';
  static const String rolSoloLectura = 'SOLO_LECTURA';

  // Tipos de registro
  static const String eventoEntrada = 'ENTRADA';
  static const String eventoSalida = 'SALIDA';

  // Tipos de horario
  static const String horarioLaboral = 'LABORAL';
  static const String horarioAlmuerzo = 'ALMUERZO';
  static const String horarioDescanso = 'DESCANSO';

  // Tipos de permiso
  static const String permisoCitaMedica = 'CITA_MEDICA';
  static const String permisoPersonal = 'PERSONAL';
  static const String permisoLaboral = 'LABORAL';
  static const String permisoTraslado = 'TRASLADO';
  static const String permisoFinContrato = 'FIN_CONTRATO';
}
