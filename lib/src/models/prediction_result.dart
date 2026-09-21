/// Result of an ML prediction on a sensor data window.
class PredictionResult {
  /// The predicted activity label (e.g., "Walking").
  final String label;

  /// Confidence score between 0.0 and 1.0, or null if confidence is unavailable.
  ///
  /// The current KNN implementation does not expose neighbor vote information,
  /// so confidence is not available. This field will be null until a proper
  /// confidence estimation is implemented.
  final double? confidence;

  /// Timestamp of prediction.
  final DateTime timestamp;

  PredictionResult({
    required this.label,
    this.confidence,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Confidence as an integer percentage (0–100), or null if unavailable.
  int? get confidencePercent => confidence != null ? (confidence! * 100).round() : null;

  @override
  String toString() {
    final conf = confidencePercent?.toString() ?? 'N/A';
    return 'PredictionResult(label: $label, confidence: $conf)';
  }
}
