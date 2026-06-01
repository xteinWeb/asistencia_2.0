import '../datasources/local/database_helper.dart';
import '../datasources/remote/api_service.dart';
import '../models/empleado_model.dart';
import '../../services/connectivity_service.dart';

class EmpleadoRepository {
  final DatabaseHelper _db;
  final ApiService _api;
  final ConnectivityService _connectivity;

  EmpleadoRepository({
    DatabaseHelper? db,
    ApiService? api,
    ConnectivityService? connectivity,
  })  : _db = db ?? DatabaseHelper(),
        _api = api ?? ApiService(),
        _connectivity = connectivity ?? ConnectivityService();

  /// Obtiene todos los empleados de SQLite local.
  Future<List<EmpleadoModel>> getAll() => _db.getAllEmpleados();

  /// Busca un empleado por cédula en SQLite.
  Future<EmpleadoModel?> getByCedula(String cedula) =>
      _db.getEmpleadoByCedula(cedula);

  /// Guarda o actualiza un empleado en SQLite.
  Future<int> save(EmpleadoModel empleado) => _db.insertEmpleado(empleado);

  /// Elimina un empleado de SQLite.
  Future<int> delete(String cedula) => _db.deleteEmpleado(cedula);

  /// Sincroniza empleados desde el servidor si hay conexión.
  Future<List<EmpleadoModel>> syncFromServer() async {
    final connected = await _connectivity.isConnected();
    if (!connected) return _db.getAllEmpleados();
    return _api.fetchAndSaveEmpleados();
  }
}
