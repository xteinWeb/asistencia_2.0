class Horario {
  final String? idHorario;
  final String horaInicio; // HH:mm
  final String horaFinal;  // HH:mm
  final String tipo;       // LABORAL / ALMUERZO / DESCANSO
  final String dias;       // e.g. "L,M,Mi,J,V"

  const Horario({
    this.idHorario,
    required this.horaInicio,
    required this.horaFinal,
    required this.tipo,
    required this.dias,
  });

  List<String> get diasList => dias.split(',').map((d) => d.trim()).toList();

  @override
  String toString() => 'Horario($tipo $horaInicio-$horaFinal $dias)';
}
