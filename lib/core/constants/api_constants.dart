import '../config/environment.dart';

class ApiConstants {
  static String get defaultBaseUrl => Environment.apiUrl;
  static const String apiPrefix = '/api';

  // Endpoints asistencia
  static const String nuevoEmpleado = '/api/asistencia/nuevoEmpleado';
  static const String compararRostro = '/api/asistencia/compararRostro';

  // Endpoints sincronización
  static const String syncRegistros = '/api/sync/registros';
  static const String syncPermisos = '/api/sync/permisos';
  static const String syncEmpleados = '/api/sync/empleados';
  static const String syncHorarios = '/api/sync/horarios';

  // Auth
  static const String login = '/api/auth/login';

  // Timeouts
  static const int connectTimeoutMs = 10000;
  static const int receiveTimeoutMs = 30000;
}
