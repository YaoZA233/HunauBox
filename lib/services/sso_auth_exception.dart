class SsoAuthException implements Exception {
  const SsoAuthException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => message;
}
