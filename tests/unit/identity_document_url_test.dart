import 'package:awiki_me/src/domain/services/did_document_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WBA DID resolves to its did.json URL', () {
    expect(
      wbaDidDocumentUrl('did:wba:awiki.me:user:yushanren:e1_abc'),
      'https://awiki.me/user/yushanren/e1_abc/did.json',
    );
  });

  test('surrounding whitespace is ignored', () {
    expect(
      wbaDidDocumentUrl('  did:wba:awiki.info:user:alice:e1_xyz  '),
      'https://awiki.info/user/alice/e1_xyz/did.json',
    );
  });

  test('path segments are URL encoded', () {
    expect(
      wbaDidDocumentUrl('did:wba:awiki.me:user:alice+dev:e1_abc'),
      'https://awiki.me/user/alice%2Bdev/e1_abc/did.json',
    );
  });

  test('non-WBA DIDs have no public document URL', () {
    expect(wbaDidDocumentUrl('did:web:example.com:user:alice'), isNull);
    expect(wbaDidDocumentUrl('did:example:alice'), isNull);
    expect(wbaDidDocumentUrl(''), isNull);
  });

  test('malformed WBA DIDs are rejected', () {
    expect(wbaDidDocumentUrl('did:wba:awiki.me'), isNull);
    expect(wbaDidDocumentUrl('did:wba::user:alice:e1'), isNull);
    expect(wbaDidDocumentUrl('did:wba:awiki.me:user::e1'), isNull);
    expect(wbaDidDocumentUrl('did:wba:awiki.me/user:alice:e1'), isNull);
  });
}
