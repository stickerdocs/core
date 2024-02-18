import 'dart:convert';

class ChallengeResponse {
  final String? challengeResponse;

  const ChallengeResponse({required this.challengeResponse});

  Map<String, dynamic> toJson() => {'challenge_response': challengeResponse};

  ChallengeResponse.fromJson(Map<String, dynamic> map)
      : challengeResponse = map['challenge_response'];

  static ChallengeResponse deserialize(String data) {
    if (data.isEmpty) {
      return const ChallengeResponse(challengeResponse: null);
    }
    
    Map<String, dynamic> decoded = jsonDecode(data);
    return ChallengeResponse.fromJson(decoded);
  }
}
