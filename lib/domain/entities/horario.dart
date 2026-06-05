class HorarioItem {
  final int item;
  final String inicio; // HH:mm:ss
  final String finalTime; // HH:mm:ss
  final bool lunes;
  final bool martes;
  final bool miercoles;
  final bool jueves;
  final bool viernes;
  final bool sabado;
  final bool domingo;
  final String tipo; // PRODUCTIVA / RECESO / etc

  const HorarioItem({
    required this.item,
    required this.inicio,
    required this.finalTime,
    required this.lunes,
    required this.martes,
    required this.miercoles,
    required this.jueves,
    required this.viernes,
    required this.sabado,
    required this.domingo,
    required this.tipo,
  });

  factory HorarioItem.fromMap(Map<String, dynamic> map) {
    return HorarioItem(
      item: map['item'] as int,
      inicio: map['inicio'] as String,
      finalTime: map['final'] as String,
      lunes: (map['lunes'] as int) == 1,
      martes: (map['martes'] as int) == 1,
      miercoles: (map['miercoles'] as int) == 1,
      jueves: (map['jueves'] as int) == 1,
      viernes: (map['viernes'] as int) == 1,
      sabado: (map['sabado'] as int) == 1,
      domingo: (map['domingo'] as int) == 1,
      tipo: map['tipo'] as String,
    );
  }

  Map<String, dynamic> toMap(String idHorario) => {
    'id_horario': idHorario,
    'item': item,
    'inicio': inicio,
    'final': finalTime,
    'lunes': lunes ? 1 : 0,
    'martes': martes ? 1 : 0,
    'miercoles': miercoles ? 1 : 0,
    'jueves': jueves ? 1 : 0,
    'viernes': viernes ? 1 : 0,
    'sabado': sabado ? 1 : 0,
    'domingo': domingo ? 1 : 0,
    'tipo': tipo,
  };
}

class Horario {
  final String? idHorario;
  final String descripcion;
  final String estado;
  final List<HorarioItem> items;

  const Horario({
    this.idHorario,
    required this.descripcion,
    required this.estado,
    required this.items,
  });

  // Getters para compatibilidad hacia atrás:
  String get horaInicio {
    if (items.isEmpty) return '00:00';
    return _formatTime(items.first.inicio);
  }

  String get horaFinal {
    if (items.isEmpty) return '00:00';
    return _formatTime(items.last.finalTime);
  }

  String get tipo {
    if (items.isEmpty) return descripcion;
    final firstType = items.first.tipo.toUpperCase();
    if (firstType == 'PRODUCTIVA') return 'LABORAL';
    if (firstType == 'RECESO') return 'ALMUERZO';
    return firstType;
  }

  String get dias {
    final activeDays = <String>[];
    if (items.any((i) => i.lunes)) activeDays.add('L');
    if (items.any((i) => i.martes)) activeDays.add('M');
    if (items.any((i) => i.miercoles)) activeDays.add('Mi');
    if (items.any((i) => i.jueves)) activeDays.add('J');
    if (items.any((i) => i.viernes)) activeDays.add('V');
    if (items.any((i) => i.sabado)) activeDays.add('S');
    if (items.any((i) => i.domingo)) activeDays.add('D');
    return activeDays.isEmpty ? 'Ninguno' : activeDays.join(',');
  }

  List<String> get diasList => dias.split(',').map((d) => d.trim()).toList();

  String _formatTime(String raw) {
    if (raw.length >= 5) {
      return raw.substring(0, 5); // Extrae HH:mm
    }
    return raw;
  }

  @override
  String toString() => 'Horario($descripcion ($horaInicio-$horaFinal))';
}
