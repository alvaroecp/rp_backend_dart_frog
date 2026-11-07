import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class OidcDiscovery {
  final String authorizationEndpoint;
  final String tokenEndpoint;
  final String userinfoEndpoint;
  final String jwksUri;

  OidcDiscovery({
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.userinfoEndpoint,
    required this.jwksUri,
  });

  factory OidcDiscovery.fromJson(Map<String, dynamic> json) {
    return OidcDiscovery(
      authorizationEndpoint: json['authorization_endpoint'] as String,
      tokenEndpoint: json['token_endpoint'] as String,
      userinfoEndpoint: json['userinfo_endpoint'] as String,
      jwksUri: json['jwks_uri'] as String,
    );
  }
}

class PkcePair {
  final String codeVerifier;
  final String codeChallenge;

  PkcePair({required this.codeVerifier, required this.codeChallenge});
}

class OidcProtocol {
  /// Realiza el descubrimiento de endpoints OIDC a partir del emisor (issuer).
  static Future<OidcDiscovery> discover(String issuer, {http.Client? httpClient}) async {
    final client = httpClient ?? http.Client();
    final wellKnownUrl = '$issuer/.well-known/openid-configuration';
    
    try {
      final response = await client.get(Uri.parse(wellKnownUrl));
      if (response.statusCode != 200) {
        throw StateError('Fallo el discovery OIDC en $wellKnownUrl: código ${response.statusCode}');
      }
      final jsonMap = jsonDecode(response.body) as Map<String, dynamic>;
      return OidcDiscovery.fromJson(jsonMap);
    } finally {
      if (httpClient == null) {
        client.close();
      }
    }
  }

  /// Genera un par PKCE (verifier y challenge S256) seguro.
  static PkcePair generatePkce() {
    final random = Random.secure();
    final values = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      values[i] = random.nextInt(256);
    }
    
    // code_verifier en base64url sin relleno '='
    final codeVerifier = base64UrlEncode(values).replaceAll('=', '');
    
    // code_challenge usando SHA-256
    final bytes = utf8.encode(codeVerifier);
    final digest = sha256.convert(bytes);
    final codeChallenge = base64UrlEncode(digest.bytes).replaceAll('=', '');

    return PkcePair(codeVerifier: codeVerifier, codeChallenge: codeChallenge);
  }

  /// Genera un valor aleatorio seguro para el state y el nonce.
  static String generateRandomString([int length = 32]) {
    final random = Random.secure();
    final values = Uint8List(length);
    for (var i = 0; i < length; i++) {
      values[i] = random.nextInt(256);
    }
    return base64UrlEncode(values).replaceAll('=', '');
  }

  /// Construye la URL de redirección hacia el endpoint de autorización de eSignet.
  static String buildAuthorizationUrl({
    required String authorizationEndpoint,
    required String clientId,
    required String redirectUri,
    required String codeChallenge,
    required String state,
    required String nonce,
    String scope = 'openid profile email',
    String acrValues = '',
  }) {
    final uri = Uri.parse(authorizationEndpoint).replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'scope': scope,
        'state': state,
        'nonce': nonce,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        if (acrValues.isNotEmpty) 'acr_values': acrValues,
      },
    );
    return uri.toString();
  }
}
