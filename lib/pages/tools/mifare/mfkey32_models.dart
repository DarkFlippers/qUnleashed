enum MfKey32ErrorType {
  notFoundFile,
  readWrite,
  flipperConnection,
}

sealed class MfKey32State {
  const MfKey32State();
}

class MfKey32WaitingForFlipper extends MfKey32State {
  const MfKey32WaitingForFlipper();
}

class MfKey32DownloadingRawFile extends MfKey32State {
  const MfKey32DownloadingRawFile(this.percent);

  final double percent;
}

class MfKey32Calculating extends MfKey32State {
  const MfKey32Calculating(this.percent);

  final double percent;
}

class MfKey32Uploading extends MfKey32State {
  const MfKey32Uploading();
}

class MfKey32Saved extends MfKey32State {
  const MfKey32Saved(this.keys);

  final List<String> keys;
}

class MfKey32Error extends MfKey32State {
  const MfKey32Error(this.errorType);

  final MfKey32ErrorType errorType;
}

class FoundedInformation {
  const FoundedInformation({
    this.keys = const [],
    this.uniqueKeys = const {},
    this.duplicated = const {},
  });

  final List<FoundedKey> keys;
  final Set<String> uniqueKeys;
  final Map<String, DuplicatedSource> duplicated;

  FoundedInformation copyWith({
    List<FoundedKey>? keys,
    Set<String>? uniqueKeys,
    Map<String, DuplicatedSource>? duplicated,
  }) {
    return FoundedInformation(
      keys: keys ?? this.keys,
      uniqueKeys: uniqueKeys ?? this.uniqueKeys,
      duplicated: duplicated ?? this.duplicated,
    );
  }
}

enum DuplicatedSource {
  flipper,
  user,
}

class FoundedKey {
  const FoundedKey({
    required this.sectorName,
    required this.keyName,
    required this.key,
  });

  final String sectorName;
  final String keyName;
  final String? key;
}

class MfKey32Nonce {
  const MfKey32Nonce({
    required this.sectorName,
    required this.keyName,
    required this.uid,
    required this.nt0,
    required this.nr0,
    required this.ar0,
    required this.nt1,
    required this.nr1,
    required this.ar1,
  });

  final String sectorName;
  final String keyName;
  final int uid;
  final int nt0;
  final int nr0;
  final int ar0;
  final int nt1;
  final int nr1;
  final int ar1;
}
