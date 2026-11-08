import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';


String _randomUrlSafe(int length, Random random) {
  final values = Uint8List(length);
  for (var i = 0; i < length; i++) {
    values[i] = random.nextInt(256);
  }
  return base64UrlEncode(values).replaceAll('=', '');
}

/// Genera la aserción JWT (private_key_jwt) requerida para el canje de tokens en eSignet.
String generateClientAssertion({
  required String clientId,
  required String issuer,
  required String privateJwkPath,
  required String alg,
  Random? random,
}) {
  final file = File(privateJwkPath);
  if (!file.existsSync()) {
    throw StateError('No se encontró el archivo JWK privado en: $privateJwkPath');
  }

  final jwkJson = file.readAsStringSync();
  final jwk = jsonDecode(jwkJson) as Map<String, dynamic>;

  final Object? kid = jwk['kid'];
  if (kid is! String || kid.isEmpty) {
    throw ArgumentError('El JWK no trae kid: eSignet lo exige en la cabecera de la aserción.');
  }

  final JWTKey key = JWTKey.fromJWK(jwk);
  final rng = random ?? Random.secure();

  final jwt = JWT(
    {
      'iss': clientId,
      'sub': clientId,
      'aud': issuer, // eSignet exige el emisor como audiencia, no el endpoint de tokens
      'jti': _randomUrlSafe(16, rng),
    },
    header: {'kid': kid}, // El kid va explícitamente en el constructor
  );

  return jwt.sign(
    key,
    algorithm: alg == 'RS256' ? JWTAlgorithm.RS256 : JWTAlgorithm.PS256,
    expiresIn: const Duration(seconds: 60), // Vida corta obligatoria
  );
}
