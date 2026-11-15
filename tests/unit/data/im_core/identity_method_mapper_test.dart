import 'package:awiki_me/src/data/im_core/identity_method_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('projects public verification methods from a Core DID document', () {
    const did = 'did:wba:awiki.me:user:alice:e1_demo';
    final summary = identityDocumentSummaryFromCore(<String, Object?>{
      'id': did,
      'verificationMethod': <Object?>[
        <String, Object?>{
          'id': '$did#key-1',
          'type': 'Multikey',
          'controller': did,
          'publicKeyMultibase': 'z6MkRoot',
        },
        <String, Object?>{
          'id': '$did#key-2',
          'type': 'X25519KeyAgreementKey2019',
          'controller': did,
          'publicKeyMultibase': 'z6LSE2ee',
        },
        <String, Object?>{
          'id': '$did#key-3',
          'type': 'JsonWebKey2020',
          'controller': did,
          'publicKeyJwk': <String, Object?>{'kty': 'OKP'},
        },
        <String, Object?>{'type': 'Multikey'},
        'not-a-method',
      ],
      'authentication': <Object?>['$did#key-1'],
      'assertionMethod': <Object?>[
        '$did#key-1',
        '$did#key-2',
      ],
      'keyAgreement': <Object?>[
        <String, Object?>{'id': '$did#key-3'},
      ],
    });

    expect(summary.did, did);
    expect(summary.verificationMethods, hasLength(3));

    final root = summary.verificationMethods[0];
    expect(root.keyId, '$did#key-1');
    expect(root.keyFragment, 'key-1');
    expect(root.type, 'Multikey');
    expect(root.relationships, <String>['authentication', 'assertionMethod']);
    expect(root.publicKeyMultibase, 'z6MkRoot');

    final e2ee = summary.verificationMethods[1];
    expect(e2ee.publicKeyMultibase, 'z6LSE2ee');

    final jwkOnly = summary.verificationMethods[2];
    expect(jwkOnly.publicKeyMultibase, isNull);
    expect(jwkOnly.relationships, <String>['keyAgreement']);
  });

  test('missing or malformed documents project to empty methods', () {
    expect(identityDocumentSummaryFromCore(const <String, Object?>{}).did, '');
    expect(
      identityDocumentSummaryFromCore(const <String, Object?>{
        'id': 'did:wba:awiki.me:user:alice:e1_demo',
        'verificationMethod': 'not-a-list',
      }).verificationMethods,
      isEmpty,
    );
  });
}
