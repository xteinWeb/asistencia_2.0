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
  /// - En Windows/iOS/Web: 'http://localhost:5900'
  /// - En Emulador Android: 'http://10.0.2.2:5900'
  /// - En dispositivo físico: Usar la IP de la máquina (ej: 'http://192.168.1.100:5900')
  static const String devBaseUrl = 'https://api.dev.colchonessunmoon.com';

  /// URL del servidor de producción.
  /// Reemplaza este valor con tu dominio HTTPS real una vez que subas la API a la nube.
  static const String prodBaseUrl = 'https://tu-api-produccion.com';

  /// Retorna la URL base correspondiente al entorno activo.
  static String get apiUrl {
    switch (active) {
      case AppEnvironment.dev:
        return devBaseUrl;
      case AppEnvironment.prod:
        return prodBaseUrl;
    }
  }
}
