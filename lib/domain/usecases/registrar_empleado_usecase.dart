import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../data/datasources/local/database_helper.dart';
import '../../data/models/empleado_model.dart';
import '../../services/face_recognition_service.dart';
import '../../services/connectivity_service.dart';

/// Registra un nuevo empleado.
/// REQUIERE INTERNET — genera el vector facial en el backend y lo guarda en SQLite.
class RegistrarEmpleadoUseCase {
  final DatabaseHelper _db;
  final FaceRecognitionService _faceService;
  final ConnectivityService _connectivity;

  RegistrarEmpleadoUseCase({
    DatabaseHelper? db,
    FaceRecognitionService? faceService,
    ConnectivityService? connectivity,
  })  : _db = db ?? DatabaseHelper(),
        _faceService = faceService ?? FaceRecognitionService(),
        _connectivity = connectivity ?? ConnectivityService();

  Future<EmpleadoModel> execute({
    required String cedula,
    required String nombre,
    required String imagePath,
    String? horarioId,
    String? fechaIniContrato,
    String? fechaFinContrato,
    String? sedePrincipal,
    String? idSeccion,
    String? tipo,
  }) async {
    // Verificar conexión
    final connected = await _connectivity.isConnected();
    if (!connected) {
      throw Exception(
          'El registro de empleados requiere conexión a internet.');
    }

    // Verificar que el archivo existe
    if (!kIsWeb && !File(imagePath).existsSync()) {
      throw Exception('Archivo de imagen no encontrado.');
    }

    // Generar vector en el backend Node.js
    final vector = await _faceService.generarVectorDesdeImagen(imagePath, cedula: cedula);
    if (vector.isEmpty) {
      throw Exception('No se pudo generar el vector facial.');
    }

    // Crear modelo
    final empleado = EmpleadoModel(
      cedula: cedula,
      nombre: nombre,
      mapaVectorFoto: vector,
      horarioId: horarioId,
      fechaIniContrato: fechaIniContrato,
      fechaFinContrato: fechaFinContrato,
      sedePrincipal: sedePrincipal,
      idSeccion: idSeccion,
      tipo: tipo,
    );

    // Guardar en SQLite local
    await _db.insertEmpleado(empleado);

    return empleado;
  }
}
