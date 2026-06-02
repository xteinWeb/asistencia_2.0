import 'package:flutter/foundation.dart';

enum AppEnvironment { dev, prod }

/// Clase para gestionar el entorno de la aplicación (Desarrollo y Producción).
class Environment {
  /// Define el entorno activo.
  /// Cambia a [AppEnvironment.prod] para pasar a producción.
  static const AppEnvironment active = AppEnvironment.dev;

  /// URL del servidor de desarrollo (Local).
  static const String devBaseUrl = 'http://192.168.11.46:8085';

  /// URL del servidor de producción.
  static const String prodBaseUrl = 'https://tu-api-produccion.com';

  /// Retorna la URL base correspondiente al entorno activo.
  static String get apiUrl {
    if (kIsWeb) {
      // Resolver dinámicamente la IP o dominio del servidor en el que está corriendo.
      final uri = Uri.base;

      // Si estamos depurando localmente en el navegador (localhost o 127.0.0.1),
      // apuntamos directamente al puerto 8085 del backend local de desarrollo.
      if (uri.host == 'localhost' || uri.host == '127.0.0.1') {
        return 'http://${uri.host}:8085';
      }

      // En producción con IP pública directa (Mapeo de puertos en el Fortinet),
      // apuntamos al host de procedencia en el puerto 8085 expuesto públicamente.
      return '${uri.scheme}://${uri.host}:8085';
    }
    switch (active) {
      case AppEnvironment.dev:
        return devBaseUrl;
      case AppEnvironment.prod:
        return prodBaseUrl;
    }
  }
}
