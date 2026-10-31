import 'package:flutter_test/flutter_test.dart';
import 'package:transkey_mobile/core/update/app_update_provider.dart';

void main() {
  test('compareVersions orders dotted versions numerically', () {
    expect(compareVersions('2.7.1', '2.7.0'), 1);
    expect(compareVersions('2.7.10', '2.7.9'), 1);
    expect(compareVersions('2.7', '2.7.0'), 0);
    expect(compareVersions('2.8.0', '2.10.0'), -1);
    expect(compareVersions('27.1', '15.5'), 1);
    expect(compareVersions('3.0.0-beta', '2.9.9'), 1);
  });
}
