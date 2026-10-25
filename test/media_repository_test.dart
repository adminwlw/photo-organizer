import 'package:album_cleaner/media_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android 10 deletes directly and Android 11 uses system trash', () {
    expect(androidUsesSystemTrash(29), isFalse);
    expect(androidUsesSystemTrash(30), isTrue);
    expect(deleteRequestBatchSize(true), 1);
    expect(deleteRequestBatchSize(false), 500);
  });

  test('photo hashes use Hamming distance and form representative groups', () {
    expect(photoHashDistance('0000000000000000', '0000000000000003'), 2);
    expect(
      groupSimilarPhotoHashes({
        'a': '0000000000000000',
        'b': '0000000000000001',
        'c': 'ffffffffffffffff',
        'd': 'fffffffffffffffe',
        'single': 'aaaaaaaaaaaaaaaa',
      }, maxDistance: 1),
      [
        ['a', 'b'],
        ['c', 'd'],
      ],
    );
  });
}
