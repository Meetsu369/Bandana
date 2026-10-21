"""Evaluation package for BANDANA dual-band activity recognition."""
from src.evaluation.train_eval import (
    BenchmarkTrainer,
    run_comprehensive_benchmark,
)

__all__ = [
    "BenchmarkTrainer",
    "run_comprehensive_benchmark",
]
