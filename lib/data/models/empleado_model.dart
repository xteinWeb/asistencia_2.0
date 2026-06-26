import 'dart:convert';
import '../../domain/entities/empleado.dart';

class EmpleadoModel extends Empleado {
  final bool sincronizado;
  final List<String>? fotoUris; // New field storing photo file URIs as JSON string

  const EmpleadoModel({
    required super.cedula,
    required super.nombre,
    required super.mapaVectorFoto,
    super.horarioId,
    super.fechaIniContrato,
    super.fechaFinContrato,
    super.estado = 'ACTIVO',
    super.sedePrincipal,
    super.idSeccion,
    super.tipo,
    super.fechaRegistro,
    this.sincronizado = false,
    this.fotoUris,
  });

  factory EmpleadoModel.fromMap(Map<String, dynamic> map) {
    List<double> vector = [];
    if (map['mapa_vector_foto'] != null) {
      final raw = map['mapa_vector_foto'] as String;
      if (raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            if (decoded.isEmpty) {
              // Lista vacía
            } else if (decoded[0] is List) {
              // Es una lista de listas (múltiples vectores), la aplanamos
              for (final sublist in decoded) {
                if (sublist is List && sublist.length == 512) {
                  vector.addAll(sublist.map((e) => (e as num).toDouble()));
                }
              }
            } else if (decoded.length % 512 == 0) {
              // Es una lista plana (vector único de 512 o múltiples vectores de 512 concatenados)
              vector = decoded.map((e) => (e as num).toDouble()).toList();
            } else {
              print(
                '[EmpleadoModel] Omitiendo vector de ${decoded.length} dimensiones para cédula ${map['cedula']}.',
              );
            }
          }
        } catch (e) {
          print(
            '[EmpleadoModel] Error al parsear vector facial para cédula ${map['cedula']}: $e',
          );
        }
      }
    }
    // Decode photo URIs if present
    List<String>? fotoList;
    if (map['foto_uris'] != null) {
      try {
        final decoded = jsonDecode(map['foto_uris'] as String);
        if (decoded is List) {
          fotoList = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {
        fotoList = null;
      }
    }
    return EmpleadoModel(
      cedula: map['cedula'] as String,
      nombre: map['nombre'] as String,
      mapaVectorFoto: vector,
      horarioId: map['horario_id'] as String?,
      fechaIniContrato: map['fecha_ini_contrato'] as String?,
      fechaFinContrato: map['fecha_fin_contrato'] as String?,
      estado: map['estado'] as String? ?? 'ACTIVO',
      sedePrincipal: map['sede_principal'] as String?,
      idSeccion: map['id_seccion'] as String?,
      tipo: map['tipo'] as String?,
      fechaRegistro: map['fecha_registro'] as String?,
      sincronizado: map['sincronizado'] == 1 || map['sincronizado'] == true,
      fotoUris: fotoList,
    );
  }

  Map<String, dynamic> toMap() => {
    'cedula': cedula,
    'nombre': nombre,
    'mapa_vector_foto': mapaVectorFoto.isEmpty ? null : jsonEncode(mapaVectorFoto),
    'horario_id': horarioId,
    'fecha_ini_contrato': fechaIniContrato,
    'fecha_fin_contrato': fechaFinContrato,
    'estado': estado,
    'sede_principal': sedePrincipal,
    'id_seccion': idSeccion,
    'tipo': tipo,
    'fecha_registro': fechaRegistro,
    'sincronizado': sincronizado ? 1 : 0,
    if (fotoUris != null && fotoUris!.isNotEmpty) 'foto_uris': jsonEncode(fotoUris),
  };

  factory EmpleadoModel.fromJson(Map<String, dynamic> json) =>
      EmpleadoModel.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  EmpleadoModel copyWith({
    String? cedula,
    String? nombre,
    List<double>? mapaVectorFoto,
    String? horarioId,
    String? fechaIniContrato,
    String? fechaFinContrato,
    String? estado,
    String? sedePrincipal,
    String? idSeccion,
    String? tipo,
    String? fechaRegistro,
    bool? sincronizado,
    List<String>? fotoUris,
  }) => EmpleadoModel(
    cedula: cedula ?? this.cedula,
    nombre: nombre ?? this.nombre,
    mapaVectorFoto: mapaVectorFoto ?? this.mapaVectorFoto,
    horarioId: horarioId ?? this.horarioId,
    fechaIniContrato: fechaIniContrato ?? this.fechaIniContrato,
    fechaFinContrato: fechaFinContrato ?? this.fechaFinContrato,
    estado: estado ?? this.estado,
    sedePrincipal: sedePrincipal ?? this.sedePrincipal,
    idSeccion: idSeccion ?? this.idSeccion,
    tipo: tipo ?? this.tipo,
    fechaRegistro: fechaRegistro ?? this.fechaRegistro,
    sincronizado: sincronizado ?? this.sincronizado,
    fotoUris: fotoUris ?? this.fotoUris,
  );
}
