import '../../domain/entities/registro.dart';

class RegistroModel extends Registro {
  const RegistroModel({
    super.id,
    required super.fechaHora,
    required super.cedula,
    required super.evento,
    super.duracion,
    required super.tipo,
    required super.unidadNegocio,
    super.sincronizado = false,
  });

  factory RegistroModel.fromMap(Map<String, dynamic> map) => RegistroModel(
        id: (map['id'] as String?)?.toLowerCase(),
        fechaHora: map['fecha_hora'] as String,
        cedula: map['cedula'] as String,
        evento: map['evento'] as String,
        duracion: map['duracion'] as String?,
        tipo: map['tipo'] as String,
        unidadNegocio: map['unidad_negocio'] as String,
        sincronizado: (map['sincronizado'] as int? ?? 0) == 1,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'fecha_hora': fechaHora,
        'cedula': cedula,
        'evento': evento,
        'duracion': duracion,
        'tipo': tipo,
        'unidad_negocio': unidadNegocio,
        'sincronizado': sincronizado ? 1 : 0,
      };

  factory RegistroModel.fromJson(Map<String, dynamic> json) =>
      RegistroModel.fromMap(json);

  Map<String, dynamic> toJson() => toMap();
}
