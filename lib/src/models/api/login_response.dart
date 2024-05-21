import 'dart:convert';

class LoginResponse {
  final String userId;
  final String? challengeResponse;

  const LoginResponse({required this.userId, required this.challengeResponse});

  Map<String, dynamic> toJson() =>
      {'user_id': userId, 'challenge_response': challengeResponse};

  LoginResponse.fromJson(Map<String, dynamic> map)
      : userId = map['user_id'],
        challengeResponse = map['challenge_response'];

  static LoginResponse deserialize(String data) {
    Map<String, dynamic> decoded = jsonDecode(data);

    return LoginResponse.fromJson(decoded);
  }
}
