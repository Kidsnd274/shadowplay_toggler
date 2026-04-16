sealed class NvapiState {
  const NvapiState();
}

class NvapiUninitialized extends NvapiState {
  const NvapiUninitialized();
}

class NvapiInitializing extends NvapiState {
  const NvapiInitializing();
}

class NvapiReady extends NvapiState {
  const NvapiReady();
}

class NvapiError extends NvapiState {
  final String message;
  const NvapiError(this.message);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NvapiError &&
          runtimeType == other.runtimeType &&
          message == other.message;

  @override
  int get hashCode => message.hashCode;
}
