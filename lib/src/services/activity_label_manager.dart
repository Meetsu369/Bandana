import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/ble_constants.dart';

/// Manages built-in and user-defined custom activity labels.
///
/// Ensures labels are trimmed, deduplicated (case-insensitively),
/// and persisted across app restarts using [SharedPreferences].
class ActivityLabelManager extends ChangeNotifier {
  ActivityLabelManager({required SharedPreferences prefs}) : _prefs = prefs {
    _loadCustomLabels();
  }

  final SharedPreferences _prefs;
  static const String _storageKey = 'bandana_custom_activities';

  final List<String> _customLabels = [];

  /// Get all active labels: default built-ins followed by user-defined custom labels.
  List<String> get allLabels => [
        ...BleConstants.defaultLabels,
        ..._customLabels,
      ];

  /// Get user-added custom labels only.
  List<String> get customLabels => List.unmodifiable(_customLabels);

  void _loadCustomLabels() {
    final stored = _prefs.getStringList(_storageKey);
    if (stored != null) {
      _customLabels.clear();
      for (final label in stored) {
        final clean = label.trim();
        if (clean.isNotEmpty &&
            !_customLabels.any((l) => l.toLowerCase() == clean.toLowerCase()) &&
            !BleConstants.defaultLabels.any((l) => l.toLowerCase() == clean.toLowerCase())) {
          _customLabels.add(clean);
        }
      }
    }
  }

  /// Validation result when attempting to add or edit a label.
  String? validateLabel(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return 'Activity label cannot be empty';
    }

    final trimmed = raw.trim();
    if (trimmed.length > 40) {
      return 'Activity label must be 40 characters or fewer';
    }

    // Check for filesystem-invalid characters that might corrupt export filenames
    if (RegExp(r'[\\/:*?"<>|]').hasMatch(trimmed)) {
      return 'Label cannot contain characters: \\ / : * ? " < > |';
    }

    final normalized = trimmed.toLowerCase();

    // Check against default labels
    if (BleConstants.defaultLabels.any((l) => l.toLowerCase() == normalized)) {
      return 'This activity is already built-in';
    }

    // Check against custom labels
    if (_customLabels.any((l) => l.toLowerCase() == normalized)) {
      return 'An activity with this name already exists';
    }

    return null;
  }

  /// Add a custom activity label. Returns true if added, false if invalid/duplicate.
  Future<bool> addCustomLabel(String raw) async {
    final validationError = validateLabel(raw);
    if (validationError != null) return false;

    final clean = raw.trim();
    _customLabels.add(clean);
    await _saveCustomLabels();
    notifyListeners();
    return true;
  }

  /// Remove a custom label. Built-in labels cannot be removed.
  Future<bool> removeCustomLabel(String label) async {
    final index = _customLabels.indexWhere(
      (l) => l.toLowerCase() == label.trim().toLowerCase(),
    );
    if (index == -1) return false;

    _customLabels.removeAt(index);
    await _saveCustomLabels();
    notifyListeners();
    return true;
  }

  Future<void> _saveCustomLabels() async {
    await _prefs.setStringList(_storageKey, _customLabels);
  }
}
