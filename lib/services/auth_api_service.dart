import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;

class AuthApiService {
  final String baseUrl = "https://api.dev.colchonessunmoon.com/api";
  // final String baseUrl = "https://api.prod.colchonessunmoon.com/api";

  Future<dynamic> postRequest(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    final url = Uri.parse('$baseUrl/$endpoint');

    try {
      print('🔗 Intentando conectar a: $url');
      print('📤 Datos enviados: $data');

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json; charset=UTF-8',
              'Accept': 'application/json',
              'User-Agent': 'Flutter-App/1.0',
            },
            body: jsonEncode(data),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw TimeoutException(
                'Timeout de conexión después de 30 segundos',
                const Duration(seconds: 30),
              );
            },
          );

      print('📊 Status Code: ${response.statusCode}');
      print('📥 Response Body: ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        print('❌ Error HTTP: ${response.statusCode} - ${response.body}');
        throw Exception(
          'Error en POST: ${response.statusCode} - ${response.reasonPhrase}',
        );
      }
    } on SocketException catch (e) {
      print('❌ SocketException: $e');
      throw Exception(
        'Error de conexión de red: Sin acceso a internet o servidor no disponible',
      );
    } on TimeoutException catch (e) {
      print('❌ TimeoutException: $e');
      throw Exception(
        'Timeout de conexión: El servidor tardó demasiado en responder',
      );
    } on FormatException catch (e) {
      print('❌ FormatException: $e');
      throw Exception('Error de formato en la respuesta del servidor');
    } catch (e) {
      print('❌ Error general: $e');
      throw Exception('Error de conexión: $e');
    }
  }
}
