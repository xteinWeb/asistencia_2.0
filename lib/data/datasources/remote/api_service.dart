import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../../core/constants/db_constants.dart';
import '../local/database_helper.dart';
import '../../models/empleado_model.dart';
import '../../models/horario_model.dart';

class ApiService {
  final DatabaseHelper _db;

  ApiService({DatabaseHelper? db}) : _db = db ?? DatabaseHelper();

  Future<String> get _baseUrl async =>
      await _db.getConfig(DbConstants.cfgUrlApi) ?? ApiConstants.defaultBaseUrl;

  Map<String, String> get _headers => {'Content-Type': 'application/json'};

  // ─── EMPLEADOS ────────────────────────────────────────────────────────────

  /// Obtiene todos los empleados del servidor y los guarda en SQLite.
  Future<List<EmpleadoModel>> fetchAndSaveEmpleados() async {
    final url = Uri.parse('${await _baseUrl}${ApiConstants.syncEmpleados}');
    final response = await http
        .get(url, headers: _headers)
        .timeout(const Duration(milliseconds: ApiConstants.receiveTimeoutMs));

    if (response.statusCode != 200) {
      throw Exception('Error al obtener empleados: ${response.statusCode}');
    }

    final list = jsonDecode(response.body) as List;
    final empleados = list.map((e) => EmpleadoModel.fromJson(e as Map<String, dynamic>)).toList();

    for (final emp in empleados) {
      await _db.insertEmpleado(emp);
    }

    return empleados;
  }

  // ─── HORARIOS ─────────────────────────────────────────────────────────────

  /// Obtiene todos los horarios del servidor y los guarda en SQLite.
  Future<List<HorarioModel>> fetchAndSaveHorarios() async {
    final url = Uri.parse('${await _baseUrl}${ApiConstants.syncHorarios}');
    final response = await http
        .get(url, headers: _headers)
        .timeout(const Duration(milliseconds: ApiConstants.receiveTimeoutMs));

    if (response.statusCode != 200) {
      throw Exception('Error al obtener horarios: ${response.statusCode}');
    }

    final list = jsonDecode(response.body) as List;
    final horarios = list.map((e) => HorarioModel.fromJson(e as Map<String, dynamic>)).toList();

    for (final h in horarios) {
      await _db.insertHorario(h);
    }

    return horarios;
  }

  // ─── AUTH ─────────────────────────────────────────────────────────────────

  /// Verifica credenciales en el servidor (si hay internet).
  Future<bool> loginOnline(String usuario, String contrasena) async {
    try {
      final url = Uri.parse('${await _baseUrl}${ApiConstants.login}');
      final response = await http
          .post(url,
              headers: _headers,
              body: jsonEncode({
                'usuario': usuario,
                'contrasena': contrasena,
              }))
          .timeout(const Duration(milliseconds: ApiConstants.connectTimeoutMs));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
