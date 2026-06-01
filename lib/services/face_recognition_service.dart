import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../data/datasources/local/database_helper.dart';
import '../core/constants/api_constants.dart';
import '../core/constants/db_constants.dart';

/// Servicio de reconocimiento facial.
/// - [registrarEmpleadoEnApi]: llama a POST /api/asistencia/nuevoEmpleado (REQUIERE internet)
/// - El vector generado se almacena en SQLite para uso offline posterior.
class FaceRecognitionService {
  final DatabaseHelper _db;

  FaceRecognitionService({DatabaseHelper? db})
      : _db = db ?? DatabaseHelper();

  /// Envía una imagen al backend Node.js y obtiene el vector facial de 128 dimensiones.
  /// Requiere conexión a internet.
  /// [imagePath] es la ruta local del archivo de imagen.
  /// Retorna el vector o lanza excepción si falla.
  Future<List<double>> generarVectorDesdeImagen(String imagePath) async {
    final baseUrl = await _db.getConfig(DbConstants.cfgUrlApi) ??
        ApiConstants.defaultBaseUrl;

    final uri = Uri.parse('$baseUrl${ApiConstants.nuevoEmpleado}');
    final file = File(imagePath);

    if (!file.existsSync()) {
      throw Exception('Archivo de imagen no encontrado: $imagePath');
    }

    final request = http.MultipartRequest('POST', uri);
    request.files.add(
      await http.MultipartFile.fromPath(
        'face',
        imagePath,
        contentType: MediaType('image', 'jpeg'),
      ),
    );

    final streamedResponse = await request
        .send()
        .timeout(const Duration(milliseconds: ApiConstants.receiveTimeoutMs));

    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception(
          'Error al generar vector: ${response.statusCode} - ${response.body}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    
    List? vectorRaw;
    if (body.containsKey('data') && body['data'] is Map) {
      final data = body['data'] as Map<String, dynamic>;
      vectorRaw = data['vector'] as List?;
    }
    vectorRaw ??= body['vector'] as List?;

    if (vectorRaw == null) {
      throw Exception('Respuesta inválida: no contiene campo "vector"');
    }

    return vectorRaw.map((e) => (e as num).toDouble()).toList();
  }

  /// Compara un vector detectado contra todos los vectores almacenados en SQLite.
  /// Retorna el índice del mejor match junto con la distancia, o null si ninguno supera el umbral.
  Future<({int index, double distance, String cedula})?> buscarMejorMatch(
    List<double> vectorDetectado, {
    double threshold = 0.6,
  }) async {
    final all = await _db.getAllEmpleados();
    final empleados = all.where((e) => e.estado == 'ACTIVO').toList();
    if (empleados.isEmpty) return null;

    int bestIndex = -1;
    double bestDistance = double.infinity;

    for (int i = 0; i < empleados.length; i++) {
      final vector = empleados[i].mapaVectorFoto;
      if (vector.isEmpty) continue;

      double sum = 0;
      for (int j = 0; j < vector.length; j++) {
        final diff = vectorDetectado[j] - vector[j];
        sum += diff * diff;
      }
      final distance = sum == 0 ? 0.0 : sum; // sqrt applied outside for perf
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }

    if (bestIndex < 0) return null;
    final sqrtDistance = sqrt(bestDistance);
    if (sqrtDistance > threshold) return null;

    return (
      index: bestIndex,
      distance: sqrtDistance,
      cedula: empleados[bestIndex].cedula,
    );
  }
}
