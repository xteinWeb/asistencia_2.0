import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/auth_response_model.dart';
import 'auth_api_service.dart';

/// Obtener empresas asociadas al usuario desde la API
Future<Object> getEmpresa({required String usuario}) async {
  final api = AuthApiService();

  final datos = {
    'prmAccion': 'USUARIO VALIDO',
    'prmConexion': 'ConexionBD',
    'prmDatos': '{"USUARIO": "$usuario"}',
  };

  try {
    final resultado = await api.postRequest('usuarioValido', datos);
    List<dynamic> data = json.decode(resultado);
    // Extraemos la lista de empresas del primer objeto del JSON
    List<Map<String, String>> listaEmpresas = (data[0]['EMPRESAS'] as List).map(
      (item) {
        return {
          "EMPRESA": item['NOMBRE'].toString(), // El nombre
          "ID": item['ID_UN'].toString(),
          "ID_AS": item['ID_UN_ASOCIADA'].toString(), // El ID
        };
      },
    ).toList();
    return listaEmpresas;
  } catch (e) {
    return {'Error': e.toString()};
  }
}

/// Iniciar sesión en la API externa
Future<String> login({
  required String usuario,
  required String contra,
  required String empresa,
  required String idAs,
}) async {
  final api = AuthApiService();

  final datos = {
    'prmAccion': 'USUARIO CREDENCIALES',
    'prmConexion': 'ConexionBD',
    'prmDatos':
        '{"USUARIO": "$usuario", "CONTRASENA": "$contra","EMPRESA": "$empresa", "ID_UN_ASOCIADA": "$idAs"}',
  };

  try {
    print("datos: $datos");
    final resultado = await api.postRequest('usuarioLogin', datos);
    print(resultado);
    print(resultado.runtimeType);

    AuthResponse auth = AuthResponse.fromJson(resultado);
    print(auth);

    if (auth.errMensaje.isNotEmpty &&
        auth.errMensaje != '0' &&
        auth.errMensaje != 'VALIDO') {
      return auth.errMensaje;
    }

    bool permisoValido = await validarPermiso(
      authResponse: auth,
      idUn: empresa,
      usuario: usuario,
      contra:
          contra, // Guardamos opcionalmente la contraseña para re-autenticación local
    );

    return permisoValido ? '' : "Sin permiso para la aplicación de asistencia";
  } catch (e) {
    return "Error: $e";
  }
}

/// Validar permisos del usuario para la aplicación de Asistencia
Future<bool> validarPermiso({
  required AuthResponse authResponse,
  required String idUn,
  required String usuario,
  String? contra,
}) async {
  final api = AuthApiService();

  final datos = {
    "prmAccion": "consulta aplicacion",
    "prmDatos": '{"USUARIO": "$usuario","opcion":"usuario"}',
    "prmConexion": {"EMPRESA": idUn},
    "prmTokenDatos": {
      "USUARIO": usuario,
      "EMPRESA": idUn,
      "TOKEN": authResponse.token,
    },
  };

  try {
    final resultado = await api.postRequest('generales/consulta', datos);
    String dataString = resultado['data'];

    // Decodificamos ese String para convertirlo en una Lista
    List<dynamic> aplicaciones = json.decode(dataString);
    print(aplicaciones);

    // Verificamos si existe el ID de la aplicación de Asistencia: 'AST-001'
    bool existeAsistencia = aplicaciones.any(
      (app) => app['ID_APLICACION'] == 'AST-001',
    );

    // Si tiene acceso, guardar datos en almacenamiento local
    if (existeAsistencia) {
      print("Existe permiso");
      final prefs = await SharedPreferences.getInstance();

      // Guardar datos de autenticación y sesión
      await prefs.setString('auth_usuario', usuario);
      await prefs.setString('auth_token', authResponse.token);
      await prefs.setString('auth_empresa_id', idUn);
      if (contra != null) {
        await prefs.setString('auth_password', contra);
      }

      String authJson = jsonEncode(authResponse.toJson());
      await prefs.setString('auth_response', authJson);

      // Sincronizar con las variables existentes del sistema
      await prefs.setString(
        'user_role',
        'ADMIN',
      ); // Rol por defecto tras iniciar sesión
      await prefs.setString('user_name', usuario);
    }

    return existeAsistencia;
  } catch (e) {
    return false;
  }
}

/// Recuperar datos de autenticación desde almacenamiento local
Future<Map<String, String?>> getStoredAuthData() async {
  final prefs = await SharedPreferences.getInstance();

  return {
    'usuario': prefs.getString('auth_usuario'),
    'token': prefs.getString('auth_token'),
    'empresa_id': prefs.getString('auth_empresa_id'),
    'auth_response': prefs.getString('auth_response'),
    'auth_password': prefs.getString('auth_password'),
  };
}

/// Limpiar datos de autenticación del almacenamiento local
Future<void> clearStoredAuthData() async {
  final prefs = await SharedPreferences.getInstance();

  await prefs.remove('auth_usuario');
  await prefs.remove('auth_token');
  await prefs.remove('auth_empresa_id');
  await prefs.remove('auth_response');
  await prefs.remove('auth_password');
  await prefs.remove('user_role');
  await prefs.remove('user_name');

  print('Datos de autenticación eliminados del almacenamiento local');
}
