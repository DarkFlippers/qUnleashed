enum RemoteButton { up, down, left, right, ok, back }

extension RemoteButtonHint on RemoteButton {
  /// The button's artwork, shared by the press animation, the keyboard hint
  /// legend and the Wrist Remote mapping dialog. The files are named after the
  /// enum, so this lives next to it rather than being spelled out again
  /// wherever it is needed.
  String get hintAsset => 'assets/ic/control/hint/$name.svg';
}

class QueuedButton {
  QueuedButton({required this.asset})
    : id = DateTime.now().microsecondsSinceEpoch.toString();

  final String id;
  final String asset;
}
