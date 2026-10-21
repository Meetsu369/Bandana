# Model Comparison Benchmark (16-Channel Invariant Dual-Band HAR)

| Model Architecture | Train Acc (%) | Test Acc (%) | Macro F1 (%) | Sitting F1 | Standing F1 | Walking F1 | Jumping F1 | Latency (ms) | Size (KB) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **1D-CNN (Temporal Conv)** | 99.92% | **100.00%** | **100.00%** | 100.0% | 100.0% | 100.0% | 100.0% | 0.67 ms | 41.4 KB |
| **Conv1D-GRU (Recurrent)** | 100.00% | **100.00%** | **100.00%** | 100.0% | 100.0% | 100.0% | 100.0% | 8.55 ms | 193.9 KB |
| **Logistic Regression (Linear)** | 100.00% | **100.00%** | **100.00%** | 100.0% | 100.0% | 100.0% | 100.0% | 0.25 ms | 2.9 KB |
| **Random Forest (Ensemble)** | 100.00% | **100.00%** | **100.00%** | 100.0% | 100.0% | 100.0% | 100.0% | 0.08 ms | 162.0 KB |
| **K-Nearest Neighbors (KNN)** | 100.00% | **100.00%** | **100.00%** | 100.0% | 100.0% | 100.0% | 100.0% | 0.18 ms | 23.0 KB |
| **Soft-Voting Ensemble (CNN+GRU+LR)** | 100.00% | **100.00%** | **100.00%** | 100.0% | 100.0% | 100.0% | 100.0% | 9.47 ms | 238.2 KB |
