import 'package:go_router/go_router.dart';
import '../../presentation/pages/splash/splash_page.dart';
import '../../presentation/pages/login/login_page.dart';
import '../../presentation/pages/home/home_page.dart';
import '../../presentation/pages/asistencia/asistencia_page.dart';
import '../../presentation/pages/empleados/empleados_list_page.dart';
import '../../presentation/pages/empleados/empleado_detail_page.dart';
import '../../presentation/pages/registro_empleado/registro_empleado_page.dart';
import '../../presentation/pages/historial/historial_page.dart';
import '../../presentation/pages/horarios/horarios_page.dart';
import '../../presentation/pages/permisos/permisos_page.dart';
import '../../presentation/pages/configuracion/configuracion_page.dart';

class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String login = '/login';
  static const String home = '/home';
  static const String asistencia = '/asistencia';
  static const String empleados = '/empleados';
  static const String empleadoDetalle = '/empleados/:cedula';
  static const String registroEmpleado = '/empleado/registro';
  static const String historial = '/historial';
  static const String horarios = '/horarios';
  static const String permisos = '/permisos';
  static const String configuracion = '/configuracion';
}

final appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  routes: [
    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) => const SplashPage(),
    ),
    GoRoute(
      path: AppRoutes.login,
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: AppRoutes.home,
      builder: (context, state) => const HomePage(),
    ),
    GoRoute(
      path: AppRoutes.asistencia,
      builder: (context, state) => const AsistenciaPage(),
    ),
    GoRoute(
      path: AppRoutes.empleados,
      builder: (context, state) => const EmpleadosListPage(),
    ),
    GoRoute(
      path: AppRoutes.registroEmpleado,
      builder: (context, state) => const RegistroEmpleadoPage(),
    ),
    GoRoute(
      path: AppRoutes.empleadoDetalle,
      builder: (context, state) => EmpleadoDetailPage(
        cedula: state.pathParameters['cedula']!,
      ),
    ),
    GoRoute(
      path: AppRoutes.historial,
      builder: (context, state) => const HistorialPage(),
    ),
    GoRoute(
      path: AppRoutes.horarios,
      builder: (context, state) => const HorariosPage(),
    ),
    GoRoute(
      path: AppRoutes.permisos,
      builder: (context, state) => const PermisosPage(),
    ),
    GoRoute(
      path: AppRoutes.configuracion,
      builder: (context, state) => const ConfiguracionPage(),
    ),
  ],
);
