import '../../domain/entities/horario.dart';

class HorarioModel extends Horario {
  const HorarioModel({
    super.idHorario,
    required super.horaInicio,
    required super.horaFinal,
    required super.tipo,
    required super.dias,
  });

  factory HorarioModel.fromMap(Map<String, dynamic> map) => HorarioModel(
        idHorario: map['id_horario'] as String?,
        horaInicio: map['hora_inicio'] as String,
        horaFinal: map['hora_final'] as String,
        tipo: map['tipo'] as String,
        dias: map['dias'] as String,
      );

  Map<String, dynamic> toMap() => {
        if (idHorario != null) 'id_horario': idHorario,
        'hora_inicio': horaInicio,
        'hora_final': horaFinal,
        'tipo': tipo,
        'dias': dias,
      };

  factory HorarioModel.fromJson(Map<String, dynamic> json) =>
      HorarioModel.fromMap(json);

  Map<String, dynamic> toJson() => toMap();
}
