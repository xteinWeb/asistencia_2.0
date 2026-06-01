class Permiso {
  final String? id;
  final String usuarioRegistrador;
  final String cedulaEmpleado;
  final String fechaHora;      // registro timestamp ISO8601
  final String tipo;           // CITA_MEDICA / PERSONAL / LABORAL / TRASLADO / FIN_CONTRATO
  final String fechaInicio;    // ISO8601 date
  final String fechaFinal;     // ISO8601 date
  final bool sincronizado;

  const Permiso({
    this.id,
    required this.usuarioRegistrador,
    required this.cedulaEmpleado,
    required this.fechaHora,
    required this.tipo,
    required this.fechaInicio,
    required this.fechaFinal,
    this.sincronizado = false,
  });

  /// Devuelve true si el permiso cubre la fecha y hora actuales
  bool isActivoEn(DateTime momento) {
    final inicio = DateTime.tryParse(fechaInicio);
    final fin = DateTime.tryParse(fechaFinal);
    if (inicio == null || fin == null) return false;
    final momentoDate = DateTime(momento.year, momento.month, momento.day);
    final inicioDate = DateTime(inicio.year, inicio.month, inicio.day);
    final finDate = DateTime(fin.year, fin.month, fin.day);
    return !momentoDate.isBefore(inicioDate) && !momentoDate.isAfter(finDate);
  }

  @override
  String toString() =>
      'Permiso(cedula: $cedulaEmpleado, tipo: $tipo, $fechaInicio-$fechaFinal)';
}
