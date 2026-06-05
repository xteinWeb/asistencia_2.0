class AusentismoModel {
  final String id;
  final String cedulaEmpleado;
  final String fecha; // YYYY-MM-DD
  final String siglaAusencia;
  final String? observacion;
  final bool sincronizado;

  const AusentismoModel({
    required this.id,
    required this.cedulaEmpleado,
    required this.fecha,
    required this.siglaAusencia,
    this.observacion,
    this.sincronizado = false,
  });

  factory AusentismoModel.fromMap(Map<String, dynamic> map) {
    return AusentismoModel(
      id: map['id'] as String,
      cedulaEmpleado: map['cedula_empleado'] as String,
      fecha: map['fecha'] as String,
      siglaAusencia: map['sigla_ausencia'] as String,
      observacion: map['observacion'] as String?,
      sincronizado: map['sincronizado'] == 1 || map['sincronizado'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'cedula_empleado': cedulaEmpleado,
        'fecha': fecha,
        'sigla_ausencia': siglaAusencia,
        'observacion': observacion,
        'sincronizado': sincronizado ? 1 : 0,
      };

  AusentismoModel copyWith({
    String? id,
    String? cedulaEmpleado,
    String? fecha,
    String? siglaAusencia,
    String? observacion,
    bool? sincronizado,
  }) =>
      AusentismoModel(
        id: id ?? this.id,
        cedulaEmpleado: cedulaEmpleado ?? this.cedulaEmpleado,
        fecha: fecha ?? this.fecha,
        siglaAusencia: siglaAusencia ?? this.siglaAusencia,
        observacion: observacion ?? this.observacion,
        sincronizado: sincronizado ?? this.sincronizado,
      );
}
