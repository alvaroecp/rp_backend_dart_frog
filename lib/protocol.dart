import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'assertion.dart';

class OidcDiscovery {
  final String authorizationEndpoint;
  final String tokenEndpoint;
  final String userinfoEndpoint;

  OidcDiscovery({
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.userinfoEndpoint,
  });
}

class PkceResult {
  final String codeVerifier;
  final String codeChallenge;

  PkceResult({
    required this.codeVerifier,
    required this.codeChallenge,
  });
}

class OidcProtocol {
  /// Realiza el descubrimiento OIDC (.well-known/openid-configuration)
  static Future<OidcDiscovery> discover(String issuer) async {
    final uri = Uri.parse('$issuer/.well-known/openid-configuration');
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Error en OIDC Discovery (${response.statusCode}): ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return OidcDiscovery(
      authorizationEndpoint: data['authorization_endpoint'] as String? ?? '',
      tokenEndpoint: data['token_endpoint'] as String? ?? '',
      userinfoEndpoint: data['userinfo_endpoint'] as String? ?? '',
    );
  }

  /// Genera aleatoriamente una cadena segura para state y nonce
  static String generateRandomString([int length = 32]) {
    final random = Random.secure();
    final values = List<int>.generate(length, (i) => random.nextInt(256));
    return base64UrlEncode(values).replaceAll('=', '');
  }

  /// Genera PKCE (code_verifier y code_challenge S256)
  static PkceResult generatePkce() {
    final codeVerifier = generateRandomString(48);
    final bytes = utf8.encode(codeVerifier);
    final digest = sha256.convert(bytes);
    final codeChallenge = base64Url.encode(digest.bytes).replaceAll('=', '');
    return PkceResult(
      codeVerifier: codeVerifier,
      codeChallenge: codeChallenge,
    );
  }

  /// Construye la URL de redirección hacia el servidor de autorización
  static String buildAuthorizationUrl({
    required String authorizationEndpoint,
    required String clientId,
    required String redirectUri,
    required String codeChallenge,
    required String state,
    required String nonce,
    String scope = 'openid profile email',
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
      },
    );
    return uri.toString();
  }

  /// Intercambia el authorization code por tokens firmando con private_key_jwt.
  /// La aserción la construye generateClientAssertion (lib/assertion.dart): lleva el kid
  /// del JWK, el emisor como audiencia y una vida de 60 s.
  static Future<Map<String, dynamic>> exchangeCodeForTokens({
    required String tokenEndpoint,
    required String issuer,
    required String clientId,
    required String redirectUri,
    required String code,
    required String codeVerifier,
    required String privateJwkPath,
    required String alg,
  }) async {
    // 1. Crear el JWT de aserción del cliente (private_key_jwt)
    final assertionToken = generateClientAssertion(
      clientId: clientId,
      issuer: issuer,
      privateJwkPath: privateJwkPath,
      alg: alg,
    );

    // 2. Preparar los parámetros en formato x-www-form-urlencoded
    final body = {
      'grant_type': 'authorization_code',
      'client_id': clientId,
      'code': code,
      'redirect_uri': redirectUri,
      'code_verifier': codeVerifier,
      'client_assertion_type': 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer',
      'client_assertion': assertionToken,
    };

    // 3. Ejecutar la petición POST al token endpoint
    final response = await http.post(
      Uri.parse(tokenEndpoint),
      headers: {'Accept': 'application/json'},
      body: body,
    );

    if (response.statusCode != 200) {
      throw Exception('Error al canjear tokens (${response.statusCode}): ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Decodifica el contenido (payload) de un JWT firmado.
  /// OJO: por ahora NO verifica la firma. Verificarla contra el JWKS de eSignet queda para la fase de mejoras.
  static Map<String, dynamic> decodeJwtPayload(String jwt) {
    final parts = jwt.split('.');
    if (parts.length != 3) {
      throw Exception('No es un JWT firmado (se esperaban 3 partes).');
    }
    final padded = parts[1] + '=' * ((4 - parts[1].length % 4) % 4);
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(base64Url.decode(padded))) as Map);
  }

  /// Comprueba las reclamaciones básicas del id_token: emisor, audiencia, caducidad y nonce.
  static void checkIdTokenClaims(
    Map<String, dynamic> claims, {
    required String issuer,
    required String clientId,
    required String nonce,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    if (claims['iss'] != issuer) {
      throw Exception('El iss del id_token (${claims['iss']}) no es el emisor.');
    }
    final aud = claims['aud'];
    final audOk = aud is String ? aud == clientId : (aud is List && aud.contains(clientId));
    if (!audOk) {
      throw Exception('El aud del id_token no incluye este cliente.');
    }
    final exp = claims['exp'];
    if (exp is! num || exp < now - 60) {
      throw Exception('El id_token está caducado.');
    }
    if (claims['nonce'] != nonce) {
      throw Exception('El nonce del id_token no coincide con el enviado.');
    }
    if (claims['sub'] is! String) {
      throw Exception('El id_token no trae sub.');
    }
  }

  /// Pide el perfil del usuario al endpoint userinfo. En eSignet llega como un JWT firmado
  /// (o, según la configuración, como JSON). Por ahora NO se verifica la firma.
  static Future<Map<String, dynamic>> fetchUserInfo(String userinfoEndpoint, String accessToken) async {
    final response = await http.get(
      Uri.parse(userinfoEndpoint),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/jwt, application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Error en userinfo (${response.statusCode})');
    }

    final body = response.body.trim();
    if (body.startsWith('{')) {
      return Map<String, dynamic>.from(jsonDecode(body) as Map);
    }
    return decodeJwtPayload(body);
  }
}
