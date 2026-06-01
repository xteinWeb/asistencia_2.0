import 'dart:convert';
import '../../domain/entities/empleado.dart';

class EmpleadoModel extends Empleado {
  final bool sincronizado;

  const EmpleadoModel({
    required super.cedula,
    required super.nombre,
    required super.mapaVectorFoto,
    super.horarioId,
    super.fechaIniContrato,
    super.fechaFinContrato,
    super.estado = 'ACTIVO',
    this.sincronizado = false,
  });

  factory EmpleadoModel.fromMap(Map<String, dynamic> map) {
    List<double> vector = [];
    if (map['mapa_vector_foto'] != null) {
      final raw = map['mapa_vector_foto'] as String;
      if (raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        vector = list.map((e) => (e as num).toDouble()).toList();
      }
    }
    return EmpleadoModel(
      cedula: map['cedula'] as String,
      nombre: map['nombre'] as String,
      mapaVectorFoto: vector,
      horarioId: map['horario_id'] as String?,
      fechaIniContrato: map['fecha_ini_contrato'] as String?,
      fechaFinContrato: map['fecha_fin_contrato'] as String?,
      estado: map['estado'] as String? ?? 'ACTIVO',
      sincronizado: (map['sincronizado'] as int? ?? 0) == 1,
    );
  }

  Map<String, dynamic> toMap() => {
        'cedula': cedula,
        'nombre': nombre,
        'mapa_vector_foto': jsonEncode(mapaVectorFoto),
        'horario_id': horarioId,
        'fecha_ini_contrato': fechaIniContrato,
        'fecha_fin_contrato': fechaFinContrato,
        'estado': estado,
        'sincronizado': sincronizado ? 1 : 0,
      };

  factory EmpleadoModel.fromJson(Map<String, dynamic> json) =>
      EmpleadoModel.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  EmpleadoModel copyWith({
    String? cedula,
    String? nombre,
    List<double>? mapaVectorFoto,
    String? horarioId,
    String? fechaIniContrato,
    String? fechaFinContrato,
    String? estado,
    bool? sincronizado,
  }) =>
      EmpleadoModel(
        cedula: cedula ?? this.cedula,
        nombre: nombre ?? this.nombre,
        mapaVectorFoto: mapaVectorFoto ?? this.mapaVectorFoto,
        horarioId: horarioId ?? this.horarioId,
        fechaIniContrato: fechaIniContrato ?? this.fechaIniContrato,
        fechaFinContrato: fechaFinContrato ?? this.fechaFinContrato,
        estado: estado ?? this.estado,
        sincronizado: sincronizado ?? this.sincronizado,
      );
}
