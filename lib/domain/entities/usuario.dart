class Usuario {
  final String usuario;
  final String nombre;
  final String contrasena; // hashed
  final String rol;        // ADMIN / OPERADOR / SOLO_LECTURA
  final String estado;     // ACTIVO / INACTIVO
  final String unidadNegocio;

  const Usuario({
    required this.usuario,
    required this.nombre,
    required this.contrasena,
    required this.rol,
    required this.estado,
    required this.unidadNegocio,
  });

  bool get isAdmin => rol == 'ADMIN';
  bool get isActive => estado == 'ACTIVO';

  @override
  String toString() => 'Usuario($usuario, rol: $rol)';
}
