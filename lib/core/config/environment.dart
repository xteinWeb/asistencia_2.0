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
  static const String devBaseUrl = 'http://192.168.11.46:6000';

  /// URL del servidor de producción.
  static const String prodBaseUrl = 'https://tu-api-produccion.com';

  /// Retorna la URL base correspondiente al entorno activo.
  static String get apiUrl {
    if (kIsWeb) {
      // Resolver dinámicamente la IP o dominio del servidor en el que está corriendo.
      final uri = Uri.base;
      
      // Si estamos depurando localmente en el navegador (localhost o 127.0.0.1),
      // apuntamos directamente al puerto 5900 del backend local de desarrollo.
      if (uri.host == 'localhost' || uri.host == '127.0.0.1') {
        return 'http://${uri.host}:6000';
      }
      
      // En producción, usamos el mismo host y puerto con el que se cargó la web (Reverse Proxy en Nginx).
      // Esto evita problemas de CORS y elimina la necesidad de abrir múltiples puertos en el firewall.
      final portStr = uri.hasPort ? ':${uri.port}' : '';
      return '${uri.scheme}://${uri.host}$portStr';
    }
    switch (active) {
      case AppEnvironment.dev:
        return devBaseUrl;
      case AppEnvironment.prod:
        return prodBaseUrl;
    }
  }
}
