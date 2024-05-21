import 'package:stickerdocs_core/src/models/api/auth_request.dart';

class LoginRequest {
  final String email;
  final AuthRequest authRequest;

  const LoginRequest({
    required this.email,
    required this.authRequest,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> map = {
      'email': email,
    };

    map.addAll(authRequest.toJson());

    return map;
  }
}
