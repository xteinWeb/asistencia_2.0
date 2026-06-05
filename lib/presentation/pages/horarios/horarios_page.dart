import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/routes/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/local/database_helper.dart';
import '../../../data/models/horario_model.dart';
import '../../../services/sync_service.dart';

class HorariosPage extends StatefulWidget {
  const HorariosPage({super.key});

  @override
  State<HorariosPage> createState() => _HorariosPageState();
}

class _HorariosPageState extends State<HorariosPage> {
  final _db = DatabaseHelper();
  
  List<HorarioModel> _horarios = [];
  bool _loading = true;
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
              content: Text('Sincronización finalizada con errores: ${result.errors.first}'),
              backgroundColor: AppColors.warning,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('¡Éxito! Sincronizados ${result.registros} registros y ${result.permisos} permisos.'),
              backgroundColor: AppColors.success,
            ),
          );
        }
        _loadHorarios();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error de red al sincronizar: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadHorarios();
  }

  Future<void> _loadHorarios() async {
    setState(() => _loading = true);
    try {
      final list = await _db.getAllHorarios();
      setState(() {
        _horarios = list;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar horarios: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Color _getTipoColor(String tipo) {
    switch (tipo.toUpperCase()) {
      case 'PRODUCTIVA':
      case 'LABORAL':
        return AppColors.primary;
      case 'RECESO':
      case 'ALMUERZO':
        return AppColors.colorAlmuerzo;
      case 'DESCANSO':
        return AppColors.colorSalida;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Horarios de Trabajo Centrales'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.home),
        ),
        actions: [
          IconButton(
            icon: _syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.sync),
            tooltip: 'Sincronizar horarios',
            onPressed: _syncing ? null : _syncManually,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _horarios.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.schedule, size: 64, color: AppColors.textDisabled),
                      const SizedBox(height: 16),
                      const Text(
                        'No hay horarios registrados en el sistema',
                        style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Presione el botón de sincronizar arriba para descargar desde SQL Server.',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _horarios.length,
                  itemBuilder: (context, index) {
                    final h = _horarios[index];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withOpacity(0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.schedule_outlined,
                                          color: AppColors.primary,
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              h.descripcion.toUpperCase(),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Código: ${h.idHorario}',
                                              style: TextStyle(
                                                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: h.estado.toUpperCase() == 'ACTIVO'
                                        ? AppColors.successLight
                                        : AppColors.errorLight,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    h.estado.toUpperCase(),
                                    style: TextStyle(
                                      color: h.estado.toUpperCase() == 'ACTIVO'
                                          ? AppColors.success
                                          : AppColors.error,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            
                            const Divider(height: 24),

                            const Text(
                              'SEGMENTOS DEL TURNO:',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 8),

                            if (h.items.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8.0),
                                child: Text(
                                  'Sin segmentos definidos en este horario.',
                                  style: TextStyle(color: Colors.grey, fontSize: 13, fontStyle: FontStyle.italic),
                                ),
                              )
                            else
                              Column(
                                children: h.items.map((item) {
                                  final itemColor = _getTipoColor(item.tipo);
                                  
                                  final List<String> days = [];
                                  if (item.lunes) days.add('Lu');
                                  if (item.martes) days.add('Ma');
                                  if (item.miercoles) days.add('Mi');
                                  if (item.jueves) days.add('Ju');
                                  if (item.viernes) days.add('Vi');
                                  if (item.sabado) days.add('Sa');
                                  if (item.domingo) days.add('Do');

                                  final String formattedInicio = item.inicio.length >= 5 ? item.inicio.substring(0, 5) : item.inicio;
                                  final String formattedFinal = item.finalTime.length >= 5 ? item.finalTime.substring(0, 5) : item.finalTime;

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.grey.withOpacity(0.1)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          item.tipo.toUpperCase() == 'PRODUCTIVA'
                                              ? Icons.play_circle_outline_rounded
                                              : Icons.pause_circle_outline_rounded,
                                          color: itemColor,
                                          size: 22,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          '$formattedInicio - $formattedFinal',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: itemColor.withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            item.tipo.toUpperCase(),
                                            style: TextStyle(
                                              color: itemColor,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          days.isEmpty ? 'Ninguno' : days.join(' '),
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.8),
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
