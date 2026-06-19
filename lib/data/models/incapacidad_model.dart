import '../../domain/entities/incapacidad.dart';

class IncapacidadModel extends Incapacidad {
  const IncapacidadModel({
    super.id,
    required super.usuarioRegistrador,
    required super.cedulaEmpleado,
    required super.fechaHora,
    required super.tipo,
    required super.fechaInicio,
    required super.fechaFinal,
    super.observacion,
    super.sincronizado = false,
  });

  factory IncapacidadModel.fromMap(Map<String, dynamic> map) => IncapacidadModel(
        id: (map['id'] as String?)?.toLowerCase(),
        usuarioRegistrador: map['usuario_registrador'] as String,
        cedulaEmpleado: map['cedula_empleado'] as String,
        fechaHora: map['fecha_hora'] as String,
        tipo: map['tipo'] as String,
        fechaInicio: map['fecha_inicio'] as String,
        fechaFinal: map['fecha_final'] as String,
        observacion: map['observacion'] as String?,
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
        'observacion': observacion,
        'sincronizado': sincronizado ? 1 : 0,
      };

  factory IncapacidadModel.fromJson(Map<String, dynamic> json) =>
      IncapacidadModel.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  IncapacidadModel copyWith({
    String? id,
    String? usuarioRegistrador,
    String? cedulaEmpleado,
    String? fechaHora,
    String? tipo,
    String? fechaInicio,
    String? fechaFinal,
    String? observacion,
    bool? sincronizado,
  }) =>
      IncapacidadModel(
        id: id ?? this.id,
        usuarioRegistrador: usuarioRegistrador ?? this.usuarioRegistrador,
        cedulaEmpleado: cedulaEmpleado ?? this.cedulaEmpleado,
        fechaHora: fechaHora ?? this.fechaHora,
        tipo: tipo ?? this.tipo,
        fechaInicio: fechaInicio ?? this.fechaInicio,
        fechaFinal: fechaFinal ?? this.fechaFinal,
        observacion: observacion ?? this.observacion,
        sincronizado: sincronizado ?? this.sincronizado,
      );
}
