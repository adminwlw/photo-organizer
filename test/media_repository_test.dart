import 'package:album_cleaner/media_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android 10 deletes directly and Android 11 uses system trash', () {
    expect(androidUsesSystemTrash(29), isFalse);
    expect(androidUsesSystemTrash(30), isTrue);
  });
}
