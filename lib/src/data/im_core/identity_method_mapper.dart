import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../domain/entities/identity_method.dart';

IdentityMethodCapabilities identityMethodCapabilitiesFromCore(
  core.IdentityMethodCapabilities value,
) => IdentityMethodCapabilities(
  method: switch (value.method) {
    core.DidMethod.wba => IdentityDidMethod.wba,
    core.DidMethod.web => IdentityDidMethod.web,
  },
  handleRecovery: value.handleRecovery,
  rootImport: value.rootImport,
  rootTransfer: value.rootTransfer,
  servicesUpdate: value.servicesUpdate,
);

const _didRelationships = <String>[
  'authentication',
  'assertionMethod',
  'keyAgreement',
  'capabilityInvocation',
  'capabilityDelegation',
];

/// Projects the public verification methods of a Core identity document.
/// Only public material crosses this boundary; Core stays the identity source.
IdentityDocumentSummary identityDocumentSummaryFromCore(
  Map<String, Object?> document,
) {
  final did = (document['id'] as String?)?.trim() ?? '';
  final rawMethods = document['verificationMethod'];
  final methods = <IdentityVerificationMethod>[];
  if (rawMethods is List) {
    for (final raw in rawMethods) {
      if (raw is! Map) {
        continue;
      }
      final method = Map<String, Object?>.from(raw);
      final keyId = (method['id'] as String?)?.trim() ?? '';
      if (keyId.isEmpty) {
        continue;
      }
      final type = (method['type'] as String?)?.trim() ?? '';
      final publicKeyMultibase = (method['publicKeyMultibase'] as String?)
          ?.trim();
      methods.add(
        IdentityVerificationMethod(
          keyId: keyId,
          type: type,
          relationships: _relationshipsFor(document, keyId),
          publicKeyMultibase: publicKeyMultibase == null ||
                  publicKeyMultibase.isEmpty
              ? null
              : publicKeyMultibase,
        ),
      );
    }
  }
  return IdentityDocumentSummary(
    did: did,
    verificationMethods: List<IdentityVerificationMethod>.unmodifiable(
      methods,
    ),
  );
}

List<String> _relationshipsFor(Map<String, Object?> document, String keyId) {
  final relationships = <String>[];
  for (final name in _didRelationships) {
    final entries = document[name];
    if (entries is! List) {
      continue;
    }
    final referenced = entries.any((entry) {
      if (entry is String) {
        return entry == keyId;
      }
      if (entry is Map) {
        return entry['id'] == keyId;
      }
      return false;
    });
    if (referenced) {
      relationships.add(name);
    }
  }
  return List<String>.unmodifiable(relationships);
}
