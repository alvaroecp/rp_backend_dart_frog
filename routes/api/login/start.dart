import 'package:dart_frog/dart_frog.dart';
import '../../../lib/config.dart';
import '../../../lib/stores.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, body: 'Method Not Allowed');
  }

  final config = context.read<AppConfig>();
  final stores = context.read<InMemoryStores>();

  final ticket = stores.createTicket();
  if (ticket == null) {
    return Response.json(
      statusCode: 429,
      body: {'error': 'too_many_pending_logins'},
    );
  }

  final baseUrl = config.publicBaseUrl.isNotEmpty 
      ? config.publicBaseUrl 
      : config.redirectUri.replaceAll('/callback', '');

  final loginUrl = '$baseUrl/app/login?ticket=${ticket.ticketId}';

  return Response.json(
    body: {
      'ticket': ticket.ticketId,
      'poll_secret': ticket.pollSecret,
      'login_url': loginUrl,
      'expires_in': 300,
      'interval': 2,
    },
  );
}
