import 'package:dart_frog/dart_frog.dart';
import '../../lib/stores.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method Not Allowed');
  }

  final stores = context.read<InMemoryStores>();

  // Authorization: Bearer <app_token>
  final authorization = context.request.headers['authorization'];
  String? token;
  if (authorization != null && authorization.startsWith('Bearer ')) {
    token = authorization.substring(7).trim();
  }

  final session = (token == null || token.isEmpty) ? null : stores.getSession(token);
  if (session == null) {
    return Response.json(
      statusCode: 401,
      body: {'error': 'invalid_token'},
      headers: {'www-authenticate': 'Bearer error="invalid_token"'},
    );
  }

  return Response.json(
    body: {
      'profile': session.profile,
      'sub': session.sub,
      'acr': session.acr,
      'auth_time': session.authTime,
      'session_expires_at': session.expiresAt.millisecondsSinceEpoch ~/ 1000,
    },
  );
}
