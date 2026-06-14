enum RemoteButton { up, down, left, right, ok, back }

class QueuedButton {
  QueuedButton({required this.asset}) : id = DateTime.now().microsecondsSinceEpoch.toString();

  final String id;
  final String asset;
}
