"""Unit tests for Edge Deployment, ONNX Export, and Streaming FIFO Inference."""
from pathlib import Path
import numpy as np
import pytest
import torch

from src.models.model import XConvTrans
from src.deployment.export_mobile import MobileModelExporter
from src.deployment.streaming_inference import (
    StreamingDualBandHARBuffer,
    TemporalHysteresisFilter,
)


def test_onnx_export(tmp_path):
    model = XConvTrans(num_classes=5, embed_dim=32)
    exporter = MobileModelExporter(model, num_classes=5, window_size=100)

    onnx_file = tmp_path / "test_model.onnx"
    out_path = exporter.export_to_onnx(onnx_file)
    assert out_path.exists()
    assert out_path.stat().st_size > 10_000

    meta_file = tmp_path / "metadata.json"
    exporter.export_metadata_json(["A", "B", "C", "D", "E"], meta_file)
    assert meta_file.exists()


def test_temporal_hysteresis_filter():
    filter_debouncer = TemporalHysteresisFilter(history_size=3)

    # State: 0 (Walking)
    s1, c1 = filter_debouncer.update(predicted_class=0, confidence=0.9)
    assert s1 == 0

    # Sudden momentary flick: 1 (Standing) -> Should NOT switch yet (needs majority)
    s2, c2 = filter_debouncer.update(predicted_class=1, confidence=0.85)
    assert s2 == 0  # Still debounced to 0!

    # Second consecutive vote for 1 (Standing) -> Now reaches majority (2/3) and transitions
    s3, c3 = filter_debouncer.update(predicted_class=1, confidence=0.92)
    assert s3 == 1  # Successfully transitioned to 1


def test_streaming_dual_band_buffer():
    labels = ["Walking", "Running", "Typing"]

    # Mock inference callback returning (class_idx, confidence)
    def dummy_infer(w: np.ndarray, a: np.ndarray):
        assert w.shape == (100, 6)
        assert a.shape == (100, 6)
        return 0, 0.95

    buffer = StreamingDualBandHARBuffer(
        class_labels=labels,
        inference_callback=dummy_infer,
        window_size=100,
        stride_samples=25,
    )

    dummy_sample_w = [0.1, 0.2, 9.8, 0.0, 0.0, 0.0]
    dummy_sample_a = [0.0, 0.1, 9.9, 0.0, 0.0, 0.0]

    # Feed 99 samples -> Should NOT trigger inference yet
    for _ in range(99):
        res = buffer.add_sample_pair(dummy_sample_w, dummy_sample_a)
        assert res is None

    # Feed 100th sample -> Window full AND stride (>=25) met -> Triggers inference!
    res100 = buffer.add_sample_pair(dummy_sample_w, dummy_sample_a)
    assert res100 is not None
    assert res100["activity"] == "Walking"

    # Feed next 24 samples -> Still accumulating towards next stride
    for _ in range(24):
        res = buffer.add_sample_pair(dummy_sample_w, dummy_sample_a)
        assert res is None

    # 25th sample -> Triggers second streaming inference
    res125 = buffer.add_sample_pair(dummy_sample_w, dummy_sample_a)
    assert res125 is not None
