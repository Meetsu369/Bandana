"""Models package for BANDANA dual-band activity recognition."""
from src.models.model import (
    XConvTrans,
    WristOnlyConvNet,
    AnkleOnlyConvNet,
    DualStreamEarlyFusion,
)
from src.models.baseline_rf import (
    DualBandFeatureExtractor,
    BaselineHARClassifier,
)

__all__ = [
    "XConvTrans",
    "WristOnlyConvNet",
    "AnkleOnlyConvNet",
    "DualStreamEarlyFusion",
    "DualBandFeatureExtractor",
    "BaselineHARClassifier",
]
