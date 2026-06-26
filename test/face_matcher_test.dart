import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:asistensia_empleados/core/utils/face_matcher.dart';
import 'package:asistensia_empleados/data/models/empleado_model.dart';

void main() {
  group('FaceMatcher Euclidean Distance Tests', () {
    test('Should calculate correct L2 distance for single 512-dimensional vectors', () {
      final v1 = List<double>.generate(512, (i) => i * 0.001);
      final v2 = List<double>.generate(512, (i) => i * 0.001);

      // Exact match should be 0.0
      expect(FaceMatcher.euclideanDistance(v1, v2), closeTo(0.0, 1e-9));

      // Slightly modified match
      final v3 = List<double>.from(v2);
      v3[0] += 0.5; // Difference of 0.5 at index 0
      expect(FaceMatcher.euclideanDistance(v1, v3), closeTo(0.5, 1e-9));
    });

    test('Should match live vector against the closest sub-vector when stored is multiple of 512', () {
      final live = List<double>.generate(512, (i) => 0.1);
      
      // Store 3 concatenated vectors (1536 elements total)
      // Vector A (0.0): distance to live is sqrt(512 * 0.01) = sqrt(5.12) ≈ 2.26
      final vectorA = List<double>.generate(512, (i) => 0.0);
      // Vector B (0.09): distance to live is sqrt(512 * 0.0001) = sqrt(0.0512) ≈ 0.226
      final vectorB = List<double>.generate(512, (i) => 0.09);
      // Vector C (0.5): distance to live is sqrt(512 * 0.16) = sqrt(81.92) ≈ 9.05
      final vectorC = List<double>.generate(512, (i) => 0.5);

      final stored = [...vectorA, ...vectorB, ...vectorC];

      // Minimum distance should be from Vector B, which is around 0.22627
      final expectedDist = FaceMatcher.euclideanDistance(live, vectorB);
      final actualDist = FaceMatcher.euclideanDistance(live, stored);

      expect(actualDist, closeTo(expectedDist, 1e-9));
      expect(FaceMatcher.isMatch(stored, live, threshold: 0.3), isTrue);
      expect(FaceMatcher.isMatch(stored, live, threshold: 0.2), isFalse);
    });
  });

  group('EmpleadoModel Multi-Vector Decoding Tests', () {
    test('Should parse single 512-dimension vector correctly', () {
      final singleVector = List<double>.generate(512, (i) => 0.1);
      final map = {
        'cedula': '123',
        'nombre': 'John Doe',
        'mapa_vector_foto': jsonEncode(singleVector),
      };

      final empleado = EmpleadoModel.fromMap(map);
      expect(empleado.mapaVectorFoto.length, 512);
      expect(empleado.mapaVectorFoto[0], 0.1);
    });

    test('Should parse concatenated flat multi-vector list correctly', () {
      final doubleVector = List<double>.generate(1024, (i) => 0.2);
      final map = {
        'cedula': '123',
        'nombre': 'John Doe',
        'mapa_vector_foto': jsonEncode(doubleVector),
      };

      final empleado = EmpleadoModel.fromMap(map);
      expect(empleado.mapaVectorFoto.length, 1024);
      expect(empleado.mapaVectorFoto[0], 0.2);
    });

    test('Should parse and flatten nested JSON array vectors correctly', () {
      final v1 = List<double>.generate(512, (i) => 0.3);
      final v2 = List<double>.generate(512, (i) => 0.4);
      final nestedList = [v1, v2];

      final map = {
        'cedula': '123',
        'nombre': 'John Doe',
        'mapa_vector_foto': jsonEncode(nestedList),
      };

      final empleado = EmpleadoModel.fromMap(map);
      expect(empleado.mapaVectorFoto.length, 1024);
      expect(empleado.mapaVectorFoto[0], 0.3);
      expect(empleado.mapaVectorFoto[512], 0.4);
    });
  });
}
