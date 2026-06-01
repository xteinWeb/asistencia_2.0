import 'dart:math';

/// Comparación local de vectores faciales (distancia euclidiana en Dart)
/// No requiere llamar a la API - funciona completamente offline.
class FaceMatcher {
  /// Calcula la distancia euclidiana entre dos vectores de 128 dimensiones.
  static double euclideanDistance(List<double> v1, List<double> v2) {
    assert(v1.length == v2.length, 'Vectors must have the same length');
    double sum = 0;
    for (int i = 0; i < v1.length; i++) {
      final diff = v1[i] - v2[i];
      sum += diff * diff;
    }
    return sqrt(sum);
  }

  /// Retorna true si los vectores corresponden al mismo rostro.
  /// [threshold] por defecto 0.6 (recomendado por face-api.js).
  static bool isMatch(
    List<double> stored,
    List<double> detected, {
    double threshold = 0.6,
  }) {
    if (stored.isEmpty || detected.isEmpty) return false;
    return euclideanDistance(stored, detected) <= threshold;
  }

  /// Busca el mejor match entre [detected] y una lista de vectores almacenados.
  /// Retorna el índice y la distancia del mejor match, o null si ninguno supera el umbral.
  static ({int index, double distance})? findBestMatch(
    List<double> detected,
    List<List<double>> storedVectors, {
    double threshold = 0.6,
  }) {
    if (detected.isEmpty || storedVectors.isEmpty) return null;

    int bestIndex = -1;
    double bestDistance = double.infinity;

    for (int i = 0; i < storedVectors.length; i++) {
      final vector = storedVectors[i];
      if (vector.isEmpty) continue;
      final distance = euclideanDistance(detected, vector);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }

    if (bestIndex >= 0 && bestDistance <= threshold) {
      return (index: bestIndex, distance: bestDistance);
    }
    return null;
  }

  /// Calcula el porcentaje de similitud (0-100%) a partir de la distancia.
  /// Distancia 0 = 100% similar, distancia >= threshold = 0%.
  static double similarityPercent(double distance, {double threshold = 0.6}) {
    if (distance <= 0) return 100.0;
    if (distance >= threshold) return 0.0;
    return ((1 - distance / threshold) * 100).clamp(0.0, 100.0);
  }
}
