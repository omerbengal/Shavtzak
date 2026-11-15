import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/services/backend_api_service.dart';

void main() {
  test('default function is api', () {
    expect(BackendApiService.functionName, 'api');
    final uri = BackendApiService.buildFunctionUri('proj', '/db/mutate');
    expect(uri.host, 'us-central1-proj.cloudfunctions.net');
    expect(uri.path, '/api');
    expect(uri.queryParameters['route'], '/db/mutate');
  });

  test('a preview build can name another function', () {
    final uri = BackendApiService.buildFunctionUri('proj', '/x', function: 'apiPreview');
    expect(uri.path, '/apiPreview');
  });
}
