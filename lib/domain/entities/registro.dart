class Registro {
  final String? id;
  final String fechaHora;       // ISO8601
  final String cedula;
  final String evento;          // ENTRADA / SALIDA
  final String? duracion;
  final String tipo;            // LABORAL / PERMISO / ALMUERZO / RETARDO / EXTRAS
  final String unidadNegocio;
  final bool sincronizado;

  const Registro({
    this.id,
    required this.fechaHora,
    required this.cedula,
    required this.evento,
    this.duracion,
    required this.tipo,
    required this.unidadNegocio,
    this.sincronizado = false,
  });

  @override
  String toString() =>
      'Registro(cedula: $cedula, evento: $evento, tipo: $tipo, $fechaHora)';
}
