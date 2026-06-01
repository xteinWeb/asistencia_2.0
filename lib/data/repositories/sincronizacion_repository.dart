import '../../services/sync_service.dart';

class SincronizacionRepository {
  final SyncService _syncService;

  SincronizacionRepository({SyncService? syncService})
      : _syncService = syncService ?? SyncService();

  /// Ejecuta sincronización manual inmediata.
  Future<SyncResult> sincronizarAhora() => _syncService.syncAll();

  /// Inicia la sincronización periódica en background.
  void iniciarSyncPeriodico({int intervalMinutes = 15}) =>
      _syncService.startPeriodicSync(intervalMinutes: intervalMinutes);

  /// Detiene la sincronización periódica.
  void detenerSync() => _syncService.stopSync();
}
