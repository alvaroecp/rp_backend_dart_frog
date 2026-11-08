import 'package:dart_frog/dart_frog.dart';
import '../lib/config.dart';
import '../lib/stores.dart';

final _config = AppConfig.load();
final _stores = InMemoryStores();

Handler middleware(Handler handler) {
  return handler
      .use(provider<AppConfig>((context) => _config))
      .use(provider<InMemoryStores>((context) => _stores));
}
