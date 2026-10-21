"""
Dual-IMU (Wrist + Ankle) Data Standardization & Temporal Synchronization Pipeline.

Part of the BANDANA Human Activity Recognition Research Engine.
Converts asynchronous, jittered mobile BLE arrival streams into a strictly uniform
40 Hz (25 ms period) 12-channel aligned representation with cross-correlation phase sync
and overlapping sliding-window segmentation.
"""

from __future__ import annotations

import io
import os
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Union

import numpy as np
import pandas as pd
from scipy import signal
from scipy.interpolate import interp1d


@dataclass
class SessionMetadata:
    """Stores metadata extracted from BANDANA session CSV export headers."""
    session_id: Optional[int] = None
    participant_id: str = "unknown"
    activity: str = "unknown"
    start_time: Optional[str] = None
    schema_version: int = 2
    notes: Optional[str] = None
    custom_fields: Dict[str, str] = field(default_factory=dict)


@dataclass
class AlignedDualBandStream:
    """Represents a strictly synchronized, uniformly sampled 40 Hz dual-band recording."""
    time_grid_ms: np.ndarray          # (T,) uniform timestamps in milliseconds
    wrist_data: np.ndarray            # (T, 6) [ax, ay, az, gx, gy, gz]
    ankle_data: np.ndarray            # (T, 6) [ax, ay, az, gx, gy, gz]
    activity: str
    participant_id: str
    session_id: int
    sampling_rate_hz: float = 40.0
    sync_offset_ms: float = 0.0       # Kinematic calibration lag applied (ms)

    @property
    def channels_12(self) -> np.ndarray:
        """Returns concatenated 12-channel array: [wrist (6), ankle (6)]."""
        return np.concatenate([self.wrist_data, self.ankle_data], axis=-1)


class DualBandPreprocessor:
    """
    Standardizes and synchronizes dual-band (wrist + ankle) IMU recordings.
    
    Features:
    1. Robust CSV parsing with header comment extraction.
    2. Monotonic capture timestamp recovery with fallback to receive time.
    3. Piecewise linear interpolation onto an exact 40 Hz (25 ms) uniform grid.
    4. Kinematic calibration sync via cross-correlation on impact spikes (stomp/clap).
    5. Overlapping sliding-window segmentation (100 samples / 2.5s window, 50% stride).
    """

    CHANNELS = ["ax", "ay", "az", "gx", "gy", "gz"]
    TARGET_FREQ_HZ = 40.0
    PERIOD_MS = 1000.0 / TARGET_FREQ_HZ  # 25.0 ms
    WINDOW_SIZE_SAMPLES = 100            # 2.5 seconds @ 40 Hz
    STRIDE_SAMPLES = 50                  # 50% overlap (1.25 seconds @ 40 Hz)

    def __init__(
        self,
        target_freq_hz: float = 40.0,
        window_size_samples: int = 100,
        stride_samples: int = 50,
        max_sync_lag_ms: float = 1000.0,
        auto_kinematic_sync: bool = True,
    ):
        self.target_freq_hz = target_freq_hz
        self.period_ms = 1000.0 / target_freq_hz
        self.window_size = window_size_samples
        self.stride = stride_samples
        self.max_sync_lag_ms = max_sync_lag_ms
        self.auto_kinematic_sync = auto_kinematic_sync

    def parse_csv(self, file_path_or_buffer: Union[str, Path, io.StringIO]) -> Tuple[pd.DataFrame, SessionMetadata]:
        """
        Parses a BANDANA session CSV, extracting metadata comments (# ...) and raw sample rows.
        Supports both Schema v2 and legacy flat CSV logs.
        """
        metadata = SessionMetadata()
        raw_lines: List[str] = []

        if isinstance(file_path_or_buffer, (str, Path)):
            with open(file_path_or_buffer, "r", encoding="utf-8", errors="ignore") as f:
                content = f.readlines()
        else:
            content = file_path_or_buffer.getvalue().splitlines(keepends=True)

        for line in content:
            stripped = line.strip()
            if not stripped:
                continue
            if stripped.startswith("#"):
                # Parse metadata header
                parts = stripped[1:].split(":", 1)
                if len(parts) == 2:
                    k, v = parts[0].strip().lower(), parts[1].strip()
                    if "schema version" in k:
                        metadata.schema_version = int(re.sub(r"[^\d]", "", v) or 2)
                    elif "session id" in k:
                        metadata.session_id = int(re.sub(r"[^\d]", "", v) or 0)
                    elif "participant id" in k:
                        metadata.participant_id = v
                    elif "activity" in k:
                        metadata.activity = v
                    elif "start time" in k:
                        metadata.start_time = v
                    elif "notes" in k:
                        metadata.notes = v
                    else:
                        metadata.custom_fields[k] = v
            else:
                raw_lines.append(line)

        if not raw_lines:
            raise ValueError("CSV contains no tabular data rows.")

        df = pd.read_csv(io.StringIO("".join(raw_lines)))

        # Clean column names
        df.columns = df.columns.str.strip().str.replace('"', "")

        # Fallback metadata from first row if not present in comments
        if metadata.session_id is None and "sessionId" in df.columns:
            metadata.session_id = int(df["sessionId"].iloc[0])
        if metadata.participant_id == "unknown" and "participantId" in df.columns:
            metadata.participant_id = str(df["participantId"].iloc[0]).strip('"')
        if metadata.activity == "unknown" and "activity" in df.columns:
            metadata.activity = str(df["activity"].iloc[0]).strip('"')

        return df, metadata

    def synchronize_session(
        self,
        df: pd.DataFrame,
        metadata: Optional[SessionMetadata] = None,
    ) -> AlignedDualBandStream:
        """
        Converts asynchronous raw dataframe rows into aligned, uniform 40 Hz dual-band arrays.
        """
        # Determine band role column
        role_col = None
        for cand in ["bandRole", "role", "band"]:
            if cand in df.columns:
                role_col = cand
                break
        if role_col is None:
            raise KeyError("CSV missing bandRole column identifying 'wrist' vs 'ankle'.")

        # Normalize role values
        df[role_col] = df[role_col].astype(str).str.strip().str.lower()
        wrist_df = df[df[role_col].isin(["wrist", "bandrole.wrist"])].copy()
        ankle_df = df[df[role_col].isin(["ankle", "bandrole.ankle"])].copy()

        if wrist_df.empty:
            raise ValueError("No wrist samples found in dataset.")
        if ankle_df.empty:
            raise ValueError("No ankle samples found in dataset.")

        # Extract timestamps in milliseconds
        t_wrist = self._extract_timestamps_ms(wrist_df)
        t_ankle = self._extract_timestamps_ms(ankle_df)

        # Sort and deduplicate timestamps
        wrist_df, t_wrist = self._clean_and_sort(wrist_df, t_wrist)
        ankle_df, t_ankle = self._clean_and_sort(ankle_df, t_ankle)

        # Optional kinematic calibration alignment (cross-correlation on impact magnitude)
        sync_offset_ms = 0.0
        if self.auto_kinematic_sync:
            sync_offset_ms = self._compute_kinematic_calibration_offset(
                wrist_df, t_wrist, ankle_df, t_ankle
            )
            # Shift ankle timestamps by the computed clock offset
            t_ankle = t_ankle - sync_offset_ms

        # Determine overlapping temporal boundaries
        start_ms = max(t_wrist[0], t_ankle[0])
        end_ms = min(t_wrist[-1], t_ankle[-1])

        if end_ms - start_ms < (self.window_size * self.period_ms):
            raise ValueError(
                f"Overlapping duration ({end_ms - start_ms:.1f} ms) is shorter than "
                f"one required window ({self.window_size * self.period_ms:.1f} ms)."
            )

        # Build strictly uniform 40 Hz time grid
        uniform_time_grid = np.arange(start_ms, end_ms, self.period_ms)
        if len(uniform_time_grid) == 0:
            raise ValueError("Empty uniform time grid generated.")

        # Interpolate 6 channels for wrist and ankle onto the uniform grid
        wrist_interp = self._interpolate_channels(wrist_df, t_wrist, uniform_time_grid)
        ankle_interp = self._interpolate_channels(ankle_df, t_ankle, uniform_time_grid)

        sess_id = metadata.session_id if metadata and metadata.session_id is not None else (int(df["sessionId"].iloc[0]) if "sessionId" in df.columns else 1)
        part_id = metadata.participant_id if metadata and metadata.participant_id != "unknown" else (str(df["participantId"].iloc[0]).strip('"') if "participantId" in df.columns else "participant_1")
        act = metadata.activity if metadata and metadata.activity != "unknown" else (str(df["activity"].iloc[0]).strip('"') if "activity" in df.columns else "unlabeled")

        return AlignedDualBandStream(
            time_grid_ms=uniform_time_grid,
            wrist_data=wrist_interp,
            ankle_data=ankle_interp,
            activity=act,
            participant_id=part_id,
            session_id=sess_id,
            sampling_rate_hz=self.target_freq_hz,
            sync_offset_ms=sync_offset_ms,
        )

    def _extract_timestamps_ms(self, df: pd.DataFrame) -> np.ndarray:
        """
        Extracts monotonic millisecond timestamps. Prefers firmware `captureTimestampMs`.
        Falls back to parsing ISO `receiveTimestamp` or generic `timestamp`.
        """
        if "captureTimestampMs" in df.columns:
            ts = pd.to_numeric(df["captureTimestampMs"], errors="coerce").to_numpy()
            # If capture timestamps are valid non-negative monotonic numbers
            if not np.isnan(ts).all() and (ts > 0).sum() > len(ts) * 0.8:
                # Handle reset/overflow if present, or zero-offset
                valid_mask = ~np.isnan(ts) & (ts >= 0)
                if valid_mask.sum() > 2:
                    base = ts[valid_mask][0]
                    return ts - base

        # Fallback to receiveTimestamp / timestamp
        for col in ["receiveTimestamp", "timestamp", "time"]:
            if col in df.columns:
                try:
                    dt = pd.to_datetime(df[col], errors="coerce")
                    if not dt.isna().all():
                        ms = (dt - dt.dropna().iloc[0]).dt.total_seconds().to_numpy() * 1000.0
                        return ms
                except Exception:
                    pass

        # Last resort: synthetic 40Hz index-based sequence
        return np.arange(len(df), dtype=float) * self.period_ms

    def _clean_and_sort(self, df: pd.DataFrame, timestamps: np.ndarray) -> Tuple[pd.DataFrame, np.ndarray]:
        """Removes NaN timestamps, sorts chronologically, and removes exact duplicates."""
        valid_idx = ~np.isnan(timestamps)
        df = df.iloc[valid_idx].copy()
        timestamps = timestamps[valid_idx]

        sort_idx = np.argsort(timestamps)
        df = df.iloc[sort_idx].copy()
        timestamps = timestamps[sort_idx]

        # Deduplicate identical timestamps by adding epsilon (0.01 ms)
        unique_mask = np.diff(timestamps, prepend=-1.0) > 0.001
        df = df.iloc[unique_mask].copy()
        timestamps = timestamps[unique_mask]

        return df, timestamps

    def _compute_kinematic_calibration_offset(
        self,
        wrist_df: pd.DataFrame,
        t_wrist: np.ndarray,
        ankle_df: pd.DataFrame,
        t_ankle: np.ndarray,
    ) -> float:
        """
        Calculates temporal lag between wrist and ankle using cross-correlation
        of accelerometer dynamic acceleration magnitudes.
        Tuned to lock onto impact spikes (foot stomp or clap sync gesture).
        """
        try:
            # Calculate acceleration magnitude: sqrt(ax^2 + ay^2 + az^2)
            w_acc = np.sqrt(
                wrist_df["ax"]**2 + wrist_df["ay"]**2 + wrist_df["az"]**2
            ).to_numpy()
            a_acc = np.sqrt(
                ankle_df["ax"]**2 + ankle_df["ay"]**2 + ankle_df["az"]**2
            ).to_numpy()

            # Resample both raw magnitudes onto a common coarse grid for cross-correlation
            common_start = max(t_wrist[0], t_ankle[0])
            common_end = min(t_wrist[-1], t_ankle[-1])
            if (common_end - common_start) < 2000:
                return 0.0

            corr_grid = np.arange(common_start, common_end, self.period_ms)
            f_w = interp1d(t_wrist, w_acc, kind="linear", bounds_error=False, fill_value="extrapolate")
            f_a = interp1d(t_ankle, a_acc, kind="linear", bounds_error=False, fill_value="extrapolate")

            sig_w = f_w(corr_grid)
            sig_a = f_a(corr_grid)

            # High-pass filter or detrend to highlight sharp impact spikes
            sig_w = sig_w - np.mean(sig_w)
            sig_a = sig_a - np.mean(sig_a)

            # Limit lag search to +/- max_sync_lag_ms
            max_lag_samples = int(self.max_sync_lag_ms / self.period_ms)
            corr = signal.correlate(sig_w, sig_a, mode="full")
            lags = signal.correlation_lags(len(sig_w), len(sig_a), mode="full")

            valid_lags_mask = np.abs(lags) <= max_lag_samples
            if not np.any(valid_lags_mask):
                return 0.0

            valid_corr = corr[valid_lags_mask]
            valid_lags = lags[valid_lags_mask]

            best_lag_samples = valid_lags[np.argmax(valid_corr)]
            lag_ms = float(best_lag_samples * self.period_ms)

            # If cross-correlation peak is weak, do not apply spurious shift
            peak_val = np.max(valid_corr)
            rms = np.sqrt(np.mean(valid_corr**2))
            if peak_val < 1.5 * rms:
                return 0.0

            return lag_ms
        except Exception:
            return 0.0

    def _interpolate_channels(
        self,
        df: pd.DataFrame,
        src_timestamps: np.ndarray,
        target_grid: np.ndarray,
    ) -> np.ndarray:
        """
        Interpolates the 6 IMU channels [ax, ay, az, gx, gy, gz] onto the uniform target grid.
        Returns a (T, 6) float32 numpy array.
        """
        out = np.zeros((len(target_grid), len(self.CHANNELS)), dtype=np.float32)

        for col_idx, ch in enumerate(self.CHANNELS):
            if ch in df.columns:
                vals = pd.to_numeric(df[ch], errors="coerce").fillna(0.0).to_numpy()
                interp_fn = interp1d(
                    src_timestamps,
                    vals,
                    kind="linear",
                    bounds_error=False,
                    fill_value="extrapolate",
                )
                out[:, col_idx] = interp_fn(target_grid).astype(np.float32)
            else:
                out[:, col_idx] = 0.0

        return out

    def segment_sliding_windows(
        self,
        aligned_stream: AlignedDualBandStream,
    ) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
        """
        Segments aligned stream into overlapping sliding windows.
        
        Returns:
            X_wrist: (N, 100, 6) float32
            X_ankle: (N, 100, 6) float32
            y: (N,) string label array
            groups: (N,) int session_id array for GroupKFold/LOSO
        """
        total_samples = len(aligned_stream.time_grid_ms)
        if total_samples < self.window_size:
            return (
                np.empty((0, self.window_size, 6), dtype=np.float32),
                np.empty((0, self.window_size, 6), dtype=np.float32),
                np.empty((0,), dtype=object),
                np.empty((0,), dtype=np.int32),
            )

        num_windows = 1 + (total_samples - self.window_size) // self.stride

        wrist_windows = np.zeros((num_windows, self.window_size, 6), dtype=np.float32)
        ankle_windows = np.zeros((num_windows, self.window_size, 6), dtype=np.float32)
        labels = np.array([aligned_stream.activity] * num_windows, dtype=object)
        groups = np.full(num_windows, aligned_stream.session_id, dtype=np.int32)

        for i in range(num_windows):
            start = i * self.stride
            end = start + self.window_size
            wrist_windows[i] = aligned_stream.wrist_data[start:end]
            ankle_windows[i] = aligned_stream.ankle_data[start:end]

        return wrist_windows, ankle_windows, labels, groups

    def process_multiple_sessions(
        self,
        file_paths: List[Union[str, Path]],
        output_dir: Optional[Union[str, Path]] = None,
    ) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
        """
        Processes a list of session CSV files and produces combined datasets.
        Optionally saves X_wrist.npy, X_ankle.npy, y.npy, groups.npy.
        """
        all_wrist: List[np.ndarray] = []
        all_ankle: List[np.ndarray] = []
        all_y: List[np.ndarray] = []
        all_groups: List[np.ndarray] = []

        for p in file_paths:
            try:
                df, meta = self.parse_csv(p)
                aligned = self.synchronize_session(df, meta)
                x_w, x_a, y, grp = self.segment_sliding_windows(aligned)
                if len(y) > 0:
                    all_wrist.append(x_w)
                    all_ankle.append(x_a)
                    all_y.append(y)
                    all_groups.append(grp)
            except Exception as e:
                print(f"[Preprocessor] Warning: Skipping {p} due to: {e}")

        if not all_wrist:
            raise RuntimeError("No valid windows could be extracted from provided CSV files.")

        X_wrist = np.concatenate(all_wrist, axis=0)
        X_ankle = np.concatenate(all_ankle, axis=0)
        y = np.concatenate(all_y, axis=0)
        groups = np.concatenate(all_groups, axis=0)

        if output_dir:
            out_p = Path(output_dir)
            out_p.mkdir(parents=True, exist_ok=True)
            np.save(out_p / "X_wrist.npy", X_wrist)
            np.save(out_p / "X_ankle.npy", X_ankle)
            np.save(out_p / "y.npy", y)
            np.save(out_p / "groups.npy", groups)
            print(f"[Preprocessor] Successfully saved dataset to {out_p}: {len(y)} windows, {len(np.unique(y))} classes.")

        return X_wrist, X_ankle, y, groups
