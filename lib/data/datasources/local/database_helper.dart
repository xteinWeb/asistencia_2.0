import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/constants/db_constants.dart';
import '../../models/empleado_model.dart';
import '../../models/horario_model.dart';
import '../../../domain/entities/horario.dart';
import '../../models/registro_model.dart';
import '../../models/usuario_model.dart';
import '../../models/permiso_model.dart';
import '../../models/configuracion_model.dart';
import '../../models/ausentismo_model.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _db;

  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  Future<Database> get database async {
    if (kIsWeb) {
      throw UnsupportedError(
        'SQLite is not supported on Web. Use online API direct methods instead.',
      );
    }
    _db ??= await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    // On Desktop (Windows/Linux/macOS) use sqflite_common_ffi
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, DbConstants.dbName);

    final db = await openDatabase(
      path,
      version: DbConstants.dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    // Normalizar base de datos eliminando duplicados de UUIDs en mayúsculas/minúsculas de forma robusta
    try {
      await db.execute('''
        DELETE FROM registros 
        WHERE rowid NOT IN (
          SELECT MIN(rowid) 
          FROM registros 
          GROUP BY LOWER(id)
        )
      ''');

      await db.execute('''
        DELETE FROM permisos 
        WHERE rowid NOT IN (
          SELECT MIN(rowid) 
          FROM permisos 
          GROUP BY LOWER(id)
        )
      ''');

      await db.execute('UPDATE registros SET id = LOWER(id)');
      await db.execute('UPDATE permisos SET id = LOWER(id)');
      debugPrint(
        '[SQLite] Normalización de base de datos y eliminación de duplicados completada con éxito.',
      );
    } catch (e) {
      debugPrint(
        'Error al normalizar e integrar UUIDs de registros/permisos: $e',
      );
    }

    return db;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE ${DbConstants.tableUsuarios} (
        usuario       TEXT PRIMARY KEY,
        nombre        TEXT NOT NULL,
        contrasena    TEXT NOT NULL,
        rol           TEXT NOT NULL,
        estado        TEXT NOT NULL DEFAULT 'ACTIVO',
        unidad_negocio TEXT NOT NULL DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE ${DbConstants.tableHorarios} (
        id_horario  TEXT PRIMARY KEY,
        descripcion TEXT NOT NULL,
        estado      TEXT NOT NULL DEFAULT 'ACTIVO'
      )
    ''');

    await db.execute('''
      CREATE TABLE itm_horarios (
        id_horario  TEXT NOT NULL,
        item        INTEGER NOT NULL,
        inicio      TEXT NOT NULL,
        final       TEXT NOT NULL,
        lunes       INTEGER NOT NULL,
        martes      INTEGER NOT NULL,
        miercoles   INTEGER NOT NULL,
        jueves      INTEGER NOT NULL,
        viernes     INTEGER NOT NULL,
        sabado      INTEGER NOT NULL,
        domingo     INTEGER NOT NULL,
        tipo        TEXT NOT NULL,
        PRIMARY KEY (id_horario, item)
      )
    ''');

    await db.execute('''
      CREATE TABLE ${DbConstants.tableEmpleados} (
        cedula              TEXT PRIMARY KEY,
        nombre              TEXT NOT NULL,
        mapa_vector_foto    TEXT,
        horario_id          TEXT,
        fecha_ini_contrato  TEXT,
        fecha_fin_contrato  TEXT,
        sincronizado        INTEGER NOT NULL DEFAULT 0,
        estado              TEXT NOT NULL DEFAULT 'ACTIVO',
        sede_principal      TEXT,
        id_seccion          TEXT,
        tipo                TEXT,
        FOREIGN KEY (horario_id) REFERENCES ${DbConstants.tableHorarios}(id_horario)
      )
    ''');

    await db.execute('''
      CREATE TABLE secciones (
        id_seccion  TEXT PRIMARY KEY,
        descripcion TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE tipo_ausencia (
        sigla  TEXT PRIMARY KEY,
        nombre TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ausentismos (
        id              TEXT PRIMARY KEY,
        cedula_empleado TEXT NOT NULL,
        fecha           TEXT NOT NULL,
        sigla_ausencia  TEXT NOT NULL,
        observacion     TEXT,
        sincronizado    INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (cedula_empleado) REFERENCES ${DbConstants.tableEmpleados}(cedula)
      )
    ''');

    await db.execute('''
      CREATE TABLE ${DbConstants.tableRegistros} (
        id              TEXT PRIMARY KEY,
        fecha_hora      TEXT NOT NULL,
        cedula          TEXT NOT NULL,
        evento          TEXT NOT NULL,
        duracion        TEXT,
        tipo            TEXT NOT NULL,
        unidad_negocio  TEXT NOT NULL,
        sincronizado    INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (cedula) REFERENCES ${DbConstants.tableEmpleados}(cedula)
      )
    ''');

    await db.execute('''
      CREATE TABLE ${DbConstants.tablePermisos} (
        id                   TEXT PRIMARY KEY,
        usuario_registrador  TEXT NOT NULL,
        cedula_empleado      TEXT NOT NULL,
        fecha_hora           TEXT NOT NULL,
        tipo                 TEXT NOT NULL,
        fecha_inicio         TEXT NOT NULL,
        fecha_final          TEXT NOT NULL,
        observacion          TEXT,
        sincronizado         INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (cedula_empleado) REFERENCES ${DbConstants.tableEmpleados}(cedula)
      )
    ''');

    await db.execute('''
      CREATE TABLE ${DbConstants.tableConfiguracion} (
        clave TEXT PRIMARY KEY,
        valor TEXT NOT NULL
      )
    ''');

    await _seedDefaultConfig(db);
    await _seedDefaultAdmin(db);
    await _seedDefaultTiposAusencia(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('DROP TABLE IF EXISTS ${DbConstants.tableRegistros}');
      await db.execute('DROP TABLE IF EXISTS ${DbConstants.tablePermisos}');

      await db.execute('''
        CREATE TABLE ${DbConstants.tableRegistros} (
          id              TEXT PRIMARY KEY,
          fecha_hora      TEXT NOT NULL,
          cedula          TEXT NOT NULL,
          evento          TEXT NOT NULL,
          duracion        TEXT,
          tipo            TEXT NOT NULL,
          unidad_negocio  TEXT NOT NULL,
          sincronizado    INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (cedula) REFERENCES ${DbConstants.tableEmpleados}(cedula)
        )
      ''');

      await db.execute('''
        CREATE TABLE ${DbConstants.tablePermisos} (
          id                   TEXT PRIMARY KEY,
          usuario_registrador  TEXT NOT NULL,
          cedula_empleado      TEXT NOT NULL,
          fecha_hora           TEXT NOT NULL,
          tipo                 TEXT NOT NULL,
          fecha_inicio         TEXT NOT NULL,
          fecha_final          TEXT NOT NULL,
          sincronizado         INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (cedula_empleado) REFERENCES ${DbConstants.tableEmpleados}(cedula)
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('PRAGMA foreign_keys = OFF');
      await db.execute('DROP TABLE IF EXISTS ${DbConstants.tableEmpleados}');
      await db.execute('DROP TABLE IF EXISTS ${DbConstants.tableHorarios}');

      await db.execute('''
        CREATE TABLE ${DbConstants.tableHorarios} (
          id_horario  TEXT PRIMARY KEY,
          hora_inicio TEXT NOT NULL,
          hora_final  TEXT NOT NULL,
          tipo        TEXT NOT NULL,
          dias        TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE ${DbConstants.tableEmpleados} (
          cedula              TEXT PRIMARY KEY,
          nombre              TEXT NOT NULL,
          mapa_vector_foto    TEXT,
          horario_id          TEXT,
          fecha_ini_contrato  TEXT,
          fecha_fin_contrato  TEXT,
          sincronizado        INTEGER NOT NULL DEFAULT 0,
          estado              TEXT NOT NULL DEFAULT 'ACTIVO',
          FOREIGN KEY (horario_id) REFERENCES ${DbConstants.tableHorarios}(id_horario)
        )
      ''');

      await db.execute('PRAGMA foreign_keys = ON');
    }
    if (oldVersion < 4) {
      try {
        await db.execute(
          "ALTER TABLE ${DbConstants.tableEmpleados} ADD COLUMN estado TEXT NOT NULL DEFAULT 'ACTIVO'",
        );
      } catch (e) {
        debugPrint('Error al agregar columna estado en SQLite: $e');
      }
    }
    if (oldVersion < 5) {
      try {
        await db.execute(
          "ALTER TABLE ${DbConstants.tableEmpleados} ADD COLUMN sede_principal TEXT",
        );
        await db.execute(
          "ALTER TABLE ${DbConstants.tableEmpleados} ADD COLUMN id_seccion TEXT",
        );
        await db.execute('''
          CREATE TABLE secciones (
            id_seccion  TEXT PRIMARY KEY,
            descripcion TEXT NOT NULL
          )
        ''');
      } catch (e) {
        debugPrint('Error al agregar columnas de sede/sección en SQLite: $e');
      }
    }
    if (oldVersion < 6) {
      try {
        await db.execute(
          "ALTER TABLE ${DbConstants.tableEmpleados} ADD COLUMN tipo TEXT",
        );
      } catch (e) {
        debugPrint('Error al agregar columna tipo en SQLite: $e');
      }
    }
    if (oldVersion < 7) {
      try {
        await db.execute('''
          CREATE TABLE tipo_ausencia (
            sigla  TEXT PRIMARY KEY,
            nombre TEXT NOT NULL
          )
        ''');
        
        await db.execute('''
          CREATE TABLE ausentismos (
            id              TEXT PRIMARY KEY,
            cedula_empleado TEXT NOT NULL,
            fecha           TEXT NOT NULL,
            sigla_ausencia  TEXT NOT NULL,
            observacion     TEXT,
            sincronizado    INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (cedula_empleado) REFERENCES ${DbConstants.tableEmpleados}(cedula)
          )
        ''');
        
        // Sembrar datos iniciales locales
        final tipos = [
          {'sigla': 'EG', 'nombre': 'INCAPACIDAD POR ENFERMEDAD GENERAL'},
          {'sigla': 'AL', 'nombre': 'INCAPACIDAD POR ACCIDENTE LABORAL'},
          {'sigla': 'EL', 'nombre': 'ENFERMEDAD LABORAL'},
          {'sigla': 'SC', 'nombre': 'FALTA SIN JUSTA CAUSA'},
          {'sigla': 'SU', 'nombre': 'SUSPENCIÓN'},
          {'sigla': 'LIC', 'nombre': 'LICENICIA'},
          {'sigla': 'LLT', 'nombre': 'LLEGADA TARDE'},
          {'sigla': 'PE', 'nombre': 'PERMISO'},
          {'sigla': 'LU', 'nombre': 'LICENCIA POR LUTO'},
          {'sigla': 'LM', 'nombre': 'LICENCIA DE MATERNIDAD'},
          {'sigla': 'VAC', 'nombre': 'VACACIONES'},
          {'sigla': 'AISL', 'nombre': 'AISLAMIENO'},
          {'sigla': 'DV', 'nombre': 'DEVOLUCIÓN'},
          {'sigla': 'TFE', 'nombre': 'TRABAJO POR FURA DE LA EMPRESA'},
        ];
        for (final t in tipos) {
          await db.insert('tipo_ausencia', t, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      } catch (e) {
        debugPrint('Error al agregar tablas de ausentismo en SQLite: $e');
      }
    }
    if (oldVersion < 8) {
      try {
        await db.execute(
          "ALTER TABLE ${DbConstants.tablePermisos} ADD COLUMN observacion TEXT",
        );
      } catch (e) {
        debugPrint('Error al agregar columna observacion en SQLite: $e');
      }
    }
    if (oldVersion < 9) {
      try {
        await db.execute(
          "ALTER TABLE ausentismos ADD COLUMN observacion TEXT",
        );
      } catch (e) {
        debugPrint('Error al agregar columna observacion en SQLite (ausentismos): $e');
      }
    }
    if (oldVersion < 10) {
      try {
        await db.execute('PRAGMA foreign_keys = OFF');
        await db.execute('DROP TABLE IF EXISTS ${DbConstants.tableHorarios}');
        await db.execute('''
          CREATE TABLE ${DbConstants.tableHorarios} (
            id_horario  TEXT PRIMARY KEY,
            descripcion TEXT NOT NULL,
            estado      TEXT NOT NULL DEFAULT 'ACTIVO'
          )
        ''');
        
        await db.execute('DROP TABLE IF EXISTS itm_horarios');
        await db.execute('''
          CREATE TABLE itm_horarios (
            id_horario  TEXT NOT NULL,
            item        INTEGER NOT NULL,
            inicio      TEXT NOT NULL,
            final       TEXT NOT NULL,
            lunes       INTEGER NOT NULL,
            martes      INTEGER NOT NULL,
            miercoles   INTEGER NOT NULL,
            jueves      INTEGER NOT NULL,
            viernes     INTEGER NOT NULL,
            sabado      INTEGER NOT NULL,
            domingo     INTEGER NOT NULL,
            tipo        TEXT NOT NULL,
            PRIMARY KEY (id_horario, item)
          )
        ''');
        await db.execute('PRAGMA foreign_keys = ON');
      } catch (e) {
        debugPrint('Error al migrar horarios a version 10: $e');
      }
    }
  }

  Future<void> _seedDefaultConfig(Database db) async {
    final defaults = [
      {'clave': DbConstants.cfgUrlApi, 'valor': ApiConstants.defaultBaseUrl},
      {'clave': DbConstants.cfgFrecuenciaSync, 'valor': '15'},
      {'clave': DbConstants.cfgUnidadNegocio, 'valor': 'Principal'},
      {'clave': DbConstants.cfgUmbralFacial, 'valor': '0.6'},
      {'clave': DbConstants.cfgPermitirManual, 'valor': '0'},
    ];
    for (final entry in defaults) {
      await db.insert(
        DbConstants.tableConfiguracion,
        entry,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> _seedDefaultAdmin(Database db) async {
    await db.insert(DbConstants.tableUsuarios, {
      'usuario': 'admin',
      'nombre': 'Administrador',
      'contrasena': 'admin123',
      'rol': 'ADMIN',
      'estado': 'ACTIVO',
      'unidad_negocio': 'Principal',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _seedDefaultTiposAusencia(Database db) async {
    final tipos = [
      {'sigla': 'EG', 'nombre': 'INCAPACIDAD POR ENFERMEDAD GENERAL'},
      {'sigla': 'AL', 'nombre': 'INCAPACIDAD POR ACCIDENTE LABORAL'},
      {'sigla': 'EL', 'nombre': 'ENFERMEDAD LABORAL'},
      {'sigla': 'SC', 'nombre': 'FALTA SIN JUSTA CAUSA'},
      {'sigla': 'SU', 'nombre': 'SUSPENCIÓN'},
      {'sigla': 'LIC', 'nombre': 'LICENICIA'},
      {'sigla': 'LLT', 'nombre': 'LLEGADA TARDE'},
      {'sigla': 'PE', 'nombre': 'PERMISO'},
      {'sigla': 'LU', 'nombre': 'LICENCIA POR LUTO'},
      {'sigla': 'LM', 'nombre': 'LICENCIA DE MATERNIDAD'},
      {'sigla': 'VAC', 'nombre': 'VACACIONES'},
      {'sigla': 'AISL', 'nombre': 'AISLAMIENO'},
      {'sigla': 'DV', 'nombre': 'DEVOLUCIÓN'},
      {'sigla': 'TFE', 'nombre': 'TRABAJO POR FURA DE LA EMPRESA'},
    ];
    for (final t in tipos) {
      await db.insert('tipo_ausencia', t, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  // ─── EMPLEADOS ────────────────────────────────────────────────────────────

  Future<int> insertEmpleado(EmpleadoModel empleado) async {
    if (kIsWeb) {
      final baseUrl =
          await getConfig(DbConstants.cfgUrlApi) ?? ApiConstants.defaultBaseUrl;
      final response = await http.post(
        Uri.parse('$baseUrl/api/sync/empleados'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode([empleado.copyWith(sincronizado: true).toMap()]),
      );
      return response.statusCode == 200 || response.statusCode == 201 ? 1 : 0;
    }

    final db = await database;
    return db.insert(
      DbConstants.tableEmpleados,
      empleado.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<EmpleadoModel?> getEmpleadoByCedula(String cedula) async {
    if (kIsWeb) {
      final list = await getAllEmpleados();
      final results = list.where((e) => e.cedula == cedula);
      return results.isEmpty ? null : results.first;
    }

    final db = await database;
    final rows = await db.query(
      DbConstants.tableEmpleados,
      where: 'cedula = ?',
      whereArgs: [cedula],
    );
    if (rows.isEmpty) return null;
    return EmpleadoModel.fromMap(rows.first);
  }

  Future<List<EmpleadoModel>> getAllEmpleados() async {
    if (kIsWeb) {
      final baseUrl =
          await getConfig(DbConstants.cfgUrlApi) ?? ApiConstants.defaultBaseUrl;
      final response = await http.get(Uri.parse('$baseUrl/api/sync/empleados'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = (data['data'] as List).map((e) {
          final map = Map<String, dynamic>.from(e);
          map['sincronizado'] = 1;
          return EmpleadoModel.fromMap(map);
        }).toList();
        return list;
      }
      return [];
    }

    final db = await database;
    final rows = await db.query(DbConstants.tableEmpleados);
    return rows.map(EmpleadoModel.fromMap).toList();
  }

  Future<int> updateEmpleado(EmpleadoModel empleado) async {
    if (kIsWeb) {
      return await insertEmpleado(empleado);
    }

    final db = await database;
    return db.update(
      DbConstants.tableEmpleados,
      empleado.toMap(),
      where: 'cedula = ?',
      whereArgs: [empleado.cedula],
    );
  }

  Future<int> deleteEmpleado(String cedula) async {
    if (kIsWeb) {
      final baseUrl =
          await getConfig(DbConstants.cfgUrlApi) ?? ApiConstants.defaultBaseUrl;
      final response = await http.delete(
        Uri.parse('$baseUrl/api/sync/empleados/$cedula'),
      );
      return response.statusCode == 200 ? 1 : 0;
    }

    final db = await database;
    return db.delete(
      DbConstants.tableEmpleados,
      where: 'cedula = ?',
      whereArgs: [cedula],
    );
  }

  // ─── HORARIOS ─────────────────────────────────────────────────────────────

  Future<int> insertHorario(HorarioModel horario) async {
    if (kIsWeb) {
      return 1;
    }

    final db = await database;
    final map = horario.toMap();
    if (map['id_horario'] == null) {
      map['id_horario'] = const Uuid().v4();
    }
    final id = map['id_horario'] as String;

    await db.insert(
      DbConstants.tableHorarios,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await db.delete(
      'itm_horarios',
      where: 'id_horario = ?',
      whereArgs: [id],
    );

    for (final item in horario.items) {
      await db.insert(
        'itm_horarios',
        item.toMap(id),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    return 1;
  }

  Future<HorarioModel?> getHorarioById(String id) async {
    if (kIsWeb) {
      final list = await getAllHorarios();
      final results = list.where((h) => h.idHorario == id);
      return results.isEmpty ? null : results.first;
    }

    final db = await database;
    final rows = await db.query(
      DbConstants.tableHorarios,
      where: 'id_horario = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;

    final itemRows = await db.query(
      'itm_horarios',
      where: 'id_horario = ?',
      whereArgs: [id],
      orderBy: 'item ASC',
    );

    final items = itemRows.map(HorarioItem.fromMap).toList();
    return HorarioModel.fromMap(rows.first, items: items);
  }

  Future<List<HorarioModel>> getAllHorarios() async {
    if (kIsWeb) {
      final baseUrl =
          await getConfig(DbConstants.cfgUrlApi) ?? ApiConstants.defaultBaseUrl;
      final response = await http.get(Uri.parse('$baseUrl/api/sync/horarios'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = (data['data'] as List)
            .map((h) => HorarioModel.fromJson(Map<String, dynamic>.from(h)))
            .toList();
        return list;
      }
      return [];
    }

    final db = await database;

    final nullRows = await db.query(
      DbConstants.tableHorarios,
      where: 'id_horario IS NULL OR id_horario = ?',
      whereArgs: [''],
    );
    if (nullRows.isNotEmpty) {
      await db.delete(
        DbConstants.tableHorarios,
        where: 'id_horario IS NULL OR id_horario = ?',
        whereArgs: [''],
      );
    }

    final rows = await db.query(DbConstants.tableHorarios);
    final allItemsRows = await db.query('itm_horarios', orderBy: 'item ASC');

    final Map<String, List<HorarioItem>> itemsMap = {};
    for (final r in allItemsRows) {
      final id = r['id_horario'] as String;
      itemsMap.putIfAbsent(id, () => []).add(HorarioItem.fromMap(r));
    }

    return rows.map((row) {
      final id = row['id_horario'] as String;
      return HorarioModel.fromMap(row, items: itemsMap[id] ?? []);
    }).toList();
  }

  Future<int> deleteHorario(String id) async {
    if (kIsWeb) {
      return 1;
    }

    final db = await database;
    await db.delete(
      'itm_horarios',
      where: 'id_horario = ?',
      whereArgs: [id],
    );
    return db.delete(
      DbConstants.tableHorarios,
      where: 'id_horario = ?',
      whereArgs: [id],
    );
  }

  // ─── REGISTROS ────────────────────────────────────────────────────────────

  Future<int> insertRegistro(RegistroModel registro) async {
    if (kIsWeb) {
      final baseUrl =
          await getConfig(DbConstants.cfgUrlApi) ?? ApiConstants.defaultBaseUrl;
      final response = await http.post(
        Uri.parse('$baseUrl/api/sync/registros'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode([registro.toMap()..['sincronizado'] = 1]),
      );
      return response.statusCode == 200 || response.statusCode == 201 ? 1 : 0;
    }

    final db = await database;
    final map = registro.toMap();
    if (map['id'] == null) {
      map['id'] = const Uuid().v4();
    }
    return db.insert(
      DbConstants.tableRegistros,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<RegistroModel>> getRegistrosPorCedula(String cedula) async {
    if (kIsWeb) {
      final list = await getRegistrosHoy();
      return list.where((r) => r.cedula == cedula).toList();
    }

    final db = await database;
    final rows = await db.query(
      DbConstants.tableRegistros,
      where: 'cedula = ?',
      whereArgs: [cedula],
      orderBy: 'fecha_hora DESC',
    );
    return rows.map(RegistroModel.fromMap).toList();
  }

  Future<List<RegistroModel>> getRegistrosPendientes() async {
    if (kIsWeb) return [];

    final db = await database;
    final rows = await db.query(
      DbConstants.tableRegistros,
      where: 'sincronizado = 0',
      orderBy: 'fecha_hora ASC',
    );
    return rows.map(RegistroModel.fromMap).toList();
  }

  Future<List<RegistroModel>> getAllRegistros() async {
    if (kIsWeb) {
      final baseUrl =
          await getConfig(DbConstants.cfgUrlApi) ?? ApiConstants.defaultBaseUrl;
      final response = await http.get(Uri.parse('$baseUrl/api/sync/registros'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = (data['data'] as List).map((r) {
          final map = Map<String, dynamic>.from(r);
          map['sincronizado'] = 1;
          return RegistroModel.fromMap(map);
        }).toList();
        return list;
      }
      return [];
    }

    final db = await database;
    final rows = await db.query(
      DbConstants.tableRegistros,
      orderBy: 'fecha_hora DESC',
    );
    return rows.map(RegistroModel.fromMap).toList();
  }

  Future<List<RegistroModel>> getRegistrosHoy() async {
    if (kIsWeb) {
      final baseUrl =
          await getConfig(DbConstants.cfgUrlApi) ?? ApiConstants.defaultBaseUrl;
      final response = await http.get(Uri.parse('$baseUrl/api/sync/registros'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = (data['data'] as List).map((r) {
          final map = Map<String, dynamic>.from(r);
          map['sincronizado'] = 1;
          return RegistroModel.fromMap(map);
        }).toList();
        return list;
      }
      return [];
    }

    final db = await database;
    final hoy = DateTime.now().toIso8601String().substring(0, 10);
    final rows = await db.query(
      DbConstants.tableRegistros,
      where: "fecha_hora LIKE ?",
      whereArgs: ['$hoy%'],
      orderBy: 'fecha_hora DESC',
    );
    return rows.map(RegistroModel.fromMap).toList();
  }

  Future<int> marcarRegistroSincronizado(String id) async {
    if (kIsWeb) return 1;

    final db = await database;
    return db.update(
      DbConstants.tableRegistros,
      {'sincronizado': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> marcarRegistrosSincronizados(List<String> ids) async {
    if (kIsWeb) return ids.length;
    if (ids.isEmpty) return 0;
    final db = await database;
    final placeholders = ids.map((_) => '?').join(',');
    return db.rawUpdate(
      'UPDATE ${DbConstants.tableRegistros} SET sincronizado = 1 WHERE id IN ($placeholders)',
      ids,
    );
  }

  // ─── USUARIOS ─────────────────────────────────────────────────────────────

  Future<UsuarioModel?> getUsuario(String usuario, String contrasena) async {
    if (kIsWeb) {
      final baseUrl =
          await getConfig(DbConstants.cfgUrlApi) ?? ApiConstants.defaultBaseUrl;
      final response = await http.get(Uri.parse('$baseUrl/api/sync/usuarios'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = (data['data'] as List)
            .map((u) => UsuarioModel.fromMap(Map<String, dynamic>.from(u)))
            .toList();
        final results = list.where(
          (u) =>
              u.usuario == usuario &&
              u.contrasena == contrasena &&
              u.estado == 'ACTIVO',
        );
        return results.isEmpty ? null : results.first;
      }
      return null;
    }

    final db = await database;
    final rows = await db.query(
      DbConstants.tableUsuarios,
      where: 'usuario = ? AND contrasena = ? AND estado = ?',
      whereArgs: [usuario, contrasena, 'ACTIVO'],
    );
    if (rows.isEmpty) return null;
    return UsuarioModel.fromMap(rows.first);
  }

  Future<int> insertUsuario(UsuarioModel usuario) async {
    if (kIsWeb) return 1;

    final db = await database;
    return db.insert(
      DbConstants.tableUsuarios,
      usuario.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<UsuarioModel>> getAllUsuarios() async {
    if (kIsWeb) {
      final baseUrl =
          await getConfig(DbConstants.cfgUrlApi) ?? ApiConstants.defaultBaseUrl;
      final response = await http.get(Uri.parse('$baseUrl/api/sync/usuarios'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = (data['data'] as List)
            .map((u) => UsuarioModel.fromMap(Map<String, dynamic>.from(u)))
            .toList();
        return list;
      }
      return [];
    }

    final db = await database;
    final rows = await db.query(DbConstants.tableUsuarios);
    return rows.map(UsuarioModel.fromMap).toList();
  }

  // ─── PERMISOS ─────────────────────────────────────────────────────────────

  Future<int> insertPermiso(PermisoModel permiso) async {
    final finalPermiso = permiso.id != null
        ? permiso
        : permiso.copyWith(id: const Uuid().v4());

    if (kIsWeb) {
      final baseUrl =
          await getConfig(DbConstants.cfgUrlApi) ?? ApiConstants.defaultBaseUrl;
      final response = await http.post(
        Uri.parse('$baseUrl/api/sync/permisos'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode([finalPermiso.copyWith(sincronizado: true).toMap()]),
      );
      return response.statusCode == 200 || response.statusCode == 201 ? 1 : 0;
    }

    final db = await database;
    final map = finalPermiso.toMap();
    return db.insert(
      DbConstants.tablePermisos,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<PermisoModel?> getPermisoActivoByCedula(String cedula) async {
    if (kIsWeb) {
      final baseUrl =
          await getConfig(DbConstants.cfgUrlApi) ?? ApiConstants.defaultBaseUrl;
      final response = await http.get(Uri.parse('$baseUrl/api/sync/permisos'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = (data['data'] as List)
            .map((p) => PermisoModel.fromMap(Map<String, dynamic>.from(p)))
            .toList();
        final ahora = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
        final results = list.where(
          (p) =>
              p.cedulaEmpleado == cedula &&
              p.fechaInicio.compareTo(ahora) <= 0 &&
              p.fechaFinal.compareTo(ahora) >= 0,
        );
        return results.isEmpty ? null : results.first;
      }
      return null;
    }

    final db = await database;
    final ahora = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final rows = await db.query(
      DbConstants.tablePermisos,
      where: 'cedula_empleado = ? AND fecha_inicio <= ? AND fecha_final >= ?',
      whereArgs: [cedula, ahora, ahora],
      orderBy: 'fecha_hora DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PermisoModel.fromMap(rows.first);
  }

  Future<List<PermisoModel>> getPermisosByCedula(String cedula) async {
    if (kIsWeb) {
      final baseUrl =
          await getConfig(DbConstants.cfgUrlApi) ?? ApiConstants.defaultBaseUrl;
      final response = await http.get(Uri.parse('$baseUrl/api/sync/permisos'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = (data['data'] as List)
            .map((p) => PermisoModel.fromMap(Map<String, dynamic>.from(p)))
            .toList();
        return list.where((p) => p.cedulaEmpleado == cedula).toList();
      }
      return [];
    }

    final db = await database;
    final rows = await db.query(
      DbConstants.tablePermisos,
      where: 'cedula_empleado = ?',
      whereArgs: [cedula],
      orderBy: 'fecha_inicio ASC',
    );
    return rows.map(PermisoModel.fromMap).toList();
  }

  Future<List<PermisoModel>> getPermisosPendientes() async {
    if (kIsWeb) return [];

    final db = await database;
    final rows = await db.query(
      DbConstants.tablePermisos,
      where: 'sincronizado = 0',
    );
    return rows.map(PermisoModel.fromMap).toList();
  }

  Future<List<PermisoModel>> getAllPermisos() async {
    if (kIsWeb) {
      final baseUrl =
          await getConfig(DbConstants.cfgUrlApi) ?? ApiConstants.defaultBaseUrl;
      final response = await http.get(Uri.parse('$baseUrl/api/sync/permisos'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = (data['data'] as List).map((p) {
          final map = Map<String, dynamic>.from(p);
          map['sincronizado'] = 1;
          return PermisoModel.fromMap(map);
        }).toList();
        return list;
      }
      return [];
    }

    final db = await database;
    final rows = await db.query(
      DbConstants.tablePermisos,
      orderBy: 'fecha_hora DESC',
    );
    return rows.map(PermisoModel.fromMap).toList();
  }

  Future<int> marcarPermisoSincronizado(String id) async {
    if (kIsWeb) return 1;

    final db = await database;
    return db.update(
      DbConstants.tablePermisos,
      {'sincronizado': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ─── CONFIGURACION ────────────────────────────────────────────────────────

  Future<String?> getConfig(String clave) async {
    if (kIsWeb) {
      if (clave == DbConstants.cfgUrlApi) {
        // En la Web, la URL de la API es dinámica y depende enteramente del host y puerto
        // desde el cual se cargó el sitio web. Forzamos null para usar siempre ApiConstants.defaultBaseUrl.
        return null;
      }
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(clave);
    }

    final db = await database;
    final rows = await db.query(
      DbConstants.tableConfiguracion,
      where: 'clave = ?',
      whereArgs: [clave],
    );
    if (rows.isEmpty) return null;
    final valor = rows.first['valor'] as String?;

    if (clave == DbConstants.cfgUrlApi &&
        (valor == 'http://192.168.1.100:8085' ||
            valor == 'http://192.168.11.51:8085')) {
      final newUrl = ApiConstants.defaultBaseUrl;
      await setConfig(DbConstants.cfgUrlApi, newUrl);
      return newUrl;
    }

    return valor;
  }

  Future<void> setConfig(String clave, String valor) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(clave, valor);
      return;
    }

    final db = await database;
    await db.insert(DbConstants.tableConfiguracion, {
      'clave': clave,
      'valor': valor,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ConfiguracionModel>> getAllConfig() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final list = <ConfiguracionModel>[];
      for (final key in keys) {
        final val = prefs.get(key);
        if (val is String) {
          list.add(ConfiguracionModel(clave: key, valor: val));
        }
      }
      // Asegurar default configs si no existen
      if (!keys.contains(DbConstants.cfgUrlApi)) {
        list.add(
          ConfiguracionModel(
            clave: DbConstants.cfgUrlApi,
            valor: ApiConstants.defaultBaseUrl,
          ),
        );
      }
      if (!keys.contains(DbConstants.cfgFrecuenciaSync)) {
        list.add(
          ConfiguracionModel(clave: DbConstants.cfgFrecuenciaSync, valor: '15'),
        );
      }
      if (!keys.contains(DbConstants.cfgUnidadNegocio)) {
        list.add(
          ConfiguracionModel(
            clave: DbConstants.cfgUnidadNegocio,
            valor: 'Principal',
          ),
        );
      }
      if (!keys.contains(DbConstants.cfgUmbralFacial)) {
        list.add(
          ConfiguracionModel(clave: DbConstants.cfgUmbralFacial, valor: '0.6'),
        );
      }
      return list;
    }

    final db = await database;
    final rows = await db.query(DbConstants.tableConfiguracion);
    return rows.map(ConfiguracionModel.fromMap).toList();
  }

  // ─── SECCIONES ────────────────────────────────────────────────────────────

  Future<void> saveSecciones(List<dynamic> data) async {
    if (kIsWeb) return;
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('secciones');
      for (final item in data) {
        await txn.insert('secciones', {
          'id_seccion': item['id_seccion'] as String,
          'descripcion': item['descripcion'] as String,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<Map<String, dynamic>>> getSecciones() async {
    if (kIsWeb) {
      try {
        final baseUrl = await getConfig(DbConstants.cfgUrlApi) ?? ApiConstants.defaultBaseUrl;
        final response = await http.get(Uri.parse('$baseUrl/api/secciones'));
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body);
          if (body['success'] == true) {
            final data = body['data'] as List;
            return data.map((item) => Map<String, dynamic>.from(item)).toList();
          }
        }
      } catch (e) {
        debugPrint('Error al obtener secciones online: $e');
      }
      return [];
    }
    final db = await database;
    return await db.query('secciones', orderBy: 'descripcion ASC');
  }

  Future<String?> getSeccionDescripcion(String idSeccion) async {
    if (kIsWeb) {
      final list = await getSecciones();
      final match = list.where((s) => s['id_seccion'] == idSeccion);
      if (match.isNotEmpty) {
        return match.first['descripcion'] as String?;
      }
      return null;
    }
    final db = await database;
    final rows = await db.query(
      'secciones',
      columns: ['descripcion'],
      where: 'id_seccion = ?',
      whereArgs: [idSeccion],
    );
    if (rows.isEmpty) return null;
    return rows.first['descripcion'] as String?;
  }

  // ─── AUSENTISMOS ──────────────────────────────────────────────────────────

  Future<List<Map<String, String>>> getTiposAusencia() async {
    if (kIsWeb) {
      try {
        final baseUrl = await getConfig(DbConstants.cfgUrlApi) ?? ApiConstants.defaultBaseUrl;
        final response = await http.get(Uri.parse('$baseUrl/api/tipos-ausencia'));
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body);
          if (body['success'] == true) {
            final data = body['data'] as List;
            return data.map((item) => {
              'sigla': (item['sigla'] ?? '').toString(),
              'nombre': (item['nombre'] ?? '').toString(),
            }).toList();
          }
        }
      } catch (e) {
        debugPrint('Error al obtener tipos de ausencia online: $e');
      }
      return [
        {'sigla': 'EG', 'nombre': 'INCAPACIDAD POR ENFERMEDAD GENERAL'},
        {'sigla': 'AL', 'nombre': 'INCAPACIDAD POR ACCIDENTE LABORAL'},
        {'sigla': 'EL', 'nombre': 'ENFERMEDAD LABORAL'},
        {'sigla': 'SC', 'nombre': 'FALTA SIN JUSTA CAUSA'},
        {'sigla': 'SU', 'nombre': 'SUSPENCIÓN'},
        {'sigla': 'LIC', 'nombre': 'LICENICIA'},
        {'sigla': 'LLT', 'nombre': 'LLEGADA TARDE'},
        {'sigla': 'PE', 'nombre': 'PERMISO'},
        {'sigla': 'LU', 'nombre': 'LICENCIA POR LUTO'},
        {'sigla': 'LM', 'nombre': 'LICENCIA DE MATERNIDAD'},
        {'sigla': 'VAC', 'nombre': 'VACACIONES'},
        {'sigla': 'AISL', 'nombre': 'AISLAMIENO'},
        {'sigla': 'DV', 'nombre': 'DEVOLUCIÓN'},
        {'sigla': 'TFE', 'nombre': 'TRABAJO POR FURA DE LA EMPRESA'},
      ];
    }
    final db = await database;
    final rows = await db.query('tipo_ausencia', orderBy: 'nombre ASC');
    return rows.map((r) => {
      'sigla': r['sigla'] as String,
      'nombre': r['nombre'] as String,
    }).toList();
  }

  Future<void> saveTiposAusencia(List<dynamic> data) async {
    if (kIsWeb) return;
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('tipo_ausencia');
      for (final item in data) {
        await txn.insert('tipo_ausencia', {
          'sigla': item['sigla'] as String,
          'nombre': item['nombre'] as String,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<int> insertAusentismo(AusentismoModel ausentismo) async {
    if (kIsWeb) {
      final baseUrl = await getConfig(DbConstants.cfgUrlApi) ?? ApiConstants.defaultBaseUrl;
      final response = await http.post(
        Uri.parse('$baseUrl/api/sync/ausentismos'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode([ausentismo.copyWith(sincronizado: true).toMap()]),
      );
      return response.statusCode == 200 || response.statusCode == 201 ? 1 : 0;
    }

    final db = await database;
    return db.insert(
      'ausentismos',
      ausentismo.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<AusentismoModel>> getAusentismosFecha(String fecha) async {
    if (kIsWeb) {
      final baseUrl = await getConfig(DbConstants.cfgUrlApi) ?? ApiConstants.defaultBaseUrl;
      final response = await http.get(Uri.parse('$baseUrl/api/sync/ausentismos'));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true) {
          final data = body['data'] as List;
          return data
              .map((item) => AusentismoModel.fromMap(Map<String, dynamic>.from(item)..['sincronizado'] = 1))
              .where((a) => a.fecha == fecha)
              .toList();
        }
      }
      return [];
    }

    final db = await database;
    final rows = await db.query(
      'ausentismos',
      where: 'fecha = ?',
      whereArgs: [fecha],
    );
    return rows.map(AusentismoModel.fromMap).toList();
  }

  Future<int> deleteAusentismo(String id) async {
    if (kIsWeb) {
      final baseUrl = await getConfig(DbConstants.cfgUrlApi) ?? ApiConstants.defaultBaseUrl;
      final response = await http.delete(
        Uri.parse('$baseUrl/api/sync/ausentismos/$id'),
      );
      return response.statusCode == 200 ? 1 : 0;
    }

    final db = await database;
    return db.delete(
      'ausentismos',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<AusentismoModel>> getAusentismosPendientes() async {
    if (kIsWeb) return [];
    final db = await database;
    final rows = await db.query(
      'ausentismos',
      where: 'sincronizado = 0',
    );
    return rows.map(AusentismoModel.fromMap).toList();
  }

  Future<int> marcarAusentismoSincronizado(String id) async {
    if (kIsWeb) return 1;
    final db = await database;
    return db.update(
      'ausentismos',
      {'sincronizado': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> marcarAusentismosSincronizados(List<String> ids) async {
    if (kIsWeb) return ids.length;
    if (ids.isEmpty) return 0;
    final db = await database;
    final placeholders = ids.map((_) => '?').join(',');
    return db.rawUpdate(
      'UPDATE ausentismos SET sincronizado = 1 WHERE id IN ($placeholders)',
      ids,
    );
  }

  // ─── UTILS ────────────────────────────────────────────────────────────────

  Future<void> close() async {
    if (kIsWeb) return;

    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }
}
