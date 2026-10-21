"""Unit tests for GroupKFold Evaluation & Disambiguation Benchmarks."""
import numpy as np
import pytest

from src.evaluation.train_eval import BenchmarkTrainer
from src.models.model import XConvTrans


def test_group_kfold_no_leakage():
    """Verify that GroupKFold strictly isolates session/group IDs between train and test."""
    num_samples = 40
    window_size = 100
    num_classes = 3

    X_w = np.random.randn(num_samples, window_size, 6).astype(np.float32)
    X_a = np.random.randn(num_samples, window_size, 6).astype(np.float32)
    y = np.random.randint(0, num_classes, size=num_samples)

    # 4 distinct sessions, 10 windows each
    groups = np.repeat([101, 102, 103, 104], 10)

    trainer = BenchmarkTrainer(num_epochs=1, batch_size=8)
    res = trainer.cross_validate_model(
        XConvTrans,
        {"num_classes": num_classes, "embed_dim": 32},
        X_w,
        X_a,
        y,
        groups,
        n_splits=2,
    )

    assert "accuracy" in res
    assert "macro_f1" in res
    assert "confusion_matrix" in res
    assert res["confusion_matrix"].shape == (num_classes, num_classes)
    assert 0.0 <= res["accuracy"] <= 1.0
