import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/datasources/local/database_helper.dart';
import '../core/constants/api_constants.dart';
import '../core/constants/db_constants.dart';
import 'connectivity_service.dart';
import '../data/models/empleado_model.dart';
import '../data/models/horario_model.dart';
import '../data/models/usuario_model.dart';
import '../data/models/permiso_model.dart';
import '../data/models/incapacidad_model.dart';
import '../data/models/registro_model.dart';
import '../data/models/ausentismo_model.dart';
import '../data/models/convocatoria_model.dart';
import '../data/models/convocatoria_empleado_model.dart';

/// Servicio de sincronización periódica y bidireccional.
class SyncService {
  final DatabaseHelper _db;
  final ConnectivityService _connectivity;
  Timer? _timer;
  bool _isSyncing = false;

  SyncService({
    DatabaseHelper? db,
    ConnectivityService? connectivity,
  })  : _db = db ?? DatabaseHelper(),
        _connectivity = connectivity ?? ConnectivityService();

  /// Inicia la sincronización periódica cada [intervalMinutes] minutos.
  void startPeriodicSync({int intervalMinutes = 15}) {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(minutes: intervalMinutes),
      (_) => syncAll(),
    );
    // Sincronizar inmediatamente al iniciar
    syncAll();
  }

  void stopSync() {
    _timer?.cancel();
    _timer = null;
  }

  /// Ejecuta el proceso completo de sincronización bidireccional:
  /// 1. Push: Sube registros, permisos locales y enrolamientos a SQL Server.
  /// 2. Pull: Descarga horarios, usuarios, empleados y permisos desde SQL Server.
  Future<SyncResult> syncAll() async {
    if (kIsWeb) {
      return SyncResult(registros: 0, permisos: 0, errors: []);
    }
    if (_isSyncing) return SyncResult(registros: 0, permisos: 0, errors: []);
    _isSyncing = true;

    final errors = <String>[];
    int registrosSynced = 0;
    int permisosSynced = 0;

    try {
      final connected = await _connectivity.isConnected();
      if (!connected) {
        return SyncResult(
            registros: 0, permisos: 0, errors: ['Sin conexión a internet']);
      }

      final baseUrl = await _db.getConfig(DbConstants.cfgUrlApi) ??
          ApiConstants.defaultBaseUrl;

      // ─── FASE 1: SUBIR DATOS LOCALES (PUSH) ──────────────────────────
      // Primero subimos los horarios para que existan en el servidor antes que los empleados
      final hSync = await _pushHorarios(baseUrl);
      errors.addAll(hSync);

      // Luego subimos los enrolamientos de empleados para que ya existan con su información real
      final eSync = await _pushEmpleados(baseUrl);
      errors.addAll(eSync);

      final rSync = await _syncRegistros(baseUrl);
      registrosSynced = rSync.$1;
      errors.addAll(rSync.$2);

      final pSync = await _syncPermisos(baseUrl);
      permisosSynced = pSync.$1;
      errors.addAll(pSync.$2);

      final aSync = await _syncAusentismos(baseUrl);
      errors.addAll(aSync.$2);

      // ─── FASE 2: DESCARGAR DATOS CENTRALES (PULL) ─────────────────────
      final pullH = await _pullHorarios(baseUrl);
      errors.addAll(pullH);

      final pullS = await _pullSecciones(baseUrl);
      errors.addAll(pullS);

      final pullU = await _pullUsuarios(baseUrl);
      errors.addAll(pullU);

      final pullE = await _pullEmpleados(baseUrl);
      errors.addAll(pullE);

      final pullP = await _pullPermisos(baseUrl);
      errors.addAll(pullP);

      final pullI = await _pullIncapacidades(baseUrl);
      errors.addAll(pullI);

      final pullR = await _pullRegistros(baseUrl);
      errors.addAll(pullR);

      final pullT = await _pullTiposAusencia(baseUrl);
      errors.addAll(pullT);

      final pullA = await _pullAusentismos(baseUrl);
      errors.addAll(pullA);

      // ─── FASE 3: SINCRONIZACIÓN DE CONVOCATORIAS (PUSH & PULL) ───────
      final pushC = await _pushConvocatorias(baseUrl);
      errors.addAll(pushC);

      final pullC = await _pullConvocatorias(baseUrl);
      errors.addAll(pullC);

      return SyncResult(
        registros: registrosSynced,
        permisos: permisosSynced,
        errors: errors,
      );
    } catch (e) {
      return SyncResult(registros: 0, permisos: 0, errors: [e.toString()]);
    } finally {
      _isSyncing = false;
    }
  }

  // ─── MÉTODOS DE SUBIDA (PUSH) ───────────────────────────────────────────

  Future<List<String>> _pushHorarios(String baseUrl) async {
    return <String>[];
  }

  Future<(int, List<String>)> _syncRegistros(String baseUrl) async {
    final pendientes = await _db.getRegistrosPendientes();
    if (pendientes.isEmpty) return (0, <String>[]);

    final errors = <String>[];
    int synced = 0;
    final idsToSync = <String>[];

    try {
      final uri = Uri.parse('$baseUrl${ApiConstants.syncRegistros}');
      final body = jsonEncode(pendientes.map((r) => r.toMap()).toList());
      final response = await http
          .post(uri,
              headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(milliseconds: ApiConstants.receiveTimeoutMs));

      if (response.statusCode == 200 || response.statusCode == 201) {
        idsToSync.addAll(pendientes.where((r) => r.id != null).map((r) => r.id!));
        synced = await _db.marcarRegistrosSincronizados(idsToSync);
      } else {
        errors.add('Error sync registros: ${response.statusCode}');
      }
    } catch (e) {
      errors.add('Excepción sync registros: $e');
    }

    return (synced, errors);
  }

  Future<(int, List<String>)> _syncPermisos(String baseUrl) async {
    final pendientes = await _db.getPermisosPendientes();
    if (pendientes.isEmpty) return (0, <String>[]);

    final errors = <String>[];
    int synced = 0;

    try {
      final uri = Uri.parse('$baseUrl${ApiConstants.syncPermisos}');
      final body = jsonEncode(pendientes.map((p) => p.toMap()).toList());
      final response = await http
          .post(uri,
              headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(milliseconds: ApiConstants.receiveTimeoutMs));

      if (response.statusCode == 200 || response.statusCode == 201) {
        for (final p in pendientes) {
          if (p.id != null) {
            await _db.marcarPermisoSincronizado(p.id!);
            synced++;
          }
        }
      } else {
        errors.add('Error sync permisos: ${response.statusCode}');
      }
    } catch (e) {
      errors.add('Excepción sync permisos: $e');
    }

    return (synced, errors);
  }

  Future<(int, List<String>)> _syncIncapacidades(String baseUrl) async {
    final pendientes = await _db.getIncapacidadesPendientes();
    if (pendientes.isEmpty) return (0, <String>[]);

    final errors = <String>[];
    int synced = 0;

    try {
      final uri = Uri.parse('$baseUrl/api/sync/incapacidades');
      final body = jsonEncode(pendientes.map((p) => p.toMap()).toList());
      final response = await http
          .post(uri,
              headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(milliseconds: ApiConstants.receiveTimeoutMs));

      if (response.statusCode == 200 || response.statusCode == 201) {
        for (final p in pendientes) {
          if (p.id != null) {
            await _db.marcarIncapacidadSincronizada(p.id!);
            synced++;
          }
        }
      } else {
        // No agregamos como error fatal si la ruta no existe (404) para evitar alarmar al usuario si el servidor no tiene soporte web aún.
        if (response.statusCode != 404) {
          errors.add('Error sync incapacidades: ${response.statusCode}');
        }
      }
    } catch (e) {
      errors.add('Excepción sync incapacidades: $e');
    }

    return (synced, errors);
  }

  Future<List<String>> _pushEmpleados(String baseUrl) async {
    final errors = <String>[];
    try {
      final list = await _db.getAllEmpleados();
      // Empleados creados o modificados localmente que no se hayan sincronizado
      final pendientes = list.where((e) => !e.sincronizado).toList();
      if (pendientes.isEmpty) return errors;

      final uri = Uri.parse('$baseUrl/api/sync/empleados');
      final body = jsonEncode(pendientes.map((e) => e.toMap()).toList());
      final response = await http
          .post(uri,
              headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(milliseconds: ApiConstants.receiveTimeoutMs));

      if (response.statusCode == 200 || response.statusCode == 201) {
        for (final emp in pendientes) {
          final updated = emp.copyWith(sincronizado: true);
          await _db.updateEmpleado(updated);
        }
      } else {
        errors.add('Error push empleados: ${response.statusCode}');
      }
    } catch (e) {
      errors.add('Excepción push empleados: $e');
    }
    return errors;
  }

  // ─── MÉTODOS DE BAJADA (PULL) ───────────────────────────────────────────

  Future<List<String>> _pullHorarios(String baseUrl) async {
    final errors = <String>[];
    try {
      final uri = Uri.parse('$baseUrl/api/sync/horarios');
      final response = await http.get(uri).timeout(const Duration(milliseconds: ApiConstants.receiveTimeoutMs));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true) {
          final data = body['data'] as List;
          for (final item in data) {
            final horario = HorarioModel.fromJson(item);
            await _db.insertHorario(horario);
          }
        }
      } else {
        errors.add('Error pull horarios: ${response.statusCode}');
      }
    } catch (e) {
      errors.add('Excepción pull horarios: $e');
    }
    return errors;
  }

  Future<List<String>> _pullUsuarios(String baseUrl) async {
    final errors = <String>[];
    try {
      final uri = Uri.parse('$baseUrl/api/sync/usuarios');
      final response = await http.get(uri).timeout(const Duration(milliseconds: ApiConstants.receiveTimeoutMs));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true) {
          final data = body['data'] as List;
          for (final item in data) {
            final usuario = UsuarioModel.fromJson(item);
            await _db.insertUsuario(usuario);
          }
        }
      } else {
        errors.add('Error pull usuarios: ${response.statusCode}');
      }
    } catch (e) {
      errors.add('Excepción pull usuarios: $e');
    }
    return errors;
  }

  Future<List<String>> _pullEmpleados(String baseUrl) async {
    final errors = <String>[];
    try {
      final uri = Uri.parse('$baseUrl/api/sync/empleados');
      final response = await http.get(uri).timeout(const Duration(milliseconds: ApiConstants.receiveTimeoutMs));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true) {
          final data = body['data'] as List;
          for (final item in data) {
            final serverEmp = EmpleadoModel.fromJson(item);
            final localEmp = await _db.getEmpleadoByCedula(serverEmp.cedula);

            EmpleadoModel finalEmp = serverEmp;
            if (localEmp != null) {
              if (!localEmp.sincronizado) {
                // Si el empleado local no está sincronizado aún, el Kiosko local es la fuente de verdad.
                // No sobreescribimos los datos locales reales con un registro cascarón vacío del servidor.
                continue;
              } else {
                // Si ya está sincronizado, el servidor es la fuente de verdad,
                // pero si el servidor no tiene vector facial y el local sí, conservamos el local.
                finalEmp = serverEmp.copyWith(
                  sincronizado: true,
                  mapaVectorFoto: serverEmp.mapaVectorFoto.isEmpty ? localEmp.mapaVectorFoto : serverEmp.mapaVectorFoto,
                );
              }
            } else {
              // Si no existe en SQLite, lo insertamos
              finalEmp = serverEmp.copyWith(sincronizado: true);
            }
            await _db.insertEmpleado(finalEmp);
          }
        }
      } else {
        errors.add('Error pull empleados: ${response.statusCode}');
      }
    } catch (e) {
      errors.add('Excepción pull empleados: $e');
    }
    return errors;
  }

  Future<List<String>> _pullPermisos(String baseUrl) async {
    final errors = <String>[];
    try {
      final uri = Uri.parse('$baseUrl/api/sync/permisos');
      final response = await http.get(uri).timeout(const Duration(milliseconds: ApiConstants.receiveTimeoutMs));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true) {
          final data = body['data'] as List;
          for (final item in data) {
            final permiso = PermisoModel.fromJson(item).copyWith(sincronizado: true);
            await _db.insertPermiso(permiso);
          }
        }
      } else {
        errors.add('Error pull permisos: ${response.statusCode}');
      }
    } catch (e) {
      errors.add('Excepción pull permisos: $e');
    }
    return errors;
  }

  Future<List<String>> _pullIncapacidades(String baseUrl) async {
    final errors = <String>[];
    try {
      final uri = Uri.parse('$baseUrl/api/sync/incapacidades');
      final response = await http.get(uri).timeout(const Duration(milliseconds: ApiConstants.receiveTimeoutMs));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true) {
          final data = body['data'] as List;
          for (final item in data) {
            final incapacidad = IncapacidadModel.fromJson(item).copyWith(sincronizado: true);
            await _db.insertIncapacidad(incapacidad);
          }
        }
      } else {
        if (response.statusCode != 404) {
          errors.add('Error pull incapacidades: ${response.statusCode}');
        }
      }
    } catch (e) {
      errors.add('Excepción pull incapacidades: $e');
    }
    return errors;
  }

  Future<List<String>> _pullRegistros(String baseUrl) async {
    final errors = <String>[];
    try {
      final uri = Uri.parse('$baseUrl/api/sync/registros');
      final response = await http.get(uri).timeout(const Duration(milliseconds: ApiConstants.receiveTimeoutMs));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true) {
          final data = body['data'] as List;
          for (final item in data) {
            final map = Map<String, dynamic>.from(item);
            map['sincronizado'] = 1;
            final registro = RegistroModel.fromJson(map);
            await _db.insertRegistro(registro);
          }
        }
      } else {
        errors.add('Error pull registros: ${response.statusCode}');
      }
    } catch (e) {
      errors.add('Excepción pull registros: $e');
    }
    return errors;
  }

  Future<List<String>> _pullSecciones(String baseUrl) async {
    final errors = <String>[];
    try {
      final uri = Uri.parse('$baseUrl/api/secciones');
      final response = await http.get(uri).timeout(const Duration(milliseconds: ApiConstants.receiveTimeoutMs));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true) {
          final data = body['data'] as List;
          await _db.saveSecciones(data);
        }
      } else {
        errors.add('Error pull secciones: ${response.statusCode}');
      }
    } catch (e) {
      errors.add('Excepción pull secciones: $e');
    }
    return errors;
  }

  Future<List<String>> _pullTiposAusencia(String baseUrl) async {
    final errors = <String>[];
    try {
      final uri = Uri.parse('$baseUrl/api/tipos-ausencia');
      final response = await http.get(uri).timeout(const Duration(milliseconds: ApiConstants.receiveTimeoutMs));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true) {
          final data = body['data'] as List;
          await _db.saveTiposAusencia(data);
        }
      } else {
        errors.add('Error pull tipos-ausencia: ${response.statusCode}');
      }
    } catch (e) {
      errors.add('Excepción pull tipos-ausencia: $e');
    }
    return errors;
  }

  Future<List<String>> _pullAusentismos(String baseUrl) async {
    final errors = <String>[];
    try {
      final uri = Uri.parse('$baseUrl/api/sync/ausentismos');
      final response = await http.get(uri).timeout(const Duration(milliseconds: ApiConstants.receiveTimeoutMs));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true) {
          final data = body['data'] as List;
          for (final item in data) {
            final map = Map<String, dynamic>.from(item);
            map['sincronizado'] = 1;
            final ausentismo = AusentismoModel.fromMap(map);
            await _db.insertAusentismo(ausentismo);
          }
        }
      } else {
        errors.add('Error pull ausentismos: ${response.statusCode}');
      }
    } catch (e) {
      errors.add('Excepción pull ausentismos: $e');
    }
    return errors;
  }

  Future<(int, List<String>)> _syncAusentismos(String baseUrl) async {
    final pendientes = await _db.getAusentismosPendientes();
    if (pendientes.isEmpty) return (0, <String>[]);

    final errors = <String>[];
    int synced = 0;
    final idsToSync = <String>[];

    try {
      final uri = Uri.parse('$baseUrl/api/sync/ausentismos');
      final body = jsonEncode(pendientes.map((a) => a.toMap()).toList());
      final response = await http
          .post(uri,
              headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(milliseconds: ApiConstants.receiveTimeoutMs));

      if (response.statusCode == 200 || response.statusCode == 201) {
        idsToSync.addAll(pendientes.map((a) => a.id));
        synced = await _db.marcarAusentismosSincronizados(idsToSync);
      } else {
        errors.add('Error sync ausentismos: ${response.statusCode}');
      }
    } catch (e) {
      errors.add('Excepción sync ausentismos: $e');
    }

    return (synced, errors);
  }

  Future<List<String>> _pushConvocatorias(String baseUrl) async {
    final errors = <String>[];
    
    // 1. Subir convocatorias
    try {
      final convocatorias = await _db.getConvocatoriasPendientes();
      if (convocatorias.isNotEmpty) {
        final uri = Uri.parse('$baseUrl/api/sync/convocatorias');
        final body = jsonEncode(convocatorias.map((c) => c.toMap()).toList());
        final response = await http
            .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
            .timeout(const Duration(milliseconds: ApiConstants.receiveTimeoutMs));

        if (response.statusCode == 200 || response.statusCode == 201) {
          final ids = convocatorias.map((c) => c.id).toList();
          await _db.marcarConvocatoriasSincronizadas(ids);
        } else {
          errors.add('Error push convocatorias: ${response.statusCode}');
        }
      }
    } catch (e) {
      errors.add('Excepción push convocatorias: $e');
    }

    // 2. Subir asignaciones de personal
    try {
      final asignaciones = await _db.getConvocatoriaEmpleadosPendientes();
      if (asignaciones.isNotEmpty) {
        final uri = Uri.parse('$baseUrl/api/sync/convocatoria-empleados');
        final body = jsonEncode(asignaciones.map((ce) => ce.toMap()).toList());
        final response = await http
            .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
            .timeout(const Duration(milliseconds: ApiConstants.receiveTimeoutMs));

        if (response.statusCode == 200 || response.statusCode == 201) {
          final keyPairs = asignaciones.map((ce) => {
            'convocatoria_id': ce.convocatoriaId,
            'cedula_empleado': ce.cedulaEmpleado,
          }).toList();
          await _db.marcarConvocatoriaEmpleadosSincronizados(keyPairs);
        } else {
          errors.add('Error push asignaciones convocatoria: ${response.statusCode}');
        }
      }
    } catch (e) {
      errors.add('Excepción push asignaciones convocatoria: $e');
    }

    return errors;
  }

  Future<List<String>> _pullConvocatorias(String baseUrl) async {
    final errors = <String>[];

    // 1. Descargar convocatorias
    try {
      final uri = Uri.parse('$baseUrl/api/sync/convocatorias');
      final response = await http.get(uri).timeout(const Duration(milliseconds: ApiConstants.receiveTimeoutMs));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true) {
          final data = body['data'] as List;
          for (final item in data) {
            final conv = ConvocatoriaModel.fromMap(Map<String, dynamic>.from(item)..['sincronizado'] = 1);
            await _db.insertConvocatoria(conv);
          }
        }
      } else {
        errors.add('Error pull convocatorias: ${response.statusCode}');
      }
    } catch (e) {
      errors.add('Excepción pull convocatorias: $e');
    }

    // 2. Descargar asignaciones de personal
    try {
      final uri = Uri.parse('$baseUrl/api/sync/convocatoria-empleados');
      final response = await http.get(uri).timeout(const Duration(milliseconds: ApiConstants.receiveTimeoutMs));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true) {
          final data = body['data'] as List;
          for (final item in data) {
            final ce = ConvocatoriaEmpleadoModel.fromMap(Map<String, dynamic>.from(item)..['sincronizado'] = 1);
            await _db.insertConvocado(ce);
          }
        }
      } else {
        errors.add('Error pull asignaciones de convocatorias: ${response.statusCode}');
      }
    } catch (e) {
      errors.add('Excepción pull asignaciones de convocatorias: $e');
    }

    return errors;
  }
}

class SyncResult {
  final int registros;
  final int permisos;
  final List<String> errors;
  bool get hasErrors => errors.isNotEmpty;

  SyncResult({
    required this.registros,
    required this.permisos,
    required this.errors,
  });

  @override
  String toString() =>
      'SyncResult(registros: $registros, permisos: $permisos, errors: $errors)';
}
