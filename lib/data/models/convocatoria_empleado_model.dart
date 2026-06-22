class ConvocatoriaEmpleadoModel {
  final String convocatoriaId;
  final String cedulaEmpleado;
  final bool asistio;
  final String? fechaHoraAsistencia; // Formato yyyy-MM-dd HH:mm:ss, nulo si no asistió
  final bool sincronizado;

  ConvocatoriaEmpleadoModel({
    required this.convocatoriaId,
    required this.cedulaEmpleado,
    this.asistio = false,
    this.fechaHoraAsistencia,
    this.sincronizado = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'convocatoria_id': convocatoriaId,
      'cedula_empleado': cedulaEmpleado,
      'asistio': asistio ? 1 : 0,
      'fecha_hora_asistencia': fechaHoraAsistencia,
      'sincronizado': sincronizado ? 1 : 0,
    };
  }

  factory ConvocatoriaEmpleadoModel.fromMap(Map<String, dynamic> map) {
    return ConvocatoriaEmpleadoModel(
      convocatoriaId: map['convocatoria_id'] as String,
      cedulaEmpleado: map['cedula_empleado'] as String,
      asistio: (map['asistio'] ?? 0) == 1,
      fechaHoraAsistencia: map['fecha_hora_asistencia'] as String?,
      sincronizado: (map['sincronizado'] ?? 0) == 1,
    );
  }
}
