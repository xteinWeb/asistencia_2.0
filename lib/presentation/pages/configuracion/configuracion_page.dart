import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../../core/theme/theme_provider.dart';

import '../../../core/routes/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/constants/db_constants.dart';
import '../../../data/datasources/local/database_helper.dart';
import '../../../services/sync_service.dart';

class ConfiguracionPage extends StatefulWidget {
  const ConfiguracionPage({super.key});

  @override
  State<ConfiguracionPage> createState() => _ConfiguracionPageState();
}

class _ConfiguracionPageState extends State<ConfiguracionPage> {
  final _formKey = GlobalKey<FormState>();
  final _db = DatabaseHelper();

  final _urlCtrl = TextEditingController();
  final _syncCtrl = TextEditingController();
  final _unidadCtrl = TextEditingController();
  final _umbralCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _testingConnection = false;
  bool _syncing = false;
  
  int _pendientesRegistros = 0;
  int _pendientesPermisos = 0;

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
        // Recargar configuraciones locales para actualizar contadores
        _loadConfig();
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
    _loadConfig();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _syncCtrl.dispose();
    _unidadCtrl.dispose();
    _umbralCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() => _loading = true);
    try {
      // 1. Cargar configuraciones de SQLite
      final url = await _db.getConfig(DbConstants.cfgUrlApi) ?? ApiConstants.defaultBaseUrl;
      final freq = await _db.getConfig(DbConstants.cfgFrecuenciaSync) ?? '15';
      final unidad = await _db.getConfig(DbConstants.cfgUnidadNegocio) ?? 'Principal';
      final umbral = await _db.getConfig(DbConstants.cfgUmbralFacial) ?? '0.6';

      _urlCtrl.text = url;
      _syncCtrl.text = freq;
      _unidadCtrl.text = unidad;
      _umbralCtrl.text = umbral;

      // 2. Cargar recuentos pendientes de sincronización
      final registros = await _db.getRegistrosPendientes();
      final permisos = await _db.getPermisosPendientes();
      
      setState(() {
        _pendientesRegistros = registros.length;
        _pendientesPermisos = permisos.length;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar configuración: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      await _db.setConfig(DbConstants.cfgUrlApi, _urlCtrl.text.trim());
      await _db.setConfig(DbConstants.cfgFrecuenciaSync, _syncCtrl.text.trim());
      await _db.setConfig(DbConstants.cfgUnidadNegocio, _unidadCtrl.text.trim());
      await _db.setConfig(DbConstants.cfgUmbralFacial, _umbralCtrl.text.trim());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuración guardada correctamente'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar configuración: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _probarConexion() async {
    final urlStr = _urlCtrl.text.trim();
    if (urlStr.isEmpty) return;

    setState(() => _testingConnection = true);
    
    try {
      // Intentamos pegarle a un endpoint simple de API de la URL ingresada
      final uri = Uri.parse(urlStr);
      final response = await http.get(uri).timeout(const Duration(seconds: 4));

      if (mounted) {
        // Cualquier código de estado (incluso 404) indica que el host respondió y es alcanzable
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('¡Conexión Exitosa! El servidor en $urlStr está en línea (status: ${response.statusCode})'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de conexión: No se pudo alcanzar el servidor ($e)'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _testingConnection = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración del Dispositivo'),
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
            tooltip: 'Sincronizar todo',
            onPressed: _syncing ? null : _syncManually,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Ficha de Configuración
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Parámetros de Servidor y Sincronización',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                            ),
                            const SizedBox(height: 20),

                            // URL de la API
                            TextFormField(
                              controller: _urlCtrl,
                              keyboardType: TextInputType.url,
                              decoration: InputDecoration(
                                labelText: 'URL de API Node.js',
                                hintText: ApiConstants.defaultBaseUrl,
                                prefixIcon: const Icon(Icons.link),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Ingrese la URL de la API' : null,
                            ),
                            const SizedBox(height: 12),

                            // Botón de Probar Conexión
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _testingConnection ? null : _probarConexion,
                                icon: _testingConnection
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.swap_calls),
                                label: const Text('Probar Conexión con Servidor'),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Frecuencia Sincronización
                            TextFormField(
                              controller: _syncCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Frecuencia de Sincronización (minutos)',
                                prefixIcon: Icon(Icons.sync_alt_outlined),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Ingrese la frecuencia';
                                final num = int.tryParse(v);
                                if (num == null || num <= 0) return 'Ingrese un número válido mayor a 0';
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Ficha de Parámetros del Dispositivo
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Parámetros Locales del Tótem',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                            ),
                            const SizedBox(height: 20),

                            // Unidad de Negocio
                            TextFormField(
                              controller: _unidadCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Unidad de Negocio / ID de Dispositivo',
                                prefixIcon: Icon(Icons.storefront_outlined),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Ingrese la unidad de negocio' : null,
                            ),
                            const SizedBox(height: 16),

                            // Umbral Similitud Facial
                            TextFormField(
                              controller: _umbralCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Umbral Similitud Facial (Recomendado: 0.6)',
                                helperText: 'Un valor más bajo exige mayor exactitud para aceptar el rostro.',
                                prefixIcon: Icon(Icons.fingerprint),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Ingrese el umbral';
                                final val = double.tryParse(v);
                                if (val == null || val <= 0.0 || val > 1.0) {
                                  return 'Ingrese un decimal válido entre 0.1 y 1.0';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Ficha de Estado de Sincronización
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.cloud_upload_outlined, color: AppColors.primary),
                                const SizedBox(width: 8),
                                Text(
                                  'Datos Locales Pendientes',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _SyncCounterRow(label: 'Registros de Asistencia', count: _pendientesRegistros),
                            const SizedBox(height: 10),
                            _SyncCounterRow(label: 'Permisos Autorizados', count: _pendientesPermisos),
                            if (_pendientesRegistros > 0 || _pendientesPermisos > 0) ...[
                              const SizedBox(height: 16),
                              Text(
                                'ℹ️ Estos datos se sincronizarán automáticamente de fondo o puedes forzar el envío inmediato desde la pantalla de "Historial".',
                                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic),
                              ),
                            ]
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Tarjeta de Configuración de Apariencia
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.palette_outlined, color: AppColors.primary),
                                const SizedBox(width: 8),
                                Text(
                                  'Apariencia y Tema del Dispositivo',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Configura la apariencia visual del tótem administrativo para adaptarlo al entorno o forzar el modo oscuro.',
                              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 20),
                            Center(
                              child: Consumer<ThemeProvider>(
                                builder: (context, themeProvider, child) {
                                  return SegmentedButton<ThemeMode>(
                                    segments: const [
                                      ButtonSegment<ThemeMode>(
                                        value: ThemeMode.light,
                                        icon: Icon(Icons.wb_sunny_outlined),
                                        label: Text('Claro'),
                                      ),
                                      ButtonSegment<ThemeMode>(
                                        value: ThemeMode.dark,
                                        icon: Icon(Icons.nightlight_outlined),
                                        label: Text('Oscuro'),
                                      ),
                                      ButtonSegment<ThemeMode>(
                                        value: ThemeMode.system,
                                        icon: Icon(Icons.settings_suggest_outlined),
                                        label: Text('Sistema'),
                                      ),
                                    ],
                                    selected: {themeProvider.themeMode},
                                    onSelectionChanged: (Set<ThemeMode> newSelection) {
                                      themeProvider.updateThemeMode(newSelection.first);
                                    },
                                    style: SegmentedButton.styleFrom(
                                      selectedBackgroundColor: AppColors.primary.withValues(alpha: 0.15),
                                      selectedForegroundColor: AppColors.primary,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Botón Guardar
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _saveConfig,
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Guardar Cambios'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _SyncCounterRow extends StatelessWidget {
  final String label;
  final int count;

  const _SyncCounterRow({
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final hasPending = count > 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: hasPending ? AppColors.warningLight : AppColors.successLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: hasPending ? AppColors.warning : AppColors.success),
          ),
          child: Text(
            hasPending ? '$count pendientes' : 'Al día',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: hasPending ? AppColors.warning : AppColors.success,
            ),
          ),
        )
      ],
    );
  }
}
