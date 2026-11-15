/// Derives the public WBA DID document URL from a `did:wba` DID.
///
/// WBA resolves `did:wba:<host>:<path...>` at `https://<host>/<path...>/did.json`.
/// Returns null for non-WBA DIDs or malformed input so callers can hide the
/// entry instead of opening a broken link.
String? wbaDidDocumentUrl(String did) {
  const schemePrefix = 'did:wba:';
  final normalized = did.trim();
  if (!normalized.startsWith(schemePrefix)) {
    return null;
  }
  final parts = normalized.substring(schemePrefix.length).split(':');
  if (parts.length < 2) {
    return null;
  }
  final host = parts.first.trim();
  if (host.isEmpty ||
      host.contains('/') ||
      host.contains('\\') ||
      host.contains('?') ||
      host.contains('#')) {
    return null;
  }
  final path = parts.skip(1).map((part) => part.trim()).toList(growable: false);
  if (path.any((part) => part.isEmpty)) {
    return null;
  }
  final encodedPath = <String>[
    ...path,
    'did.json',
  ].map(Uri.encodeComponent).join('/');
  return Uri(scheme: 'https', host: host, path: '/$encodedPath').toString();
}
