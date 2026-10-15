import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_shadows.dart';
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
            title: Text(
              'Model Training',
              style: AppTypography.h2For(brightness).copyWith(fontWeight: FontWeight.w800),
            ),
            backgroundColor: context.background,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.laptop_chromebook),
                tooltip: 'Laptop Service',
                onPressed: _openLaptopServiceDialog,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh sessions',
                onPressed: _controller.loadSessions,
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: _buildTrainBottomBar(brightness),
            ),
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

                  // Evaluation Results Card
                  if (_controller.lastResult != null) ...[
                    _buildEvaluationResultCard(
                      result: _controller.lastResult!,
                      brightness: brightness,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],

                  // Bottom padding to avoid overlap with bottomNavigationBar
                  const SizedBox(height: 80),
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
        borderRadius: AppRadius.card,
        border: Border.all(
          color: AppColors.borderColor(brightness),
          width: 2.0,
        ),
        boxShadow: AppShadows.hard(brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Active Models',
                style: AppTypography.h3For(brightness).copyWith(fontWeight: FontWeight.w800),
              ),
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
          color: AppColors.borderColor(brightness).withValues(alpha: 0.3),
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
        borderRadius: AppRadius.card,
        border: Border.all(
          color: AppColors.borderColor(brightness),
          width: 2.0,
        ),
        boxShadow: AppShadows.hard(brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Training Configuration',
            style: AppTypography.h3For(brightness).copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.md),

          // Algorithm choice (Segmented group with 2px borders and #D6F865 active fill)
          Text(
            'Algorithm',
            style: AppTypography.captionFor(brightness).copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          _buildBentoAlgorithmSelector(brightness),
          const SizedBox(height: AppSpacing.md),

          // Source choice (Segmented group with 2px borders and #FF3384 active fill)
          Text(
            'Data Source',
            style: AppTypography.captionFor(brightness).copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          _buildBentoDataSourceSelector(brightness),
        ],
      ),
    );
  }

  Widget _buildBentoAlgorithmSelector(Brightness brightness) {
    return Row(
      children: [
        Expanded(
          child: _buildBentoSegmentItem(
            label: 'K-NN',
            icon: Icons.hub_outlined,
            isSelected: _controller.selectedAlgorithm == MlAlgorithm.knn,
            activeColor: AppColors.accentLime,
            activeTextColor: const Color(0xFF18181B),
            brightness: brightness,
            onTap: () => _controller.setAlgorithm(MlAlgorithm.knn),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _buildBentoSegmentItem(
            label: 'Logistic Regression',
            icon: Icons.stacked_line_chart,
            isSelected: _controller.selectedAlgorithm == MlAlgorithm.logisticRegression,
            activeColor: AppColors.accentLime,
            activeTextColor: const Color(0xFF18181B),
            brightness: brightness,
            onTap: () => _controller.setAlgorithm(MlAlgorithm.logisticRegression),
          ),
        ),
      ],
    );
  }

  Widget _buildBentoDataSourceSelector(Brightness brightness) {
    return Row(
      children: [
        Expanded(
          child: _buildBentoSegmentItem(
            label: 'Wrist (30)',
            icon: Icons.watch_outlined,
            isSelected: _controller.selectedSource == TrainingDataSource.wrist,
            activeColor: AppColors.accentPink,
            activeTextColor: Colors.white,
            brightness: brightness,
            onTap: () => _controller.setSource(TrainingDataSource.wrist),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildBentoSegmentItem(
            label: 'Ankle (30)',
            icon: Icons.directions_walk,
            isSelected: _controller.selectedSource == TrainingDataSource.ankle,
            activeColor: AppColors.accentPink,
            activeTextColor: Colors.white,
            brightness: brightness,
            onTap: () => _controller.setSource(TrainingDataSource.ankle),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildBentoSegmentItem(
            label: 'Dual (60)',
            icon: Icons.sync_alt,
            isSelected: _controller.selectedSource == TrainingDataSource.combined,
            activeColor: AppColors.accentPink,
            activeTextColor: Colors.white,
            brightness: brightness,
            onTap: () => _controller.setSource(TrainingDataSource.combined),
          ),
        ),
      ],
    );
  }

  Widget _buildBentoSegmentItem({
    required String label,
    required IconData icon,
    required bool isSelected,
    required Color activeColor,
    required Color activeTextColor,
    required Brightness brightness,
    required VoidCallback onTap,
  }) {
    final borderColor = AppColors.borderColor(brightness);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? activeColor : context.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: borderColor,
              width: 2.0,
            ),
            boxShadow: isSelected ? AppShadows.hardSm(brightness) : AppShadows.none,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? activeTextColor : AppColors.textSecondary(brightness),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: label.length > 14 ? 10.0 : 11.0,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? activeTextColor : AppColors.textPrimary(brightness),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSessionSelectorSection(Brightness brightness) {
    // De-duplicate session selection list strictly by id
    final rawSessions = _controller.availableSessions;
    final seen = <int>{};
    final sessions = rawSessions.where((s) => s.id != null && seen.add(s.id!)).toList();
    final selectedCount = _controller.selectedSessionIds.length;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: AppRadius.card,
        border: Border.all(
          color: AppColors.borderColor(brightness),
          width: 2.0,
        ),
        boxShadow: AppShadows.hard(brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        'Select Sessions',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary(brightness),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accentSkyBlue.withValues(alpha: brightness == Brightness.light ? 1.0 : 0.25),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.borderColor(brightness),
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        '$selectedCount',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: brightness == Brightness.light ? const Color(0xFF0369A1) : const Color(0xFF93C5FD),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildBentoSmallButton(
                label: 'All',
                brightness: brightness,
                onTap: _controller.selectAll,
              ),
              const SizedBox(width: 6),
              _buildBentoSmallButton(
                label: 'Clear',
                brightness: brightness,
                onTap: _controller.clearSelection,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
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
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: sessions.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final s = sessions[index];
                  final isSelected = _controller.selectedSessionIds.contains(s.id);
                  return InkWell(
                    onTap: () => _controller.toggleSession(s.id!),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primaryAccent(brightness).withValues(alpha: 0.08)
                            : context.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primaryAccent(brightness)
                              : AppColors.borderColor(brightness).withValues(alpha: 0.3),
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Session #${s.id}: ${s.label}',
                                  style: AppTypography.bodyMediumFor(brightness).copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${s.sampleCount} samples • ${_formatDate(s.startTime)}',
                                  style: AppTypography.captionFor(brightness).copyWith(
                                    color: AppColors.textSecondary(brightness),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.brandPink : Colors.transparent,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: isSelected ? AppColors.brandPink : AppColors.borderColor(brightness),
                                width: 2,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(Icons.check, size: 16, color: Colors.white)
                                : null,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBentoSmallButton({
    required String label,
    required Brightness brightness,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.borderColor(brightness),
              width: 1.5,
            ),
            boxShadow: AppShadows.hardSm(brightness),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary(brightness),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildValidationCard(Brightness brightness) {
    final val = _controller.validationResult;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: AppRadius.card,
        border: Border.all(
          color: val != null && !val.isValid
              ? AppColors.accentDanger
              : AppColors.borderColor(brightness),
          width: 2.0,
        ),
        boxShadow: AppShadows.hard(brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Dataset Readiness',
                style: AppTypography.h3For(brightness).copyWith(fontWeight: FontWeight.w800),
              ),
              OutlinedButton(
                onPressed: _controller.hasSelection ? _controller.validateDataset : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(80, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  side: BorderSide(
                    color: _controller.hasSelection
                        ? AppColors.borderColor(brightness)
                        : AppColors.borderColor(brightness).withValues(alpha: 0.3),
                    width: 1.5,
                  ),
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
              style: AppTypography.captionFor(brightness).copyWith(
                color: AppColors.textSecondary(brightness),
              ),
            )
          else if (!val.isValid) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, size: 18, color: AppColors.accentDanger),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    val.message,
                    style: AppTypography.bodyMediumFor(brightness).copyWith(
                      color: AppColors.accentDanger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF16A34A)),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  val.message,
                  style: AppTypography.bodyMediumFor(brightness).copyWith(
                    color: const Color(0xFF16A34A),
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
                _buildBadge('${val.windowCount} windows', AppColors.primaryAccent(brightness)),
                _buildBadge('${val.labelCount} classes', AppColors.secondaryStrong(brightness)),
                for (final entry in val.labelDistribution.entries)
                  _buildBadge('${entry.key}: ${entry.value}', AppColors.secondaryInfo(brightness)),
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
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildTrainBottomBar(Brightness brightness) {
    if (_controller.isTraining) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: AppRadius.button,
          border: Border.all(color: AppColors.borderColor(brightness), width: 2.0),
          boxShadow: AppShadows.hard(brightness),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.brandPink),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                _controller.currentProgress?.status ?? 'Training in progress…',
                style: AppTypography.bodySmallFor(brightness).copyWith(
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    final selectedCount = _controller.selectedSessionIds.length;
    final canTrain = _controller.canTrain;

    // Prerequisite state: [ Train Model ] disabled with clean helper tooltip if 0 sessions selected
    if (selectedCount == 0) {
      return PrimaryButton(
        label: 'Train Model',
        leadingIcon: Icons.model_training,
        isDisabled: true,
        tooltip: 'Select at least 1 session to validate & train',
        onPressed: null,
      );
    }

    if (!canTrain) {
      return PrimaryButton(
        label: 'Validate Dataset First',
        leadingIcon: Icons.rule,
        onPressed: _controller.validateDataset,
      );
    }

    return PrimaryButton(
      label: 'Train Model',
      leadingIcon: Icons.model_training,
      onPressed: _controller.train,
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
        borderRadius: AppRadius.card,
        border: Border.all(
          color: result.success ? AppColors.accentLime : AppColors.accentDanger,
          width: 2.0,
        ),
        boxShadow: AppShadows.hard(brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.success ? Icons.verified : Icons.error,
                color: result.success ? const Color(0xFF16A34A) : AppColors.accentDanger,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  result.message,
                  style: AppTypography.h3For(brightness).copyWith(
                    color: result.success ? const Color(0xFF16A34A) : AppColors.accentDanger,
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
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
        final brightness = Theme.of(context).brightness;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: context.surface,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.card,
                side: BorderSide(
                  color: AppColors.borderColor(brightness),
                  width: 2.0,
                ),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.primaryAccent(brightness).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.borderColor(brightness), width: 1.5),
                    ),
                    child: Icon(
                      Icons.laptop_chromebook,
                      size: 20,
                      color: AppColors.primaryAccent(brightness),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Laptop Service',
                      style: AppTypography.h3For(brightness).copyWith(fontWeight: FontWeight.w800),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connect to the local Python training service running on your laptop.\n'
                      'Use "adb reverse tcp:8000 tcp:8000" for USB or enter LAN IP.',
                      style: AppTypography.captionFor(brightness).copyWith(
                        color: AppColors.textSecondary(brightness),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: hostController,
                      style: AppTypography.bodyMediumFor(brightness),
                      decoration: InputDecoration(
                        labelText: 'Host URL',
                        hintText: 'http://127.0.0.1:8000 or http://10.0.2.2:8000',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppColors.borderColor(brightness), width: 1.5),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppColors.borderColor(brightness), width: 1.5),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppColors.primaryAccent(brightness), width: 2.0),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
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
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accentLime,
                            foregroundColor: const Color(0xFF18181B),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: isChecking
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF18181B)),
                                )
                              : const Text('Test Connection', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        if (isConnected != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isConnected!
                                  ? const Color(0xFF16A34A).withValues(alpha: 0.15)
                                  : AppColors.accentDanger.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isConnected! ? const Color(0xFF16A34A) : AppColors.accentDanger,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isConnected! ? Icons.check_circle : Icons.error,
                                  color: isConnected! ? const Color(0xFF16A34A) : AppColors.accentDanger,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isConnected! ? 'Connected' : 'Unreachable',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isConnected! ? const Color(0xFF16A34A) : AppColors.accentDanger,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(color: AppColors.borderColor(brightness).withValues(alpha: 0.2)),
                    const SizedBox(height: 8),
                    Text(
                      'Import Model Artifact (JSON)',
                      style: AppTypography.bodyMediumFor(brightness).copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'You can paste a model artifact JSON exported from the laptop service to activate it directly.',
                      style: AppTypography.captionFor(brightness).copyWith(
                        color: AppColors.textSecondary(brightness),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.file_download_outlined, size: 16),
                      label: const Text('Paste & Import Artifact'),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.borderColor(brightness), width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () async {
                        final jsonController = TextEditingController();
                        bool isCombined = false;
                        final importConfirmed = await showDialog<bool>(
                          context: context,
                          builder: (c) => StatefulBuilder(
                            builder: (c, setImportState) => AlertDialog(
                              backgroundColor: context.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: AppRadius.card,
                                side: BorderSide(color: AppColors.borderColor(brightness), width: 2.0),
                              ),
                              title: Text(
                                'Import Model JSON',
                                style: AppTypography.h3For(brightness).copyWith(fontWeight: FontWeight.w800),
                              ),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(
                                    controller: jsonController,
                                    maxLines: 4,
                                    decoration: InputDecoration(
                                      hintText: '{"formatVersion": 2, "algorithm": "...", ...}',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(color: AppColors.borderColor(brightness), width: 1.5),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  SwitchListTile(
                                    dense: true,
                                    title: Text(
                                      'Is Dual-Band (60 features)',
                                      style: AppTypography.bodySmallFor(brightness).copyWith(fontWeight: FontWeight.w600),
                                    ),
                                    value: isCombined,
                                    onChanged: (v) => setImportState(() => isCombined = v),
                                  ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c, false),
                                  child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary(brightness))),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(c, true),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.brandPink,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: const Text('Activate', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
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
                  child: Text('Close', style: TextStyle(color: AppColors.textPrimary(brightness), fontWeight: FontWeight.w700)),
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