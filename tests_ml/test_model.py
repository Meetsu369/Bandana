"""Unit tests for Neural Architecture and Feature Extraction."""
import numpy as np
import pytest
import torch

from src.models.model import (
    XConvTrans,
    WristOnlyConvNet,
    AnkleOnlyConvNet,
    DualStreamEarlyFusion,
)
from src.models.baseline_rf import DualBandFeatureExtractor, BaselineHARClassifier


def test_model_parameter_budget():
    """Verify strictly under 150k parameter budget."""
    model = XConvTrans(num_classes=7, embed_dim=32)
    total_params = model.total_parameters
    assert total_params < 150_000, f"XConvTrans has {total_params} parameters, exceeding 150k limit!"
    print(f"XConvTrans parameter count: {total_params} (< 150,000)")


def test_forward_pass_shapes():
    """Verify forward pass output shape for batch."""
    batch_size = 4
    num_classes = 7
    window_size = 100
    model = XConvTrans(num_classes=num_classes, embed_dim=32)
    model.eval()

    # Channels first (B, 6, 100)
    x_w = torch.randn(batch_size, 6, window_size)
    x_a = torch.randn(batch_size, 6, window_size)
    out = model(x_w, x_a)
    assert out.shape == (batch_size, num_classes)

    # Channels last (B, 100, 6)
    x_w_t = torch.randn(batch_size, window_size, 6)
    x_a_t = torch.randn(batch_size, window_size, 6)
    out_t = model(x_w_t, x_a_t)
    assert out_t.shape == (batch_size, num_classes)


def test_gradient_backprop():
    """Verify backpropagation through dual-stream cross-attention."""
    model = XConvTrans(num_classes=5, embed_dim=32)
    model.train()

    x_w = torch.randn(2, 6, 100, requires_grad=True)
    x_a = torch.randn(2, 6, 100, requires_grad=True)
    target = torch.tensor([1, 3], dtype=torch.long)

    logits = model(x_w, x_a)
    loss = torch.nn.functional.cross_entropy(logits, target)
    loss.backward()

    # Verify input gradients exist and are non-zero
    assert x_w.grad is not None and torch.norm(x_w.grad) > 0
    assert x_a.grad is not None and torch.norm(x_a.grad) > 0


def test_ablation_models():
    """Verify WristOnly, AnkleOnly, and EarlyFusion ablation variants."""
    x_w = torch.randn(3, 6, 100)
    x_a = torch.randn(3, 6, 100)

    m_wrist = WristOnlyConvNet(num_classes=6)
    assert m_wrist(x_w).shape == (3, 6)

    m_ankle = AnkleOnlyConvNet(num_classes=6)
    assert m_ankle(x_ankle=x_a).shape == (3, 6)

    m_early = DualStreamEarlyFusion(num_classes=6)
    assert m_early(x_w, x_a).shape == (3, 6)


def test_handcrafted_feature_extractor():
    extractor = DualBandFeatureExtractor(sampling_rate_hz=40.0)
    w = np.random.randn(100, 6).astype(np.float32)
    a = np.random.randn(100, 6).astype(np.float32)

    feat = extractor.extract_single_window(w, a)
    assert isinstance(feat, np.ndarray)
    assert feat.ndim == 1
    assert len(feat) > 50  # Over 50 rich time/frequency/cross-limb features
    assert not np.isnan(feat).any()
