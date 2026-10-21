"""
Baseline Handcrafted Feature Extraction & Machine Learning Pipeline.

Part of the BANDANA Human Activity Recognition Research Engine.
Extracts:
1. Time-Domain Features:
   - Mean, Standard Deviation, Root Mean Square (RMS), Signal Magnitude Area (SMA)
   - Min, Max, Peak-to-Peak Amplitude, Interquartile Range (IQR), Zero Crossing Rate (ZCR)
2. Frequency-Domain Features:
   - Dominant Frequency (FFT peak), Spectral Energy, Spectral Entropy
3. Cross-Limb Coordination Features:
   - Pearson correlation between corresponding wrist and ankle axes (corr(ax_w, ax_a), etc.)
   - Cross-limb acceleration magnitude correlation
   - Relative phase lag estimate
"""

from __future__ import annotations

from typing import Dict, List, Optional, Tuple, Union

import numpy as np
from scipy import signal
from scipy import stats
from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier
from sklearn.metrics import classification_report, f1_score


class DualBandFeatureExtractor:
    """
    Extracts comprehensive time, frequency, and cross-limb features from
    windowed wrist and ankle 6-axis IMU streams.
    """

    CHANNELS = ["ax", "ay", "az", "gx", "gy", "gz"]

    def __init__(self, sampling_rate_hz: float = 40.0):
        self.sampling_rate_hz = sampling_rate_hz

    def extract_single_window(
        self,
        wrist_window: np.ndarray,
        ankle_window: np.ndarray,
    ) -> np.ndarray:
        """
        Extracts feature vector from a single pair of (wrist, ankle) windows.
        Args:
            wrist_window: (T, 6) or (6, T)
            ankle_window: (T, 6) or (6, T)
        Returns:
            1D feature vector of shape (F,)
        """
        if wrist_window.shape[0] == 6 and wrist_window.shape[1] != 6:
            wrist_window = wrist_window.T
        if ankle_window.shape[0] == 6 and ankle_window.shape[1] != 6:
            ankle_window = ankle_window.T

        features: List[float] = []

        # 1. Per-band statistical & spectral features
        for limb_name, window in [("wrist", wrist_window), ("ankle", ankle_window)]:
            # Accelerometer and Gyroscope magnitudes
            acc_mag = np.sqrt(window[:, 0]**2 + window[:, 1]**2 + window[:, 2]**2)
            gyr_mag = np.sqrt(window[:, 3]**2 + window[:, 4]**2 + window[:, 5]**2)

            for col_idx in range(6):
                sig = window[:, col_idx]
                features.extend(self._extract_signal_features(sig))

            # Magnitude features
            features.extend(self._extract_signal_features(acc_mag))
            features.extend(self._extract_signal_features(gyr_mag))

            # Signal Magnitude Area (SMA)
            sma_acc = np.sum(np.abs(window[:, :3])) / len(window)
            sma_gyr = np.sum(np.abs(window[:, 3:6])) / len(window)
            features.extend([sma_acc, sma_gyr])

        # 2. Cross-limb spatiotemporal coordination features
        for axis_idx in range(6):
            w_axis = wrist_window[:, axis_idx]
            a_axis = ankle_window[:, axis_idx]
            # Pearson correlation
            if np.std(w_axis) > 1e-6 and np.std(a_axis) > 1e-6:
                corr, _ = stats.pearsonr(w_axis, a_axis)
                features.append(0.0 if np.isnan(corr) else float(corr))
            else:
                features.append(0.0)

        # Cross-limb magnitude correlation
        w_mag = np.sqrt(wrist_window[:, 0]**2 + wrist_window[:, 1]**2 + wrist_window[:, 2]**2)
        a_mag = np.sqrt(ankle_window[:, 0]**2 + ankle_window[:, 1]**2 + ankle_window[:, 2]**2)
        if np.std(w_mag) > 1e-6 and np.std(a_mag) > 1e-6:
            corr_mag, _ = stats.pearsonr(w_mag, a_mag)
            features.append(0.0 if np.isnan(corr_mag) else float(corr_mag))
        else:
            features.append(0.0)

        # Relative energy ratio (wrist energy / (ankle energy + eps))
        energy_w = np.mean(w_mag**2)
        energy_a = np.mean(a_mag**2)
        features.append(float(energy_w / (energy_a + 1e-5)))

        return np.array(features, dtype=np.float32)

    def _extract_signal_features(self, sig: np.ndarray) -> List[float]:
        """Extracts 1D time and frequency domain features from a single axis."""
        mean_val = float(np.mean(sig))
        std_val = float(np.std(sig))
        rms_val = float(np.sqrt(np.mean(sig**2)))
        min_val = float(np.min(sig))
        max_val = float(np.max(sig))
        p2p_val = max_val - min_val
        iqr_val = float(stats.iqr(sig))

        # Zero crossing rate (relative to mean)
        zero_crossings = float(np.sum(np.diff(sig > mean_val) != 0) / len(sig))

        # FFT frequency features
        fft_vals = np.abs(np.fft.rfft(sig - mean_val))
        fft_freqs = np.fft.rfftfreq(len(sig), d=1.0 / self.sampling_rate_hz)
        spectral_energy = float(np.sum(fft_vals**2) / len(fft_vals))

        # Dominant frequency
        dom_freq = float(fft_freqs[np.argmax(fft_vals)]) if len(fft_vals) > 0 else 0.0

        # Spectral entropy
        norm_fft = fft_vals / (np.sum(fft_vals) + 1e-9)
        spectral_entropy = -float(np.sum(norm_fft * np.log2(norm_fft + 1e-9)))

        return [
            mean_val,
            std_val,
            rms_val,
            min_val,
            max_val,
            p2p_val,
            iqr_val,
            zero_crossings,
            dom_freq,
            spectral_energy,
            spectral_entropy,
        ]

    def extract_batch(
        self,
        X_wrist: np.ndarray,
        X_ankle: np.ndarray,
    ) -> np.ndarray:
        """
        Extracts features for a batch of windows.
        Args:
            X_wrist: (N, 100, 6)
            X_ankle: (N, 100, 6)
        Returns:
            X_features: (N, num_features)
        """
        num_windows = len(X_wrist)
        first_feat = self.extract_single_window(X_wrist[0], X_ankle[0])
        num_features = len(first_feat)

        out = np.zeros((num_windows, num_features), dtype=np.float32)
        out[0] = first_feat

        for i in range(1, num_windows):
            out[i] = self.extract_single_window(X_wrist[i], X_ankle[i])

        return out


class BaselineHARClassifier:
    """Random Forest / Gradient Boosting baseline classifier."""

    def __init__(
        self,
        classifier_type: str = "rf",
        n_estimators: int = 150,
        random_state: int = 42,
    ):
        self.extractor = DualBandFeatureExtractor()
        if classifier_type == "gb":
            self.clf = GradientBoostingClassifier(
                n_estimators=n_estimators,
                random_state=random_state,
            )
        else:
            self.clf = RandomForestClassifier(
                n_estimators=n_estimators,
                max_depth=15,
                random_state=random_state,
                n_jobs=-1,
            )

    def fit(self, X_wrist: np.ndarray, X_ankle: np.ndarray, y: np.ndarray):
        X_feats = self.extractor.extract_batch(X_wrist, X_ankle)
        self.clf.fit(X_feats, y)
        return self

    def predict(self, X_wrist: np.ndarray, X_ankle: np.ndarray) -> np.ndarray:
        X_feats = self.extractor.extract_batch(X_wrist, X_ankle)
        return self.clf.predict(X_feats)

    def predict_proba(self, X_wrist: np.ndarray, X_ankle: np.ndarray) -> np.ndarray:
        X_feats = self.extractor.extract_batch(X_wrist, X_ankle)
        return self.clf.predict_proba(X_feats)
