class Empleado {
  final String cedula;
  final String nombre;
  final List<double> mapaVectorFoto; // 128 floats
  final String? horarioId;
  final String? fechaIniContrato;
  final String? fechaFinContrato;
  final String estado; // ACTIVO / INACTIVO
  final String? sedePrincipal;
  final String? idSeccion;
  final String? tipo; // OPERATIVO / ADMINISTRATIVO
  final String? fechaRegistro;

  const Empleado({
    required this.cedula,
    required this.nombre,
    required this.mapaVectorFoto,
    this.horarioId,
    this.fechaIniContrato,
    this.fechaFinContrato,
    this.estado = 'ACTIVO',
    this.sedePrincipal,
    this.idSeccion,
    this.tipo,
    this.fechaRegistro,
  });

  @override
  String toString() => 'Empleado(cedula: $cedula, nombre: $nombre, estado: $estado, sedePrincipal: $sedePrincipal, idSeccion: $idSeccion, tipo: $tipo, fechaRegistro: $fechaRegistro)';
}

