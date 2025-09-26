class ControlledOperationException implements Exception {
  const ControlledOperationException(this.message);

  final String message;

  @override
  String toString() => message;
}
