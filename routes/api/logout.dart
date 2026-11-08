import 'package:dart_frog/dart_frog.dart';
import '../../lib/stores.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, body: 'Method Not Allowed');
  }

  final stores = context.read<InMemoryStores>();

  // Authorization: Bearer <app_token>. Siempre responde 204, aunque el token no sirva.
  final authorization = context.request.headers['authorization'];
  if (authorization != null && authorization.startsWith('Bearer ')) {
    final token = authorization.substring(7).trim();
    if (token.isNotEmpty) {
      stores.removeSession(token);
    }
  }

  return Response(statusCode: 204);
}
