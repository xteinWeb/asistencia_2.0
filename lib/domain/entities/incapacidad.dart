class Incapacidad {
  final String? id;
  final String usuarioRegistrador;
  final String cedulaEmpleado;
  final String fechaHora;      // registro timestamp ISO8601
  final String tipo;           // EG / AL / EL / LM etc.
  final String fechaInicio;    // ISO8601 date-time
  final String fechaFinal;     // ISO8601 date-time
  final String? observacion;
  final bool sincronizado;

  const Incapacidad({
    this.id,
    required this.usuarioRegistrador,
    required this.cedulaEmpleado,
    required this.fechaHora,
    required this.tipo,
    required this.fechaInicio,
    required this.fechaFinal,
    this.observacion,
    this.sincronizado = false,
  });

  /// Devuelve true si la incapacidad cubre la fecha y hora actuales
  bool isActivoEn(DateTime momento) {
    final inicio = DateTime.tryParse(fechaInicio);
    final fin = DateTime.tryParse(fechaFinal);
    if (inicio == null || fin == null) return false;
    return !momento.isBefore(inicio) && !momento.isAfter(fin);
  }

  @override
  String toString() =>
      'Incapacidad(cedula: $cedulaEmpleado, tipo: $tipo, $fechaInicio-$fechaFinal, obs: $observacion)';
}
