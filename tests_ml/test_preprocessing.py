"""Unit tests for Data Standardization & Temporal Synchronization."""
import io
import numpy as np
import pandas as pd
import pytest

from src.preprocessing.preprocess_sync import (
    DualBandPreprocessor,
    SessionMetadata,
    AlignedDualBandStream,
)
from src.preprocessing.synthetic_generator import SyntheticDualBandGenerator


def test_parse_csv_schema_v2():
    preprocessor = DualBandPreprocessor()
    csv_text = (
        "# BANDANA IMU Session Export\n"
        "# Schema Version: 2\n"
        "# Session ID: 42\n"
        "# Participant ID: test_user\n"
        "# Activity: Walking\n"
        "sessionId,participantId,activity,bandRole,captureTimestampMs,receiveTimestamp,deviceId,deviceName,ax,ay,az,gx,gy,gz,accelMag,gyroMag\n"
        '42,"test_user","Walking",wrist,100,2026-10-16T10:00:00.000Z,D1,W,0.1,0.2,9.8,0.01,0.02,0.03,9.8,0.03\n'
        '42,"test_user","Walking",ankle,105,2026-10-16T10:00:00.005Z,D2,A,0.3,0.4,9.9,0.04,0.05,0.06,9.9,0.08\n'
    )
    df, meta = preprocessor.parse_csv(io.StringIO(csv_text))
    assert meta.session_id == 42
    assert meta.participant_id == "test_user"
    assert meta.activity == "Walking"
    assert len(df) == 2


def test_synchronize_and_interpolate_to_40hz():
    generator = SyntheticDualBandGenerator(sampling_rate_hz=40.0, random_seed=123)
    df = generator.generate_session(
        session_id=1,
        participant_id="sub_1",
        activity="Walking",
        duration_sec=5.0,
    )
    preprocessor = DualBandPreprocessor(target_freq_hz=40.0)
    aligned = preprocessor.synchronize_session(df)

    assert isinstance(aligned, AlignedDualBandStream)
    assert aligned.sampling_rate_hz == 40.0
    assert aligned.wrist_data.shape[1] == 6
    assert aligned.ankle_data.shape[1] == 6
    assert len(aligned.wrist_data) == len(aligned.ankle_data)
    assert len(aligned.time_grid_ms) == len(aligned.wrist_data)

    # Check that time step is exactly 25.0 ms
    diffs = np.diff(aligned.time_grid_ms)
    np.testing.assert_allclose(diffs, 25.0, atol=1e-3)


def test_segment_sliding_windows():
    generator = SyntheticDualBandGenerator(sampling_rate_hz=40.0, random_seed=456)
    df = generator.generate_session(
        session_id=99,
        participant_id="sub_test",
        activity="Running",
        duration_sec=6.0,  # 240 samples @ 40 Hz
    )
    preprocessor = DualBandPreprocessor(
        target_freq_hz=40.0,
        window_size_samples=100,
        stride_samples=50,
    )
    aligned = preprocessor.synchronize_session(df)
    x_w, x_a, y, groups = preprocessor.segment_sliding_windows(aligned)

    # With 240 samples, window 100, stride 50:
    # starts at 0, 50, 100 -> 3 full windows
    expected_windows = 1 + (len(aligned.time_grid_ms) - 100) // 50
    assert len(x_w) == expected_windows
    assert x_w.shape == (expected_windows, 100, 6)
    assert x_a.shape == (expected_windows, 100, 6)
    assert len(y) == expected_windows
    assert y[0] == "Running"
    assert groups[0] == 99


def test_kinematic_sync_lag_detection():
    preprocessor = DualBandPreprocessor(auto_kinematic_sync=True)
    generator = SyntheticDualBandGenerator(random_seed=789)
    df = generator.generate_session(
        session_id=7,
        participant_id="sub_7",
        activity="Jumping Jacks",
        duration_sec=8.0,
    )
    aligned = preprocessor.synchronize_session(df)
    # Offset should be bounded within max_sync_lag_ms
    assert abs(aligned.sync_offset_ms) <= preprocessor.max_sync_lag_ms
