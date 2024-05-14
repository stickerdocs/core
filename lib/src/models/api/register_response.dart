import 'dart:convert';

class RegisterResponse {
  final String userId;
  final String? challengeResponse;

  const RegisterResponse({
    required this.userId,
    required this.challengeResponse,
  });

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'challenge_response': challengeResponse,
      };

  RegisterResponse.fromJson(Map<String, dynamic> map)
      : userId = map['user_id'],
        challengeResponse = map['challenge_response'];

  static RegisterResponse deserialize(String data) {
    Map<String, dynamic> decoded = jsonDecode(data);
    return RegisterResponse.fromJson(decoded);
  }
}
