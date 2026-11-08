import 'package:dart_frog/dart_frog.dart';
import '../../lib/config.dart';
import '../../lib/protocol.dart';
import '../../lib/stores.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method Not Allowed');
  }

  final ticketId = context.request.uri.queryParameters['ticket'];
  if (ticketId == null || ticketId.length < 10) {
    return Response(statusCode: 400, body: 'Ticket inválido o ausente');
  }

  final stores = context.read<InMemoryStores>();
  final ticket = stores.getTicket(ticketId);
  if (ticket == null || ticket.status != TicketStatus.pending || ticket.isUsed) {
    return Response(statusCode: 400, body: 'Ticket caducado o ya utilizado');
  }

  ticket.isUsed = true;
  final config = context.read<AppConfig>();

  try {
    final discovery = await OidcProtocol.discover(config.issuer);
    final pkce = OidcProtocol.generatePkce();
    final state = OidcProtocol.generateRandomString(32);
    final nonce = OidcProtocol.generateRandomString(32);
    final cookieId = OidcProtocol.generateRandomString(32);

    stores.createTransaction(
      cookieId,
      TransactionData(
        codeVerifier: pkce.codeVerifier,
        state: state,
        nonce: nonce,
        ticketId: ticketId,
        createdAt: DateTime.now(),
      ),
    );

    final authUrl = OidcProtocol.buildAuthorizationUrl(
      authorizationEndpoint: discovery.authorizationEndpoint,
      clientId: config.clientId,
      redirectUri: config.redirectUri,
      codeChallenge: pkce.codeChallenge,
      state: state,
      nonce: nonce,
    );

    return Response(
      statusCode: 302,
      headers: {
        'Location': authUrl,
        'Set-Cookie': '${config.cookieName}=$cookieId; HttpOnly; Path=/; SameSite=Lax',
      },
    );
  } catch (e) {
    return Response(statusCode: 502, body: 'Error al conectar con el servidor OIDC: $e');
  }
}
