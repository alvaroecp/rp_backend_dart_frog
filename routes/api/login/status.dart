import 'package:dart_frog/dart_frog.dart';
import '../../../lib/stores.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method Not Allowed');
  }

  final ticketId = context.request.uri.queryParameters['ticket'];
  // El contrato exige que el secreto viaje estrictamente en la cabecera X-Poll-Secret
  final pollSecret = context.request.headers['x-poll-secret'];

  if (ticketId == null || ticketId.isEmpty) {
    return Response.json(statusCode: 404, body: {'status': 'unknown'});
  }
  if (pollSecret == null || pollSecret.isEmpty) {
    return Response.json(statusCode: 403, body: {'error': 'forbidden'});
  }

  final stores = context.read<InMemoryStores>();
  final ticket = stores.getTicket(ticketId);

  if (ticket == null) {
    return Response.json(statusCode: 404, body: {'status': 'unknown'});
  }

  if (ticket.pollSecret != pollSecret) {
    return Response.json(statusCode: 403, body: {'error': 'forbidden'});
  }

  // Verificar caducidad (TTL por defecto: 300 segundos)
  final age = DateTime.now().difference(ticket.createdAt).inSeconds;
  if (age > 300) {
    stores.removeTicket(ticketId);
    return Response.json(statusCode: 410, body: {'status': 'expired'});
  }

  if (ticket.status == TicketStatus.pending) {
    return Response.json(
      body: {
        'status': 'pending',
        'expires_in': (300 - age).clamp(0, 300),
      },
    );
  }

  if (ticket.status == TicketStatus.complete) {
    final tokens = stores.getTokensForTicket(ticketId);

    // Regla de un solo uso (one-shot): se entrega y se remueve de inmediato
    stores.removeTicket(ticketId);

    return Response.json(
      body: {
        'status': 'complete',
        'app_token': tokens?['app_token'],
        'expires_in': tokens?['expires_in'] ?? 3600,
      },
    );
  }

  if (ticket.status == TicketStatus.error) {
    final reason = ticket.errorMessage ?? 'unknown_error';
    stores.removeTicket(ticketId); // One-shot

    return Response.json(
      body: {
        'status': 'error',
        'error': reason,
      },
    );
  }

  return Response(statusCode: 500, body: 'Estado desconocido');
}
