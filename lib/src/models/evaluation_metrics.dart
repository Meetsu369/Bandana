/// Multi-class classification evaluation metrics.
class ClassMetric {
  final String label;
  final int truePositives;
  final int falsePositives;
  final int falseNegatives;
  final int support;

  const ClassMetric({
    required this.label,
    required this.truePositives,
    required this.falsePositives,
    required this.falseNegatives,
    required this.support,
  });

  double get precision => (truePositives + falsePositives) > 0
      ? truePositives / (truePositives + falsePositives)
      : 0.0;

  double get recall => (truePositives + falseNegatives) > 0
      ? truePositives / (truePositives + falseNegatives)
      : 0.0;

  double get f1Score {
    final p = precision;
    final r = recall;
    return (p + r) > 0 ? (2 * p * r) / (p + r) : 0.0;
  }
}

/// Evaluation metrics calculated on held-out validation sessions.
class ModelEvaluationReport {
  final int totalSamples;
  final int correctCount;
  final double accuracy;
  final double macroF1;
  final double macroPrecision;
  final double macroRecall;
  final Map<String, ClassMetric> classMetrics;
  final Map<String, Map<String, int>> confusionMatrix; // [actual][predicted]
  final int trainSessionCount;
  final int validationSessionCount;

  const ModelEvaluationReport({
    required this.totalSamples,
    required this.correctCount,
    required this.accuracy,
    required this.macroF1,
    required this.macroPrecision,
    required this.macroRecall,
    required this.classMetrics,
    required this.confusionMatrix,
    required this.trainSessionCount,
    required this.validationSessionCount,
  });

  /// Compute evaluation report from actual and predicted label pairs.
  factory ModelEvaluationReport.compute({
    required List<String> actualLabels,
    required List<String> predictedLabels,
    required int trainSessionCount,
    required int validationSessionCount,
  }) {
    if (actualLabels.length != predictedLabels.length || actualLabels.isEmpty) {
      return ModelEvaluationReport(
        totalSamples: actualLabels.length,
        correctCount: 0,
        accuracy: 0.0,
        macroF1: 0.0,
        macroPrecision: 0.0,
        macroRecall: 0.0,
        classMetrics: {},
        confusionMatrix: {},
        trainSessionCount: trainSessionCount,
        validationSessionCount: validationSessionCount,
      );
    }

    final total = actualLabels.length;
    var correct = 0;
    final allClasses = <String>{...actualLabels, ...predictedLabels}.toList()..sort();

    // Initialize confusion matrix
    final matrix = <String, Map<String, int>>{};
    for (final actual in allClasses) {
      matrix[actual] = {for (final pred in allClasses) pred: 0};
    }

    for (int i = 0; i < total; i++) {
      final act = actualLabels[i];
      final pred = predictedLabels[i];
      if (act == pred) correct++;
      matrix[act]![pred] = (matrix[act]![pred] ?? 0) + 1;
    }

    final classMetrics = <String, ClassMetric>{};
    for (final c in allClasses) {
      int tp = matrix[c]![c] ?? 0;
      int fp = 0;
      int fn = 0;
      int support = 0;

      for (final other in allClasses) {
        if (other != c) {
          fp += matrix[other]![c] ?? 0;
          fn += matrix[c]![other] ?? 0;
        }
        support += matrix[c]![other] ?? 0;
      }

      classMetrics[c] = ClassMetric(
        label: c,
        truePositives: tp,
        falsePositives: fp,
        falseNegatives: fn,
        support: support,
      );
    }

    final validMetrics = classMetrics.values.where((m) => m.support > 0).toList();
    final double macroPrec = validMetrics.isNotEmpty
        ? validMetrics.map((m) => m.precision).reduce((a, b) => a + b) / validMetrics.length
        : 0.0;
    final double macroRec = validMetrics.isNotEmpty
        ? validMetrics.map((m) => m.recall).reduce((a, b) => a + b) / validMetrics.length
        : 0.0;
    final double macroF1Val = validMetrics.isNotEmpty
        ? validMetrics.map((m) => m.f1Score).reduce((a, b) => a + b) / validMetrics.length
        : 0.0;

    return ModelEvaluationReport(
      totalSamples: total,
      correctCount: correct,
      accuracy: total > 0 ? correct / total : 0.0,
      macroF1: macroF1Val,
      macroPrecision: macroPrec,
      macroRecall: macroRec,
      classMetrics: classMetrics,
      confusionMatrix: matrix,
      trainSessionCount: trainSessionCount,
      validationSessionCount: validationSessionCount,
    );
  }
}
