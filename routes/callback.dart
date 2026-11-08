import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import '../lib/config.dart';
import '../lib/protocol.dart';
import '../lib/stores.dart';

Future<Response> onRequest(RequestContext context) async {
  final params = context.request.uri.queryParameters;
  final code = params['code'];
  final returnedState = params['state'];

  final stores = context.read<InMemoryStores>();
  final config = context.read<AppConfig>();

  // 1. Extraer la cookie de sesión enviada por el navegador
  final cookieHeader = context.request.headers[HttpHeaders.cookieHeader];
  final cookieId = _extractCookieValue(cookieHeader, config.cookieName);

  if (code == null || returnedState == null) {
    return Response(
      statusCode: 400,
      body: 'Parámetros faltantes: se requiere "code" y "state".',
    );
  }

  if (cookieId == null) {
    return Response(
      statusCode: 400,
      body: 'Sesión de navegador ausente o expirada (Cookie no encontrada).',
    );
  }

  // 2. Recuperar la transacción usando la cookie y validar el state
  final transaction = stores.consumeTransaction(cookieId);
  if (transaction == null || transaction.state != returnedState) {
    return Response(
      statusCode: 400,
      body: 'Transacción inválida o estado (state) no coincide.',
    );
  }

  try {
    // 3. Descubrimiento OIDC e intercambio de tokens
    final discovery = await OidcProtocol.discover(config.issuer);

    final tokens = await OidcProtocol.exchangeCodeForTokens(
      tokenEndpoint: discovery.tokenEndpoint,
      issuer: config.issuer,
      clientId: config.clientId,
      redirectUri: config.redirectUri,
      code: code,
      codeVerifier: transaction.codeVerifier,
      privateJwkPath: config.privateJwkPath,
      alg: config.assertionAlg,
    );

    final idToken = tokens['id_token'];
    final accessToken = tokens['access_token'];
    if (idToken is! String || accessToken is! String) {
      throw Exception('La respuesta del canje no trae id_token y access_token.');
    }

    // 4. Comprobar las reclamaciones del id_token (por ahora SIN verificar la firma)
    final claims = OidcProtocol.decodeJwtPayload(idToken);
    OidcProtocol.checkIdTokenClaims(
      claims,
      issuer: config.issuer,
      clientId: config.clientId,
      nonce: transaction.nonce,
    );

    // 5. Obtener el perfil del usuario y comprobar que es la misma persona
    final profile = await OidcProtocol.fetchUserInfo(discovery.userinfoEndpoint, accessToken);
    if (profile['sub'] != claims['sub']) {
      throw Exception('El sub del userinfo no coincide con el del id_token.');
    }

    // 6. Crear la sesión propia: la app recibe solo este app_token, nunca los tokens de eSignet
    final appToken = OidcProtocol.generateRandomString(32);
    stores.saveSession(
      AppSession(
        appToken: appToken,
        profile: profile,
        sub: claims['sub'] as String,
        acr: '${claims['acr'] ?? ''}',
        authTime: (claims['auth_time'] as num?)?.toInt() ?? 0,
        expiresAt: DateTime.now().add(stores.sessionTtl),
      ),
    );

    // 7. Marcar el ticket como completado para el polling de la app
    stores.completeTicket(transaction.ticketId, {
      'app_token': appToken,
      'expires_in': stores.sessionTtl.inSeconds,
    });

    // 5. Retornar la página HTML de éxito
    return Response(
      body: '''
        <!DOCTYPE html>
        <html lang="es">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Autenticación Exitosa</title>
            <style>
                body { font-family: system-ui, sans-serif; text-align: center; padding-top: 50px; background-color: #f9fafb; color: #1f2937; }
                .card { max-width: 400px; margin: auto; background: white; padding: 30px; border-radius: 12px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
                h2 { color: #10b981; }
            </style>
        </head>
        <body>
            <div class="card">
                <h2>¡Autenticación Exitosa!</h2>
                <p>Tus credenciales han sido verificadas correctamente.</p>
                <p><strong>Ya puedes cerrar esta ventana y volver a la aplicación.</strong></p>
            </div>
        </body>
        </html>
      ''',
      headers: {'content-type': 'text/html; charset=utf-8'},
    );
  } catch (e, st) {
    print('Error durante el intercambio de tokens: $e\n$st');
    // Si falla el intercambio, actualizamos el ticket con error para que la app lo detecte en el polling
    final ticket = stores.getTicket(transaction.ticketId);
    if (ticket != null) {
      ticket.status = TicketStatus.error;
      ticket.errorMessage = e.toString().length > 300 ? e.toString().substring(0, 300) : e.toString();
      ticket.completedAt = DateTime.now();
    }

    return Response(
      statusCode: 502,
      body: 'Error durante el intercambio de tokens: $e',
    );
  }
}

// Función auxiliar para extraer el valor de una cookie específica del encabezado HTTP
String? _extractCookieValue(String? cookieHeader, String name) {
  if (cookieHeader == null) return null;
  final cookies = cookieHeader.split(';');
  for (final cookie in cookies) {
    final parts = cookie.trim().split('=');
    if (parts.length == 2 && parts[0] == name) {
      return parts[1];
    }
  }
  return null;
}
