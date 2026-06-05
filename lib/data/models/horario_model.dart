import '../../domain/entities/horario.dart';

class HorarioModel extends Horario {
  const HorarioModel({
    super.idHorario,
    required super.descripcion,
    required super.estado,
    required super.items,
  });

  factory HorarioModel.fromMap(Map<String, dynamic> map, {List<HorarioItem> items = const []}) {
    return HorarioModel(
      idHorario: map['id_horario'] as String?,
      descripcion: (map['descripcion'] ?? '') as String,
      estado: (map['estado'] ?? 'ACTIVO') as String,
      items: items,
    );
  }

  Map<String, dynamic> toMap() => {
    if (idHorario != null) 'id_horario': idHorario,
    'descripcion': descripcion,
    'estado': estado,
  };

  factory HorarioModel.fromJson(Map<String, dynamic> json) {
    final itemsList = (json['items'] as List?)
        ?.map((itemJson) => HorarioItem.fromMap(Map<String, dynamic>.from(itemJson)))
        .toList() ?? [];
    return HorarioModel(
      idHorario: json['id_horario'] as String?,
      descripcion: (json['descripcion'] ?? '') as String,
      estado: (json['estado'] ?? 'ACTIVO') as String,
      items: itemsList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id_horario': idHorario,
      'descripcion': descripcion,
      'estado': estado,
      'items': items.map((i) => i.toMap(idHorario ?? '')).toList(),
    };
  }
}
