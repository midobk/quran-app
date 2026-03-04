class RollingStatsBuffer {
  RollingStatsBuffer({required this.capacity}) : assert(capacity > 0);

  final int capacity;
  final List<double> _values = <double>[];

  int get length => _values.length;
  bool get isEmpty => _values.isEmpty;
  List<double> get values => List<double>.unmodifiable(_values);

  void add(double value) {
    if (_values.length == capacity) {
      _values.removeAt(0);
    }
    _values.add(value);
  }

  void clear() {
    _values.clear();
  }

  double get average {
    if (_values.isEmpty) {
      return 0;
    }
    double sum = 0;
    for (final double value in _values) {
      sum += value;
    }
    return sum / _values.length;
  }
}
