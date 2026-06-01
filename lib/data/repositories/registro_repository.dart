import '../datasources/local/database_helper.dart';
import '../models/registro_model.dart';

class RegistroRepository {
  final DatabaseHelper _db;

  RegistroRepository({DatabaseHelper? db}) : _db = db ?? DatabaseHelper();

  /// Inserta un nuevo registro de asistencia en SQLite.
  Future<int> insertar(RegistroModel registro) => _db.insertRegistro(registro);

  /// Registros del día de hoy.
  Future<List<RegistroModel>> getHoy() => _db.getRegistrosHoy();

  /// Registros de un empleado específico.
  Future<List<RegistroModel>> getPorCedula(String cedula) =>
      _db.getRegistrosPorCedula(cedula);

  /// Registros pendientes de sincronización.
  Future<List<RegistroModel>> getPendientes() => _db.getRegistrosPendientes();

  /// Marca un registro como sincronizado.
  Future<int> marcarSincronizado(String id) =>
      _db.marcarRegistroSincronizado(id);
}
