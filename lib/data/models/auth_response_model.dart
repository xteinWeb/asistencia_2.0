class AuthResponse {
  final String errMensaje;
  final String token;
  final String newToken;
  final int tiempoSesion;
  final String userName;
  final String? fotoPerfilUser; // Puede ser nulo
  final String email;

  AuthResponse({
    required this.errMensaje,
    required this.token,
    required this.newToken,
    required this.tiempoSesion,
    required this.userName,
    this.fotoPerfilUser,
    required this.email,
  });

  // Método para transformar el JSON en una instancia de la clase
  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      errMensaje: json['ErrMensaje'] ?? '',
      token: json['token'] ?? '',
      newToken: json['newToken'] ?? '',
      tiempoSesion: json['TIEMPO_SESION'] ?? 0,
      userName: json['user_name'] ?? '',
      fotoPerfilUser: json['foto_perfil_user'], // Al ser String?, acepta el null directamente
      email: json['EMAIL'] ?? '',
    );
  }

  // Método para convertir el objeto de vuelta a JSON (útil para guardar en local storage)
  Map<String, dynamic> toJson() {
    return {
      'ErrMensaje': errMensaje,
      'token': token,
      'newToken': newToken,
      'TIEMPO_SESION': tiempoSesion,
      'user_name': userName,
      'foto_perfil_user': fotoPerfilUser,
      'EMAIL': email,
    };
  }
}
