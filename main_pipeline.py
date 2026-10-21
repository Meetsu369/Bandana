"""
BANDANA: Complete Dual-IMU (Wrist + Ankle) HAR Pipeline & Research Benchmark Driver.

Executes:
1. Data Standardization & 40 Hz Temporal Synchronization (Phase 1)
2. Dual-Stream Cross-Attention ConvNet (X-ConvTrans) and Baseline Extraction (Phase 2)
3. Rigorous GroupKFold Cross-Validation & Disambiguation Ablation (Phase 3)
4. ONNX Mobile Export & Real-Time FIFO Streaming Simulation (Phase 4)
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
import torch

from src.preprocessing.preprocess_sync import DualBandPreprocessor
from src.preprocessing.synthetic_generator import SyntheticDualBandGenerator
from src.models.model import XConvTrans
from src.models.baseline_rf import BaselineHARClassifier
from src.evaluation.train_eval import run_comprehensive_benchmark
from src.deployment.export_mobile import MobileModelExporter
from src.deployment.streaming_inference import StreamingDualBandHARBuffer


def main():
    parser = argparse.ArgumentParser(description="BANDANA Dual-Band HAR Research & Deployment Pipeline")
    parser.add_argument("--data-dir", type=str, default="data/raw_sessions", help="Directory with raw session CSVs")
    parser.add_argument("--output-dir", type=str, default="benchmark_results", help="Directory for evaluation artifacts")
    parser.add_argument("--epochs", type=int, default=12, help="Number of training epochs per fold")
    parser.add_argument("--generate-synthetic", action="store_true", default=True, help="Synthesize benchmark sessions if none exist")
    args = parser.parse_args()

    data_p = Path(args.data_dir)
    out_p = Path(args.output_dir)
    out_p.mkdir(parents=True, exist_ok=True)

    print("=" * 75)
    print("BANDANA DUAL-IMU HAR: END-TO-END RESEARCH & MOBILE PIPELINE")
    print("=" * 75)

    # ── PHASE 1: Data Standardization & Temporal Synchronization ──
    csv_files = list(data_p.glob("*.csv")) if data_p.exists() else []
    if not csv_files and args.generate_synthetic:
        print(f"\n[Phase 1] No CSVs found in {data_p}. Synthesizing multi-subject benchmark dataset...")
        generator = SyntheticDualBandGenerator(sampling_rate_hz=40.0, random_seed=42)
        csv_files = generator.generate_full_benchmark_dataset(
            output_dir=data_p,
            num_participants=4,
            session_duration_sec=25.0,
        )

    print(f"\n[Phase 1] Standardizing and synchronizing {len(csv_files)} session CSVs to 40 Hz...")
    preprocessor = DualBandPreprocessor(
        target_freq_hz=40.0,
        window_size_samples=100,  # 2.5 seconds
        stride_samples=50,        # 50% overlap / 1.25 seconds
        auto_kinematic_sync=True,
    )
    processed_dir = out_p / "processed_data"
    X_wrist, X_ankle, y, groups = preprocessor.process_multiple_sessions(
        file_paths=csv_files,
        output_dir=processed_dir,
    )

    print(f"[Phase 1] Extracted {len(y)} windows across {len(np.unique(groups))} sessions.")
    print(f"  Wrist shape:  {X_wrist.shape} (T=100 samples, 6 channels)")
    print(f"  Ankle shape:  {X_ankle.shape} (T=100 samples, 6 channels)")
    print(f"  Labels:       {np.unique(y).tolist()}")

    # ── PHASE 2 & 3: Rigorous Evaluation & Academic Benchmarking ──
    print(f"\n[Phase 2 & 3] Running 4-way ablation benchmark (LOSO / GroupKFold)...")
    results = run_comprehensive_benchmark(
        X_wrist=X_wrist,
        X_ankle=X_ankle,
        y=y,
        groups=groups,
        output_dir=out_p,
        num_epochs=args.epochs,
    )

    # Baseline Random Forest check
    print("\n[Phase 2] Evaluating Baseline Random Forest with Handcrafted Features...")
    unique_labels = sorted(list(set(y)))
    label_to_idx = {l: i for i, l in enumerate(unique_labels)}
    y_int = np.array([label_to_idx[l] for l in y])

    rf = BaselineHARClassifier(n_estimators=100, random_state=42)
    split_point = int(len(y) * 0.75)
    rf.fit(X_wrist[:split_point], X_ankle[:split_point], y_int[:split_point])
    rf_preds = rf.predict(X_wrist[split_point:], X_ankle[split_point:])
    rf_acc = np.mean(rf_preds == y_int[split_point:])
    print(f"  -> Baseline Random Forest Accuracy: {rf_acc * 100:.2f}%")

    # ── PHASE 4: Edge Deployment & Mobile Inference ──
    print(f"\n[Phase 4] Training full production X-ConvTrans model for mobile export...")
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    num_classes = len(unique_labels)
    prod_model = XConvTrans(num_classes=num_classes, embed_dim=32).to(device)
    optimizer = torch.optim.AdamW(prod_model.parameters(), lr=1e-3, weight_decay=1e-4)
    criterion = torch.nn.CrossEntropyLoss()

    # Quick final fit on all data
    t_xw = torch.tensor(X_wrist.transpose(0, 2, 1), dtype=torch.float32).to(device)
    t_xa = torch.tensor(X_ankle.transpose(0, 2, 1), dtype=torch.float32).to(device)
    t_y = torch.tensor(y_int, dtype=torch.long).to(device)

    dataset = torch.utils.data.TensorDataset(t_xw, t_xa, t_y)
    loader = torch.utils.data.DataLoader(dataset, batch_size=32, shuffle=True)

    prod_model.train()
    for ep in range(max(args.epochs, 10)):
        for xw, xa, y_b in loader:
            optimizer.zero_grad()
            out = prod_model(xw, xa)
            loss = criterion(out, y_b)
            loss.backward()
            optimizer.step()

    prod_model.eval().to("cpu")
    print(f"  -> Production X-ConvTrans model parameters: {prod_model.total_parameters}")

    exporter = MobileModelExporter(prod_model, num_classes=num_classes, window_size=100)
    onnx_path = out_p / "x_convtrans.onnx"
    exporter.export_to_onnx(onnx_path)
    exporter.export_metadata_json(unique_labels, out_p / "model_metadata.json")

    # Verify real-time streaming FIFO buffer with temporal hysteresis
    print("\n[Phase 4] Testing real-time mobile streaming engine (100-sample FIFO, stride=25)...")
    def live_infer(w_window: np.ndarray, a_window: np.ndarray):
        with torch.no_grad():
            inp_w = torch.tensor(w_window.T, dtype=torch.float32).unsqueeze(0)
            inp_a = torch.tensor(a_window.T, dtype=torch.float32).unsqueeze(0)
            logits = prod_model(inp_w, inp_a)
            probs = torch.softmax(logits, dim=-1).numpy()[0]
            pred_idx = int(np.argmax(probs))
            return pred_idx, float(probs[pred_idx])

    streaming_engine = StreamingDualBandHARBuffer(
        class_labels=unique_labels,
        inference_callback=live_infer,
        window_size=100,
        stride_samples=25,
        history_size=3,
    )

    # Feed 150 simulated samples (expect 3 inference events: at sample 100, 125, 150)
    events = []
    for s_idx in range(150):
        # Simulate active walking sample
        w_s = [0.2, 0.4, 9.8 + np.sin(s_idx * 0.2), 0.1, 1.5, 0.0]
        a_s = [0.1, 0.0, 9.9 + 3.0 * np.sin(s_idx * 0.4), 0.0, 2.5, 0.0]
        res = streaming_engine.add_sample_pair(w_s, a_s)
        if res:
            events.append((s_idx + 1, res))

    print(f"  -> Processed 150 incoming BLE sample pairs.")
    print(f"  -> Triggered {len(events)} streaming inference updates (every 625 ms):")
    for s_num, res in events:
        print(f"     Sample #{s_num:3d} -> Activity: {res['activity']:15s} (Confidence: {res['confidence']*100:.1f}%) [Smoothed]")

    print("\n" + "=" * 75)
    print("PIPELINE EXECUTION COMPLETE")
    print(f"Artifacts saved in: {out_p.resolve()}")
    print("=" * 75)


if __name__ == "__main__":
    main()
