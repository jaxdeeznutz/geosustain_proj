/// Accept old hash links and direct hosted links without losing record queries.
String portalLocation(String hash, String path, String search) {
  final fragment = hash.replaceFirst(RegExp('^#'), '');
  return fragment.startsWith('/') ? fragment : '$path$search';
}
