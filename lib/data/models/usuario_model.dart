import '../../domain/entities/usuario.dart';

class UsuarioModel extends Usuario {
  const UsuarioModel({
    required super.usuario,
    required super.nombre,
    required super.contrasena,
    required super.rol,
    required super.estado,
    required super.unidadNegocio,
  });

  factory UsuarioModel.fromMap(Map<String, dynamic> map) => UsuarioModel(
        usuario: map['usuario'] as String,
        nombre: map['nombre'] as String,
        contrasena: map['contrasena'] as String,
        rol: map['rol'] as String,
        estado: map['estado'] as String,
        unidadNegocio: map['unidad_negocio'] as String,
      );

  Map<String, dynamic> toMap() => {
        'usuario': usuario,
        'nombre': nombre,
        'contrasena': contrasena,
        'rol': rol,
        'estado': estado,
        'unidad_negocio': unidadNegocio,
      };

  factory UsuarioModel.fromJson(Map<String, dynamic> json) =>
      UsuarioModel.fromMap(json);

  Map<String, dynamic> toJson() => toMap();
}
