enum UfbtLogLevel {
  debug(10),
  info(20),
  warning(30),
  error(40),
  critical(50);

  const UfbtLogLevel(this.severity);

  final int severity;

  String get levelName => name.toUpperCase();

  String get letter => levelName.substring(0, 1);
}
