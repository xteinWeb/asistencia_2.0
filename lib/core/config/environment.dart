import 'package:flutter/foundation.dart';

enum AppEnvironment {
  dev,
  prod,
}

/// Clase para gestionar el entorno de la aplicación (Desarrollo y Producción).
class Environment {
  /// Define el entorno activo. 
  /// Cambia a [AppEnvironment.prod] para pasar a producción.
  static const AppEnvironment active = AppEnvironment.dev;

  /// URL del servidor de desarrollo (Local).
  static const String devBaseUrl = 'http://192.168.11.46:5900';

  /// URL del servidor de producción.
  static const String prodBaseUrl = 'https://tu-api-produccion.com';

  /// Retorna la URL base correspondiente al entorno activo.
  static String get apiUrl {
    if (kIsWeb) {
      // Resolver dinámicamente la IP o dominio del servidor en el que está corriendo
      // la aplicación web para evitar IPs estáticas harcodeadas.
      final uri = Uri.base;
      return '${uri.scheme}://${uri.host}:5900';
    }
    switch (active) {
      case AppEnvironment.dev:
        return devBaseUrl;
      case AppEnvironment.prod:
        return prodBaseUrl;
    }
  }
}
