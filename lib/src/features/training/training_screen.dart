import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../models/evaluation_metrics.dart';
import '../../services/database_service.dart';
import '../../services/laptop_training_service.dart';
import '../../services/ml_service.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import 'training_controller.dart';

/// Full-featured model training and evaluation screen.
///
/// Supports selecting between KNN and Logistic Regression,
/// Wrist (30), Ankle (30), and Dual-band (60) data sources,
/// session-level validation splits, and honest confusion matrix / metric display.
class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  late final TrainingController _controller;
  final _ml = getIt<MlService>();

  @override
  void initState() {
    super.initState();
    _controller = TrainingController(
      db: getIt<DatabaseService>(),
      ml: _ml,
    );
    _controller.loadSessions();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: context.background,
          appBar: AppBar(
            title: const Text('Model Training'),
            backgroundColor: context.background,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.laptop),
                tooltip: 'Laptop Training Service',
                onPressed: _openLaptopServiceDialog,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh sessions',
                onPressed: _controller.loadSessions,
              ),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Active Models Overview
                  _buildActiveModelsCard(brightness),
                  const SizedBox(height: AppSpacing.lg),

                  // Algorithm & Source Selector
                  _buildConfigSection(brightness),
                  const SizedBox(height: AppSpacing.lg),

                  // Session Selection Checklist
                  _buildSessionSelectorSection(brightness),
                  const SizedBox(height: AppSpacing.lg),

                  // Validation Preview / Action
                  _buildValidationCard(brightness),
                  const SizedBox(height: AppSpacing.lg),

                  // Training Action CTA
                  _buildTrainAction(brightness),
                  const SizedBox(height: AppSpacing.lg),

                  // Evaluation Results Card
                  if (_controller.lastResult != null) ...[
                    _buildEvaluationResultCard(
                      result: _controller.lastResult!,
                      brightness: brightness,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActiveModelsCard(Brightness brightness) {
    final singleTrained = _ml.isTrained;
    final combinedTrained = _ml.isCombinedTrained;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: context.ink.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Active Models', style: AppTypography.h3For(brightness)),
              if (_ml.canRollback30 || _ml.canRollback60)
                TextButton.icon(
                  icon: const Icon(Icons.history, size: 16),
                  label: const Text('Rollback Model'),
                  onPressed: () => _confirmRollbackDialog(),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _buildModelStatusItem(
                  title: 'Single-Band (30)',
                  isTrained: singleTrained,
                  algorithm: _ml.algorithm30.shortName,
                  sampleCount: _ml.trainedSampleCount,
                  classCount: _ml.trainedClassCount,
                  brightness: brightness,
                  onDelete: singleTrained
                      ? () => _controller.deleteModel(combined: false)
                      : null,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _buildModelStatusItem(
                  title: 'Dual-Band (60)',
                  isTrained: combinedTrained,
                  algorithm: _ml.algorithm60.shortName,
                  sampleCount: _ml.trainedSampleCountCombined,
                  classCount: _ml.trainedClassCountCombined,
                  brightness: brightness,
                  onDelete: combinedTrained
                      ? () => _controller.deleteModel(combined: true)
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModelStatusItem({
    required String title,
    required bool isTrained,
    required String algorithm,
    required int sampleCount,
    required int classCount,
    required Brightness brightness,
    VoidCallback? onDelete,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.disabledSurface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: context.ink.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: AppTypography.captionFor(brightness).copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (onDelete != null)
                InkWell(
                  onTap: onDelete,
                  child: Icon(Icons.delete_outline, size: 16, color: context.danger),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (isTrained) ...[
            Text(
              '$algorithm • $classCount classes',
              style: AppTypography.captionFor(brightness).copyWith(
                color: context.success,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '$sampleCount windows trained',
              style: AppTypography.captionFor(brightness).copyWith(
                color: context.secondaryInfo,
              ),
            ),
          ] else ...[
            Text(
              'Not Trained',
              style: AppTypography.captionFor(brightness).copyWith(
                color: context.secondaryInfo,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConfigSection(Brightness brightness) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: context.ink.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Training Configuration', style: AppTypography.h3For(brightness)),
          const SizedBox(height: AppSpacing.md),

          // Algorithm choice
          Text('Algorithm', style: AppTypography.captionFor(brightness).copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.xs),
          SegmentedButton<MlAlgorithm>(
            segments: const [
              ButtonSegment(
                value: MlAlgorithm.knn,
                label: Text('K-NN'),
                icon: Icon(Icons.hub_outlined),
              ),
              ButtonSegment(
                value: MlAlgorithm.logisticRegression,
                label: Text('Logistic Regression'),
                icon: Icon(Icons.stacked_line_chart),
              ),
            ],
            selected: {_controller.selectedAlgorithm},
            onSelectionChanged: (val) {
              _controller.setAlgorithm(val.first);
            },
          ),
          const SizedBox(height: AppSpacing.md),

          // Source choice
          Text('Data Source', style: AppTypography.captionFor(brightness).copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.xs),
          SegmentedButton<TrainingDataSource>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment(
                value: TrainingDataSource.wrist,
                label: Text('Wrist (30)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              ButtonSegment(
                value: TrainingDataSource.ankle,
                label: Text('Ankle (30)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              ButtonSegment(
                value: TrainingDataSource.combined,
                label: Text('Dual (60)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
            selected: {_controller.selectedSource},
            onSelectionChanged: (val) {
              _controller.setSource(val.first);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSessionSelectorSection(Brightness brightness) {
    final sessions = _controller.availableSessions;
    final selectedCount = _controller.selectedSessionIds.length;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: context.ink.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Select Sessions ($selectedCount)',
                  style: AppTypography.h3For(brightness).copyWith(fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: _controller.selectAll,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                ),
                child: const Text('All'),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: _controller.clearSelection,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                ),
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(
                child: Text(
                  'No sessions found. Record some activities in the Record tab first.',
                  style: AppTypography.captionFor(brightness),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: sessions.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final s = sessions[index];
                  final isSelected = _controller.selectedSessionIds.contains(s.id);
                  return CheckboxListTile(
                    dense: true,
                    title: Text(
                      'Session #${s.id}: ${s.label}',
                      style: AppTypography.bodyFor(brightness).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${s.sampleCount} samples • ${_formatDate(s.startTime)}',
                      style: AppTypography.captionFor(brightness),
                    ),
                    value: isSelected,
                    activeColor: context.primaryAccent,
                    onChanged: (_) => _controller.toggleSession(s.id!),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildValidationCard(Brightness brightness) {
    final val = _controller.validationResult;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: val != null && !val.isValid
              ? context.danger
              : context.ink.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Dataset Readiness', style: AppTypography.h3For(brightness)),
              OutlinedButton(
                onPressed: _controller.hasSelection ? _controller.validateDataset : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(80, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
                child: const Text('Validate'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (val == null)
            Text(
              'Select sessions and tap Validate to check window readiness.',
              style: AppTypography.captionFor(brightness),
            )
          else if (!val.isValid) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 18, color: context.danger),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    val.message,
                    style: AppTypography.bodyFor(brightness).copyWith(
                      color: context.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Icon(Icons.check_circle_outline, size: 18, color: context.success),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  val.message,
                  style: AppTypography.bodyFor(brightness).copyWith(
                    color: context.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildBadge('${val.windowCount} windows', context.primaryAccent),
                _buildBadge('${val.labelCount} classes', context.secondaryStrong),
                for (final entry in val.labelDistribution.entries)
                  _buildBadge('${entry.key}: ${entry.value}', context.secondaryInfo),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildTrainAction(Brightness brightness) {
    if (_controller.isTraining) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: context.primaryAccent, width: 1.5),
        ),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _controller.currentProgress?.status ?? 'Training in progress…',
              style: AppTypography.captionFor(brightness).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return PrimaryButton(
      label: 'Train Model',
      leadingIcon: Icons.model_training,
      onPressed: _controller.canTrain ? _controller.train : null,
    );
  }

  Widget _buildEvaluationResultCard({
    required TrainingResult result,
    required Brightness brightness,
  }) {
    final report = result.evaluationReport;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: result.success ? context.success : context.danger,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.success ? Icons.verified : Icons.error,
                color: result.success ? context.success : context.danger,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                result.message,
                style: AppTypography.h3For(brightness).copyWith(
                  color: result.success ? context.success : context.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (report != null && report.totalSamples > 0) ...[
            Text(
              'Session-Level Evaluation (No Window Leakage)',
              style: AppTypography.captionFor(brightness).copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Trained on ${report.trainSessionCount} session(s) • Evaluated on ${report.validationSessionCount} held-out session(s) (${report.totalSamples} windows)',
              style: AppTypography.captionFor(brightness).copyWith(
                color: context.secondaryInfo,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // Metric Cards
            Row(
              children: [
                _buildMetricBox('Accuracy', '${(report.accuracy * 100).toStringAsFixed(1)}%', context.success, brightness),
                const SizedBox(width: AppSpacing.sm),
                _buildMetricBox('Macro F1', '${(report.macroF1 * 100).toStringAsFixed(1)}%', context.primaryAccent, brightness),
                const SizedBox(width: AppSpacing.sm),
                _buildMetricBox('Precision', '${(report.macroPrecision * 100).toStringAsFixed(1)}%', context.secondaryStrong, brightness),
                const SizedBox(width: AppSpacing.sm),
                _buildMetricBox('Recall', '${(report.macroRecall * 100).toStringAsFixed(1)}%', context.secondaryInfo, brightness),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // Confusion Matrix
            Text('Confusion Matrix', style: AppTypography.captionFor(brightness).copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.xs),
            _buildConfusionMatrixTable(report, brightness),
          ] else ...[
            Text(
              'Model fitted on all ${result.windowCount} windows across ${result.classCount} classes.',
              style: AppTypography.captionFor(brightness),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricBox(String label, String value, Color color, Brightness brightness) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: AppTypography.h3For(brightness).copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style: AppTypography.captionFor(brightness).copyWith(
                fontSize: 10,
                color: context.secondaryInfo,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfusionMatrixTable(ModelEvaluationReport report, Brightness brightness) {
    final classes = report.classMetrics.keys.toList()..sort();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 16,
        headingRowHeight: 32,
        dataRowMinHeight: 28,
        dataRowMaxHeight: 36,
        columns: [
          const DataColumn(label: Text('Actual \\ Pred')),
          for (final c in classes) DataColumn(label: Text(c)),
        ],
        rows: [
          for (final act in classes)
            DataRow(
              cells: [
                DataCell(Text(act, style: const TextStyle(fontWeight: FontWeight.bold))),
                for (final pred in classes)
                  DataCell(
                    Text(
                      '${report.confusionMatrix[act]?[pred] ?? 0}',
                      style: TextStyle(
                        fontWeight: act == pred ? FontWeight.bold : FontWeight.normal,
                        color: act == pred ? context.success : context.danger,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _confirmRollbackDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rollback Model?'),
          content: const Text(
            'This will restore the previous model version from backup. Active predictions will use the restored model.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Rollback'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      final s30 = await _controller.rollbackModel(combined: false);
      final s60 = await _controller.rollbackModel(combined: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (s30 || s60) ? 'Model successfully rolled back ✓' : 'No rollback backup available',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _openLaptopServiceDialog() async {
    final laptopService = getIt<LaptopTrainingService>();
    final hostController = TextEditingController(text: laptopService.configuredHost);
    bool? isConnected;
    bool isChecking = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.laptop_chromebook),
                  SizedBox(width: 8),
                  Text('Laptop Training Service'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Connect to the local Python training service running on your laptop.\n'
                      'Use "adb reverse tcp:8000 tcp:8000" for USB or enter LAN IP.',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: hostController,
                      decoration: const InputDecoration(
                        labelText: 'Host URL',
                        hintText: 'http://127.0.0.1:8000 or http://10.0.2.2:8000',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton.tonal(
                          onPressed: isChecking
                              ? null
                              : () async {
                                  setDialogState(() => isChecking = true);
                                  await laptopService.setConfiguredHost(hostController.text);
                                  final healthy = await laptopService.checkHealth();
                                  setDialogState(() {
                                    isConnected = healthy;
                                    isChecking = false;
                                  });
                                },
                          child: isChecking
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Test Connection'),
                        ),
                        const SizedBox(width: 12),
                        if (isConnected != null)
                          Row(
                            children: [
                              Icon(
                                isConnected! ? Icons.check_circle : Icons.error,
                                color: isConnected! ? Colors.green : Colors.orange,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isConnected! ? 'Connected' : 'Unreachable',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isConnected! ? Colors.green : Colors.orange,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text(
                      'Import Model Artifact (JSON)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'You can paste a model artifact JSON exported from the laptop service to activate it directly.',
                      style: TextStyle(fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.file_download_outlined, size: 16),
                      label: const Text('Paste & Import Artifact'),
                      onPressed: () async {
                        final jsonController = TextEditingController();
                        bool isCombined = false;
                        final importConfirmed = await showDialog<bool>(
                          context: context,
                          builder: (c) => StatefulBuilder(
                            builder: (c, setImportState) => AlertDialog(
                              title: const Text('Import Model JSON'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(
                                    controller: jsonController,
                                    maxLines: 4,
                                    decoration: const InputDecoration(
                                      hintText: '{"formatVersion": 2, "algorithm": "...", ...}',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  SwitchListTile(
                                    dense: true,
                                    title: const Text('Is Dual-Band (60 features)'),
                                    value: isCombined,
                                    onChanged: (v) => setImportState(() => isCombined = v),
                                  ),
                                ],
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Activate')),
                              ],
                            ),
                          ),
                        );

                        if (importConfirmed == true && jsonController.text.trim().isNotEmpty) {
                          final success = await _ml.importModelJson(jsonController.text.trim(), combined: isCombined);
                          if (mounted && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(success ? 'Model artifact imported and activated ✓' : 'Failed to parse/import model artifact'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            if (success) setState(() {});
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}