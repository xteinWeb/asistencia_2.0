class ConfiguracionModel {
  final String clave;
  final String valor;

  const ConfiguracionModel({
    required this.clave,
    required this.valor,
  });

  factory ConfiguracionModel.fromMap(Map<String, dynamic> map) =>
      ConfiguracionModel(
        clave: map['clave'] as String,
        valor: map['valor'] as String,
      );

  Map<String, dynamic> toMap() => {
        'clave': clave,
        'valor': valor,
      };

  factory ConfiguracionModel.fromJson(Map<String, dynamic> json) =>
      ConfiguracionModel.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  ConfiguracionModel copyWith({String? clave, String? valor}) =>
      ConfiguracionModel(
        clave: clave ?? this.clave,
        valor: valor ?? this.valor,
      );

  @override
  String toString() => 'Configuracion($clave: $valor)';
}
