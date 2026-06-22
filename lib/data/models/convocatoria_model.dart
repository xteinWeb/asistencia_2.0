class ConvocatoriaModel {
  final String id;
  final String fecha; // Formato yyyy-MM-dd
  final String horaInicio; // Formato HH:mm
  final String horaFinal; // Formato HH:mm
  final String descripcion;
  final bool sincronizado;

  ConvocatoriaModel({
    required this.id,
    required this.fecha,
    required this.horaInicio,
    required this.horaFinal,
    required this.descripcion,
    this.sincronizado = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fecha': fecha,
      'hora_inicio': horaInicio,
      'hora_final': horaFinal,
      'descripcion': descripcion,
      'sincronizado': sincronizado ? 1 : 0,
    };
  }

  factory ConvocatoriaModel.fromMap(Map<String, dynamic> map) {
    return ConvocatoriaModel(
      id: map['id'] as String,
      fecha: map['fecha'] as String,
      horaInicio: map['hora_inicio'] as String,
      horaFinal: map['hora_final'] as String,
      descripcion: map['descripcion'] as String,
      sincronizado: (map['sincronizado'] ?? 0) == 1,
    );
  }
}
