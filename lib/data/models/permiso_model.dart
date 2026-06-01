import '../../domain/entities/permiso.dart';

class PermisoModel extends Permiso {
  const PermisoModel({
    super.id,
    required super.usuarioRegistrador,
    required super.cedulaEmpleado,
    required super.fechaHora,
    required super.tipo,
    required super.fechaInicio,
    required super.fechaFinal,
    super.sincronizado = false,
  });

  factory PermisoModel.fromMap(Map<String, dynamic> map) => PermisoModel(
        id: (map['id'] as String?)?.toLowerCase(),
        usuarioRegistrador: map['usuario_registrador'] as String,
        cedulaEmpleado: map['cedula_empleado'] as String,
        fechaHora: map['fecha_hora'] as String,
        tipo: map['tipo'] as String,
        fechaInicio: map['fecha_inicio'] as String,
        fechaFinal: map['fecha_final'] as String,
        sincronizado: (map['sincronizado'] as int? ?? 0) == 1,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'usuario_registrador': usuarioRegistrador,
        'cedula_empleado': cedulaEmpleado,
        'fecha_hora': fechaHora,
        'tipo': tipo,
        'fecha_inicio': fechaInicio,
        'fecha_final': fechaFinal,
        'sincronizado': sincronizado ? 1 : 0,
      };

  factory PermisoModel.fromJson(Map<String, dynamic> json) =>
      PermisoModel.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  PermisoModel copyWith({
    String? id,
    String? usuarioRegistrador,
    String? cedulaEmpleado,
    String? fechaHora,
    String? tipo,
    String? fechaInicio,
    String? fechaFinal,
    bool? sincronizado,
  }) =>
      PermisoModel(
        id: id ?? this.id,
        usuarioRegistrador: usuarioRegistrador ?? this.usuarioRegistrador,
        cedulaEmpleado: cedulaEmpleado ?? this.cedulaEmpleado,
        fechaHora: fechaHora ?? this.fechaHora,
        tipo: tipo ?? this.tipo,
        fechaInicio: fechaInicio ?? this.fechaInicio,
        fechaFinal: fechaFinal ?? this.fechaFinal,
        sincronizado: sincronizado ?? this.sincronizado,
      );
}
