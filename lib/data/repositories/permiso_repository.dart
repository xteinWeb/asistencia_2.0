import '../datasources/local/database_helper.dart';
import '../models/permiso_model.dart';

class PermisoRepository {
  final DatabaseHelper _db;

  PermisoRepository({DatabaseHelper? db}) : _db = db ?? DatabaseHelper();

  /// Inserta un permiso en SQLite.
  Future<int> insertar(PermisoModel permiso) => _db.insertPermiso(permiso);

  /// Retorna el permiso activo para un empleado hoy (si existe).
  Future<PermisoModel?> getActivoByCedula(String cedula) =>
      _db.getPermisoActivoByCedula(cedula);

  /// Permisos pendientes de sincronización.
  Future<List<PermisoModel>> getPendientes() => _db.getPermisosPendientes();

  /// Marca un permiso como sincronizado.
  Future<int> marcarSincronizado(String id) => _db.marcarPermisoSincronizado(id);
}
