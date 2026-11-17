import 'package:dart_frog/dart_frog.dart';

/// CORS for the web frontend. Only ONE origin is allowed (never `*`).
/// The origin comes from AppConfig.allowedOrigin (ALLOWED_ORIGIN).
Middleware cors(String allowedOrigin) {
  final corsHeaders = <String, Object>{
    'Access-Control-Allow-Origin': allowedOrigin,
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type, X-Poll-Secret',
    'Access-Control-Max-Age': '600',
    'Vary': 'Origin',
  };

  return (handler) {
    return (context) async {
      // Preflight: answer here, before the routes (they return 405 for OPTIONS).
      if (context.request.method == HttpMethod.options) {
        return Response(statusCode: 204, headers: corsHeaders);
      }
      final response = await handler(context);
      return response.copyWith(headers: {...response.headers, ...corsHeaders});
    };
  };
}
