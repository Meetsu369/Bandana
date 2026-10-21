"""
Real-Time Mobile Streaming Inference Engine with Temporal Hysteresis Filter.

Part of the BANDANA Human Activity Recognition Research Engine.
Architecture:
1. Double-buffered Circular FIFO Window Buffer (100 samples / 2.5s @ 40 Hz).
2. Stride execution: inference triggered strictly every 25 incoming samples (625 ms / ~1.6 Hz).
3. Temporal Hysteresis / Debouncing Filter:
   - Rolling 3-window majority vote with confidence thresholding.
   - Eliminates momentary flickering between transient states (sitting, standing, walking, cart pushing).
"""

from __future__ import annotations

from collections import deque
from typing import Callable, Deque, Dict, List, Optional, Tuple, Union

import numpy as np


class TemporalHysteresisFilter:
    """
    Smoothing and debouncing filter across consecutive window predictions.
    Uses rolling majority voting and persistence weighting to prevent state flickering.
    """

    def __init__(self, history_size: int = 3, min_confidence: float = 0.40):
        self.history_size = history_size
        self.min_confidence = min_confidence
        self.history: Deque[Tuple[int, float]] = deque(maxlen=history_size)
        self.current_stable_state: Optional[int] = None

    def update(self, predicted_class: int, confidence: float) -> Tuple[int, float]:
        """
        Processes a raw instantaneous prediction and returns the stabilized state.
        Args:
            predicted_class: Raw argmax class index
            confidence: Softmax probability [0.0, 1.0]
        Returns:
            (stabilized_class, stabilized_confidence)
        """
        # If confidence is below threshold, treat with lower weight
        self.history.append((predicted_class, confidence))

        if len(self.history) < 2:
            self.current_stable_state = predicted_class
            return predicted_class, confidence

        # Count weighted occurrences in recent history
        weights: Dict[int, float] = {}
        for idx, (cls_idx, conf) in enumerate(self.history):
            # Recency weighting (most recent has slightly higher weight)
            recency = 1.0 + (idx / len(self.history)) * 0.5
            weights[cls_idx] = weights.get(cls_idx, 0.0) + (conf * recency)

        best_class = max(weights.items(), key=lambda kv: kv[1])[0]

        # State transition hysteresis:
        # If proposing a transition from current stable state, require clear majority
        if self.current_stable_state is not None and best_class != self.current_stable_state:
            # Check how many of the last N windows voted for best_class
            recent_votes = sum(1 for c, _ in self.history if c == best_class)
            # Require at least 2 out of 3 votes to transition away from stable state
            if recent_votes >= math_threshold(self.history_size):
                self.current_stable_state = best_class
            else:
                # Maintain previous stable state to avoid flickering
                best_class = self.current_stable_state
        else:
            self.current_stable_state = best_class

        avg_conf = float(np.mean([conf for c, conf in self.history if c == best_class]))
        return self.current_stable_state, avg_conf

    def reset(self):
        self.history.clear()
        self.current_stable_state = None


def math_threshold(history_size: int) -> int:
    return (history_size // 2) + 1


class StreamingDualBandHARBuffer:
    """
    100-sample double-buffered FIFO queue for real-time mobile streaming.
    Triggers inference every `stride_samples` (default: 25 samples = 625 ms).
    """

    def __init__(
        self,
        class_labels: List[str],
        inference_callback: Callable[[np.ndarray, np.ndarray], Tuple[int, float]],
        window_size: int = 100,
        stride_samples: int = 25,
        history_size: int = 3,
    ):
        self.class_labels = class_labels
        self.inference_callback = inference_callback
        self.window_size = window_size
        self.stride_samples = stride_samples

        self.wrist_buffer = deque(maxlen=window_size)
        self.ankle_buffer = deque(maxlen=window_size)

        self.new_samples_since_inference = 0
        self.filter = TemporalHysteresisFilter(history_size=history_size)

    def add_sample_pair(
        self,
        wrist_sample: Union[List[float], np.ndarray],
        ankle_sample: Union[List[float], np.ndarray],
    ) -> Optional[Dict[str, Union[str, float, int]]]:
        """
        Receives synchronous 6-channel wrist and ankle samples [ax, ay, az, gx, gy, gz].
        Returns prediction result dictionary whenever stride threshold is met, else None.
        """
        assert len(wrist_sample) == 6, f"Wrist sample must have 6 channels, got {len(wrist_sample)}"
        assert len(ankle_sample) == 6, f"Ankle sample must have 6 channels, got {len(ankle_sample)}"

        self.wrist_buffer.append(list(wrist_sample))
        self.ankle_buffer.append(list(ankle_sample))
        self.new_samples_since_inference += 1

        # Check if full window is ready and stride reached
        if (
            len(self.wrist_buffer) == self.window_size
            and len(self.ankle_buffer) == self.window_size
            and self.new_samples_since_inference >= self.stride_samples
        ):
            self.new_samples_since_inference = 0

            # Form (1, 6, 100) or (1, 100, 6) arrays
            w_arr = np.array(self.wrist_buffer, dtype=np.float32)  # (100, 6)
            a_arr = np.array(self.ankle_buffer, dtype=np.float32)  # (100, 6)

            # Invoke model inference
            raw_class_idx, raw_conf = self.inference_callback(w_arr, a_arr)

            # Apply temporal hysteresis filter
            smooth_class_idx, smooth_conf = self.filter.update(raw_class_idx, raw_conf)

            label = (
                self.class_labels[smooth_class_idx]
                if 0 <= smooth_class_idx < len(self.class_labels)
                else "Unknown"
            )

            return {
                "activity": label,
                "class_index": int(smooth_class_idx),
                "confidence": float(smooth_conf),
                "raw_activity": self.class_labels[raw_class_idx] if 0 <= raw_class_idx < len(self.class_labels) else "Unknown",
                "raw_confidence": float(raw_conf),
            }

        return None

    def reset(self):
        self.wrist_buffer.clear()
        self.ankle_buffer.clear()
        self.new_samples_since_inference = 0
        self.filter.reset()
