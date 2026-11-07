import 'dart:io';

class AppConfig {
  final String clientId;
  final String redirectUri;
  final String privateJwkPath;
  final String issuer;
  final bool allowInsecureIssuer;
  final String assertionAlg;
  final int port;

  AppConfig({
    required this.clientId,
    required this.redirectUri,
    required this.privateJwkPath,
    required this.issuer,
    required this.allowInsecureIssuer,
    required this.assertionAlg,
    required this.port,
  });

  factory AppConfig.load() {
    // Buscar la ruta del rp.env (por defecto en ~/rp-app/rp.env)
    String envPath = Platform.environment['RP_ENV'] ?? '';
    if (envPath.isEmpty) {
      final home = Platform.environment['HOME'] ?? '/home/ernesto';
      envPath = '$home/rp-app/rp.env';
    }

    final envFile = File(envPath);
    final Map<String, String> envVars = {};

    if (envFile.existsSync()) {
      final lines = envFile.readAsLinesSync();
      for (var line in lines) {
        line = line.trim();
        // Ignorar comentarios y líneas vacías
        if (line.isEmpty || line.startsWith('#')) continue;
        
        final parts = line.split('=');
        if (parts.length >= 2) {
          final key = parts[0].trim();
          final value = parts.sublist(1).join('=').trim();
          envVars[key] = value;
        }
      }
    }

    // Las variables de entorno del sistema mandan sobre el archivo
    String getVar(String key, [String defaultValue = '']) {
      return Platform.environment[key] ?? envVars[key] ?? defaultValue;
    }

    final clientId = getVar('CLIENT_ID');
    if (clientId.isEmpty) {
      throw StateError('Falta la variable CLIENT_ID en el entorno o en rp.env');
    }

    final redirectUri = getVar('REDIRECT_URI');
    if (redirectUri.isEmpty) {
      throw StateError('Falta la variable REDIRECT_URI en el entorno o en rp.env');
    }

    // Extraer el puerto automáticamente del REDIRECT_URI (ej. http://localhost:3005/callback -> 3005)
    final uriObj = Uri.parse(redirectUri);
    final port = uriObj.hasPort ? uriObj.port : 80;

    final issuer = getVar('ISSUER', 'http://localhost:8080');
    final allowInsecure = getVar('ALLOW_INSECURE_ISSUER', 'false').toLowerCase() == 'true';

    if (issuer.startsWith('http://') && !allowInsecure) {
      throw StateError('El emisor usa HTTP pero ALLOW_INSECURE_ISSUER no está activado.');
    }

    final jwkPath = getVar('PRIVATE_JWK_PATH');
    final resolvedJwkPath = jwkPath.isNotEmpty 
        ? jwkPath 
        : '${Platform.environment['HOME']}/rp-app/client-private.jwk';

    return AppConfig(
      clientId: clientId,
      redirectUri: redirectUri,
      privateJwkPath: resolvedJwkPath,
      issuer: issuer,
      allowInsecureIssuer: allowInsecure,
      assertionAlg: getVar('ASSERTION_ALG', 'PS256'),
      port: port,
    );
  }
}
