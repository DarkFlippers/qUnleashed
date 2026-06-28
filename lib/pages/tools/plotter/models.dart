class PlotData {
  PlotData({required this.centerFreqHz, required this.pulses});

  final int centerFreqHz;
  final List<double> pulses;
}

class IrSignal {
  IrSignal({this.name, this.type, this.frequency, this.data});

  String? name;
  String? type;
  int? frequency;
  List<double>? data;
}

class PlotterParseResult {
  PlotterParseResult({this.data, this.signals = const []});

  final PlotData? data;
  final List<IrSignal> signals;
}

class PlotterParseException implements Exception {
  PlotterParseException(this.message);

  final String message;

  @override
  String toString() => message;
}
