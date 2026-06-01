class Empleado {
  final String cedula;
  final String nombre;
  final List<double> mapaVectorFoto; // 128 floats
  final String? horarioId;
  final String? fechaIniContrato;
  final String? fechaFinContrato;
  final String estado; // ACTIVO / INACTIVO

  const Empleado({
    required this.cedula,
    required this.nombre,
    required this.mapaVectorFoto,
    this.horarioId,
    this.fechaIniContrato,
    this.fechaFinContrato,
    this.estado = 'ACTIVO',
  });

  @override
  String toString() => 'Empleado(cedula: $cedula, nombre: $nombre, estado: $estado)';
}

