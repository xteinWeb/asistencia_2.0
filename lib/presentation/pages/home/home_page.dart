import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/routes/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/sync_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
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
              content: Text(
                'Sincronización finalizada con errores: ${result.errors.first}',
              ),
              backgroundColor: AppColors.warning,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '¡Éxito! Sincronización bidireccional de todos los datos completada.',
              ),
              backgroundColor: AppColors.success,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de red al sincronizar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 720;

    final items = [
      _MenuItem(
        icon: Icons.face_retouching_natural,
        label: 'Asistencia',
        subtitle: 'Marcar entrada/salida',
        color: AppColors.success,
        route: AppRoutes.asistencia,
      ),
      _MenuItem(
        icon: Icons.people_outline,
        label: 'Empleados',
        subtitle: 'Gestión de empleados',
        color: AppColors.primary,
        route: AppRoutes.empleados,
      ),
      _MenuItem(
        icon: Icons.history,
        label: 'Historial',
        subtitle: 'Registros de asistencia',
        color: AppColors.accent,
        route: AppRoutes.historial,
      ),
      _MenuItem(
        icon: Icons.schedule,
        label: 'Horarios',
        subtitle: 'Gestión de horarios',
        color: AppColors.colorAlmuerzo,
        route: AppRoutes.horarios,
      ),
      _MenuItem(
        icon: Icons.event_available,
        label: 'Permisos',
        subtitle: 'Autorización de permisos',
        color: AppColors.colorPermiso,
        route: AppRoutes.permisos,
      ),
      _MenuItem(
        icon: Icons.assignment_turned_in_outlined,
        label: 'Programación',
        subtitle: 'Personal y tiempo extra',
        color: AppColors.colorPermiso,
        route: AppRoutes.convocatorias,
      ),
      _MenuItem(
        icon: Icons.event_busy,
        label: 'Novedades',
        subtitle: 'Control y justificaciones',
        color: AppColors.warning,
        route: AppRoutes.ausentismo,
      ),
      _MenuItem(
        icon: Icons.analytics_outlined,
        label: 'Reportes',
        subtitle: 'Históricos y estadísticas',
        color: AppColors.info,
        route: AppRoutes.reportes,
      ),
      _MenuItem(
        icon: Icons.medical_information,
        label: 'Incapacidades',
        subtitle: 'Ver de incapacidades',
        color: AppColors.textSecondary,
        route: AppRoutes.incapacidades,
      ),
      _MenuItem(
        icon: Icons.settings_outlined,
        label: 'Configuración',
        subtitle: 'Ajustes del sistema',
        color: AppColors.textSecondary,
        route: AppRoutes.configuracion,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Control de Asistencia'),
        actions: [
          IconButton(
            icon: _syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.sync),
            tooltip: 'Sincronizar todo',
            onPressed: _syncing ? null : _syncManually,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () => context.go(AppRoutes.login),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isWide ? 3 : 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: isWide ? 1.4 : 1.1,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return _MenuCard(item: item);
          },
        ),
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final String route;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.route,
  });
}

class _MenuCard extends StatelessWidget {
  final _MenuItem item;
  const _MenuCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go(item.route),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(item.icon, color: item.color, size: 32),
            ),
            const SizedBox(height: 10),
            Text(
              item.label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.subtitle,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
