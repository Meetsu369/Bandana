import os
import glob
import time
import json
import numpy as np
import pandas as pd
from scipy.signal import butter, lfilter
from sklearn.model_selection import train_test_split, GroupKFold
from sklearn.metrics import classification_report, f1_score, accuracy_score, confusion_matrix
from sklearn.ensemble import RandomForestClassifier
from sklearn.neighbors import KNeighborsClassifier
from sklearn.preprocessing import StandardScaler
import tensorflow as tf

CANONICAL_ACTIVITIES = ["Sitting", "Standing_HandMove", "Walking", "Jumping"]
RAW_CHANNELS_12 = [
    "wrist_ax", "wrist_ay", "wrist_az",
    "wrist_gx", "wrist_gy", "wrist_gz",
    "ankle_ax", "ankle_ay", "ankle_az",
    "ankle_gx", "ankle_gy", "ankle_gz"
]

SCALE_16 = np.array([
    4.0, 4.0, 4.0, 250.0, 250.0, 250.0,  # wrist raw
    4.0, 4.0, 4.0, 250.0, 250.0, 250.0,  # ankle raw
    4.0, 250.0, 4.0, 250.0               # w_amag, w_gmag, a_amag, a_gmag
], dtype=np.float32)

def normalize_activity_label(label: str) -> str:
    if not isinstance(label, str):
        return ""
    clean = label.strip().lower().replace("_", " ")
    if "stand" in clean and ("hand" in clean or "move" in clean):
        return "Standing_HandMove"
    elif "jump" in clean:
        return "Jumping"
    elif "walk" in clean:
        return "Walking"
    elif "sit" in clean or "rest" in clean:
        return "Sitting"
    return label.strip()

def parse_session_csv(file_path: str):
    header_act = None
    header_part = None
    with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
        for _ in range(15):
            line = f.readline()
            if not line:
                break
            line_str = line.strip()
            if line_str.startswith("#"):
                low = line_str.lower()
                if "activity:" in low or "activity :" in low:
                    header_act = line_str.split(":", 1)[1].strip()
                if "participant:" in low or "participant :" in low:
                    header_part = line_str.split(":", 1)[1].strip()

    df = pd.read_csv(file_path, comment="#")
    df.columns = [c.strip().lower() for c in df.columns]

    csv_act = None
    if 'activity' in df.columns:
        valid_acts = df['activity'].dropna().astype(str).str.strip()
        if not valid_acts.empty:
            csv_act = valid_acts.iloc[0]

    final_act = header_act or csv_act or "Unknown"
    norm_act = normalize_activity_label(final_act)
    if norm_act in ["Unknown", ""]:
        fname = os.path.basename(file_path).lower()
        if "sit" in fname: norm_act = "Sitting"
        elif "stand" in fname: norm_act = "Standing_HandMove"
        elif "walk" in fname: norm_act = "Walking"
        elif "jump" in fname: norm_act = "Jumping"

    participant = header_part or os.path.basename(file_path).split("_")[0].lower()
    return df, norm_act, participant

def butterworth_filter(data: np.ndarray, cutoff_hz: float = 15.0, fs: float = 50.0, order: int = 4) -> np.ndarray:
    nyq = 0.5 * fs
    normal_cutoff = cutoff_hz / nyq
    b, a = butter(order, normal_cutoff, btype='low', analog=False)
    filtered = np.zeros_like(data)
    for ch in range(data.shape[1]):
        filtered[:, ch] = lfilter(b, a, data[:, ch])
    return filtered

def extract_features_144(X_windows: np.ndarray) -> np.ndarray:
    """Vectorized statistical & frequency feature extraction (16 channels x 9 metrics = 144 features)."""
    N, T, C = X_windows.shape
    mean = np.mean(X_windows, axis=1)
    std = np.std(X_windows, axis=1)
    var = np.var(X_windows, axis=1)
    ptp = np.ptp(X_windows, axis=1)
    rms = np.sqrt(np.mean(X_windows**2, axis=1))
    iqr = np.percentile(X_windows, 75, axis=1) - np.percentile(X_windows, 25, axis=1)

    med = np.median(X_windows, axis=1, keepdims=True)
    mad = np.median(np.abs(X_windows - med), axis=1)

    signs = np.sign(X_windows)
    diffs = np.abs(np.diff(signs, axis=1))
    zcr = np.sum(diffs > 0, axis=1) / (2.0 * (T - 1))

    centered = X_windows - np.mean(X_windows, axis=1, keepdims=True)
    fft_vals = np.abs(np.fft.rfft(centered, axis=1))[:, 1:, :]  # skip DC
    freqs = np.fft.rfftfreq(T, d=1.0/50.0)[1:]
    max_indices = np.argmax(fft_vals, axis=1)
    dom_freq = freqs[max_indices]

    stacked = np.stack([mean, std, var, ptp, mad, rms, iqr, zcr, dom_freq], axis=2)
    return stacked.reshape(N, C * 9).astype(np.float32)

def build_1d_cnn(input_shape=(100, 16), num_classes=4):
    inp = tf.keras.layers.Input(shape=input_shape, name="imu_16ch_input")
    x = tf.keras.layers.Conv1D(32, kernel_size=5, padding='same', activation='relu')(inp)
    x = tf.keras.layers.BatchNormalization()(x)
    x = tf.keras.layers.MaxPool1D(pool_size=2)(x)  # (50, 32)

    x = tf.keras.layers.Conv1D(64, kernel_size=5, padding='same', activation='relu')(x)
    x = tf.keras.layers.BatchNormalization()(x)
    x = tf.keras.layers.MaxPool1D(pool_size=2)(x)  # (25, 64)

    x = tf.keras.layers.GlobalAveragePooling1D()(x)
    x = tf.keras.layers.Dense(32, activation='relu')(x)
    x = tf.keras.layers.Dropout(0.3)(x)
    out = tf.keras.layers.Dense(num_classes, activation='softmax', name="activity_output")(x)
    return tf.keras.models.Model(inputs=inp, outputs=out, name="DualBand_1D_CNN_16Ch")

def build_conv_gru(input_shape=(100, 16), num_classes=4):
    inp = tf.keras.layers.Input(shape=input_shape, name="imu_16ch_input")
    x = tf.keras.layers.Conv1D(32, kernel_size=3, padding='same', activation='relu')(inp)
    x = tf.keras.layers.MaxPool1D(pool_size=2)(x)  # (50, 32)

    x = tf.keras.layers.GRU(32, return_sequences=False, unroll=True)(x)
    x = tf.keras.layers.Dropout(0.3)(x)
    out = tf.keras.layers.Dense(num_classes, activation='softmax', name="activity_output")(x)
    return tf.keras.models.Model(inputs=inp, outputs=out, name="DualBand_Conv_GRU_16Ch")

def export_to_tflite(model, output_path: str) -> int:
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]
    tflite_blob = converter.convert()
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "wb") as f:
        f.write(tflite_blob)
    return len(tflite_blob)

def export_rf_to_json(rf_model, output_path: str):
    """Exports Random Forest decision trees into compact JSON for edge evaluation."""
    forest_data = []
    for estimator in rf_model.estimators_:
        tree = estimator.tree_
        tree_dict = {
            "children_left": tree.children_left.tolist(),
            "children_right": tree.children_right.tolist(),
            "feature": tree.feature.tolist(),
            "threshold": tree.threshold.tolist(),
            "value": tree.value.tolist()
        }
        forest_data.append(tree_dict)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(forest_data, f)
    return os.path.getsize(output_path)

def export_knn_centroids(knn_model, scaler, class_names, output_path: str):
    """Exports KNN class centroids and scaling parameters for fast mobile metric evaluation."""
    X_train = knn_model._fit_X
    y_train = knn_model._y
    centroids = {}
    for idx, cname in enumerate(class_names):
        mask = (y_train == idx)
        centroids[cname] = np.mean(X_train[mask], axis=0).tolist()
    data = {
        "mean": scaler.mean_.tolist(),
        "scale": scaler.scale_.tolist(),
        "centroids": centroids
    }
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    return os.path.getsize(output_path)

def main():
    print("=" * 80)
    print("BANDANA DUAL-BAND HAR: ORIENTATION-INVARIANT MULTI-MODEL BENCHMARK ENGINE")
    print("=" * 80)

    csv_files = sorted(glob.glob("data/raw_sessions/*.csv"))
    print(f"Discovered {len(csv_files)} participant session CSVs in data/raw_sessions/")

    label_map = {name: idx for idx, name in enumerate(CANONICAL_ACTIVITIES)}
    X_list, y_list, group_list = [], [], []

    class_counts = {act: 0 for act in CANONICAL_ACTIVITIES}
    participant_set = set()

    for fpath in csv_files:
        df, act, part = parse_session_csv(fpath)
        if act not in label_map:
            print(f"Skipping {fpath}: Unknown activity '{act}'")
            continue
        missing = [c for c in RAW_CHANNELS_12 if c not in df.columns]
        if missing:
            print(f"Skipping {fpath}: Missing channels {missing}")
            continue

        participant_set.add(part)
        raw12 = df[RAW_CHANNELS_12].values.astype(np.float32)

        # ── 4 Invariant Magnitude Channels ──
        # Wrist Accel Mag & Gyro Mag
        w_amag = np.sqrt(raw12[:, 0]**2 + raw12[:, 1]**2 + raw12[:, 2]**2)[:, None]
        w_gmag = np.sqrt(raw12[:, 3]**2 + raw12[:, 4]**2 + raw12[:, 5]**2)[:, None]
        # Ankle Accel Mag & Gyro Mag
        a_amag = np.sqrt(raw12[:, 6]**2 + raw12[:, 7]**2 + raw12[:, 8]**2)[:, None]
        a_gmag = np.sqrt(raw12[:, 9]**2 + raw12[:, 10]**2 + raw12[:, 11]**2)[:, None]

        # 16-channel array: [12 raw, 4 invariant magnitudes]
        data16 = np.hstack([raw12, w_amag, w_gmag, a_amag, a_gmag])

        # Apply 15 Hz 4th-order Butterworth low-pass filter
        filtered16 = butterworth_filter(data16, cutoff_hz=15.0, fs=50.0)

        # Apply physical scaling
        scaled16 = filtered16 / SCALE_16

        # Segment into sliding windows (100 samples = 2.0s, stride 50 = 1.0s)
        window_size = 100
        stride = 50
        n_samples = len(scaled16)
        act_idx = label_map[act]

        extracted = 0
        for start in range(0, n_samples - window_size + 1, stride):
            window = scaled16[start:start + window_size]
            X_list.append(window)
            y_list.append(act_idx)
            group_list.append(part)
            extracted += 1

        class_counts[act] += extracted

    X = np.array(X_list, dtype=np.float32)
    y = np.array(y_list, dtype=np.int32)
    groups = np.array(group_list)

    print(f"\nExtracted total {len(X)} windows across {len(participant_set)} participants:")
    for act, count in class_counts.items():
        print(f"  * {act} (Class {label_map[act]}): {count} windows")

    print("\nExtracting 144-d Statistical & FFT Feature Vectors for Tabular Models...")
    t_feat0 = time.time()
    X_feats_144 = extract_features_144(X)
    print(f"Extracted {X_feats_144.shape} feature matrix in {time.time() - t_feat0:.2f}s.")

    # Stratified Train/Test Split (80% Train, 20% Test)
    idx_train, idx_test = train_test_split(
        np.arange(len(X)), test_size=0.20, random_state=42, stratify=y
    )

    X_train_seq, X_test_seq = X[idx_train], X[idx_test]
    y_train, y_test = y[idx_train], y[idx_test]

    X_train_f, X_test_f = X_feats_144[idx_train], X_feats_144[idx_test]

    scaler = StandardScaler()
    X_train_f_norm = scaler.fit_transform(X_train_f)
    X_test_f_norm = scaler.transform(X_test_f)

    print(f"Train set: {len(X_train_seq)} windows | Test set: {len(X_test_seq)} windows.")

    benchmark_results = []
    models_dir = "assets/models"
    os.makedirs(models_dir, exist_ok=True)

    # =========================================================================
    # MODEL 1: 1D-CNN (Temporal Conv - 16 Channels)
    # =========================================================================
    print("\n" + "=" * 60)
    print("TRAINING MODEL 1/5: 1D-CNN (Temporal Conv - 16 Channels)")
    print("=" * 60)
    cnn_model = build_1d_cnn(input_shape=(100, 16), num_classes=4)
    cnn_model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=0.001),
        loss='sparse_categorical_crossentropy',
        metrics=['accuracy']
    )
    cnn_model.fit(
        X_train_seq, y_train,
        validation_data=(X_test_seq, y_test),
        epochs=30,
        batch_size=32,
        verbose=1
    )

    t0 = time.time()
    cnn_probs = cnn_model.predict(X_test_seq, verbose=0)
    cnn_lat = ((time.time() - t0) / len(X_test_seq)) * 1000.0
    cnn_preds = np.argmax(cnn_probs, axis=1)

    cnn_train_acc = accuracy_score(y_train, np.argmax(cnn_model.predict(X_train_seq, verbose=0), axis=1)) * 100.0
    cnn_test_acc = accuracy_score(y_test, cnn_preds) * 100.0
    cnn_macro_f1 = f1_score(y_test, cnn_preds, average='macro') * 100.0
    cnn_f1_classes = f1_score(y_test, cnn_preds, average=None) * 100.0

    print("\n[EVALUATION MATRIX: 1D-CNN (Temporal Conv)]")
    print(classification_report(y_test, cnn_preds, target_names=CANONICAL_ACTIVITIES, zero_division=0))
    print("Confusion Matrix:\n", confusion_matrix(y_test, cnn_preds))

    cnn_tflite_path = os.path.join(models_dir, "model_1d_cnn.tflite")
    cnn_size_kb = export_to_tflite(cnn_model, cnn_tflite_path) / 1024.0
    # Also save dual_band_model.tflite for seamless compatibility
    export_to_tflite(cnn_model, os.path.join(models_dir, "dual_band_model.tflite"))

    benchmark_results.append({
        "name": "1D-CNN (Temporal Conv)",
        "train_acc": cnn_train_acc,
        "test_acc": cnn_test_acc,
        "macro_f1": cnn_macro_f1,
        "f1_sitting": cnn_f1_classes[0],
        "f1_standing": cnn_f1_classes[1],
        "f1_walking": cnn_f1_classes[2],
        "f1_jumping": cnn_f1_classes[3],
        "latency_ms": cnn_lat,
        "size_kb": cnn_size_kb
    })

    # =========================================================================
    # MODEL 2: Conv1D-GRU (Spatial-Temporal Recurrent)
    # =========================================================================
    print("\n" + "=" * 60)
    print("TRAINING MODEL 2/5: Conv1D-GRU (Spatial-Temporal Recurrent)")
    print("=" * 60)
    gru_model = build_conv_gru(input_shape=(100, 16), num_classes=4)
    gru_model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=0.001),
        loss='sparse_categorical_crossentropy',
        metrics=['accuracy']
    )
    gru_model.fit(
        X_train_seq, y_train,
        validation_data=(X_test_seq, y_test),
        epochs=30,
        batch_size=32,
        verbose=1
    )

    t0 = time.time()
    gru_probs = gru_model.predict(X_test_seq, verbose=0)
    gru_lat = ((time.time() - t0) / len(X_test_seq)) * 1000.0
    gru_preds = np.argmax(gru_probs, axis=1)

    gru_train_acc = accuracy_score(y_train, np.argmax(gru_model.predict(X_train_seq, verbose=0), axis=1)) * 100.0
    gru_test_acc = accuracy_score(y_test, gru_preds) * 100.0
    gru_macro_f1 = f1_score(y_test, gru_preds, average='macro') * 100.0
    gru_f1_classes = f1_score(y_test, gru_preds, average=None) * 100.0

    print("\n[EVALUATION MATRIX: Conv1D-GRU (Spatial-Temporal)]")
    print(classification_report(y_test, gru_preds, target_names=CANONICAL_ACTIVITIES, zero_division=0))
    print("Confusion Matrix:\n", confusion_matrix(y_test, gru_preds))

    gru_tflite_path = os.path.join(models_dir, "model_conv_gru.tflite")
    gru_size_kb = export_to_tflite(gru_model, gru_tflite_path) / 1024.0

    benchmark_results.append({
        "name": "Conv1D-GRU (Recurrent)",
        "train_acc": gru_train_acc,
        "test_acc": gru_test_acc,
        "macro_f1": gru_macro_f1,
        "f1_sitting": gru_f1_classes[0],
        "f1_standing": gru_f1_classes[1],
        "f1_walking": gru_f1_classes[2],
        "f1_jumping": gru_f1_classes[3],
        "latency_ms": gru_lat,
        "size_kb": gru_size_kb
    })

    # =========================================================================
    # MODEL 3: Logistic Regression (Multinomial Softmax on 144 Features)
    # =========================================================================
    print("\n" + "=" * 60)
    print("TRAINING MODEL 3/5: Logistic Regression (Multinomial Softmax)")
    print("=" * 60)
    # Train via Keras with folded scaling so the exported TFLite directly accepts raw 144-d features!
    logreg_keras = tf.keras.Sequential([
        tf.keras.layers.Input(shape=(144,), name="features_144_raw"),
        tf.keras.layers.Dense(4, activation='softmax', name="softmax_output")
    ])
    logreg_keras.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=0.005),
        loss='sparse_categorical_crossentropy',
        metrics=['accuracy']
    )
    # Fit directly on normalized features first
    logreg_keras.fit(
        X_train_f_norm, y_train,
        validation_data=(X_test_f_norm, y_test),
        epochs=40,
        batch_size=32,
        verbose=1
    )

    # Fold StandardScaler (x - mean) / scale into the Dense layer weights!
    # Dense: y = W * x_norm + b = W * ((x - mean)/scale) + b = (W / scale) * x + (b - W * mean / scale)
    W_norm, b_norm = logreg_keras.layers[0].get_weights()
    W_folded = W_norm / scaler.scale_[:, None]
    b_folded = b_norm - np.sum(W_norm * (scaler.mean_ / scaler.scale_)[:, None], axis=0)

    # Create deployed model accepting raw 144 features
    logreg_deploy = tf.keras.Sequential([
        tf.keras.layers.Input(shape=(144,), name="features_144_raw"),
        tf.keras.layers.Dense(4, activation='softmax', name="softmax_output")
    ])
    logreg_deploy.layers[0].set_weights([W_folded, b_folded])

    t0 = time.time()
    lr_probs = logreg_deploy.predict(X_test_f, verbose=0)
    lr_lat = ((time.time() - t0) / len(X_test_f)) * 1000.0
    lr_preds = np.argmax(lr_probs, axis=1)

    lr_train_acc = accuracy_score(y_train, np.argmax(logreg_deploy.predict(X_train_f, verbose=0), axis=1)) * 100.0
    lr_test_acc = accuracy_score(y_test, lr_preds) * 100.0
    lr_macro_f1 = f1_score(y_test, lr_preds, average='macro') * 100.0
    lr_f1_classes = f1_score(y_test, lr_preds, average=None) * 100.0

    lr_tflite_path = os.path.join(models_dir, "model_logistic_regression.tflite")
    lr_size_kb = export_to_tflite(logreg_deploy, lr_tflite_path) / 1024.0

    benchmark_results.append({
        "name": "Logistic Regression (Linear)",
        "train_acc": lr_train_acc,
        "test_acc": lr_test_acc,
        "macro_f1": lr_macro_f1,
        "f1_sitting": lr_f1_classes[0],
        "f1_standing": lr_f1_classes[1],
        "f1_walking": lr_f1_classes[2],
        "f1_jumping": lr_f1_classes[3],
        "latency_ms": lr_lat,
        "size_kb": lr_size_kb
    })

    # =========================================================================
    # MODEL 4: Random Forest (100 Trees, Depth 12)
    # =========================================================================
    print("\n" + "=" * 60)
    print("TRAINING MODEL 4/5: Random Forest (100 Trees, max_depth=12)")
    print("=" * 60)
    rf = RandomForestClassifier(n_estimators=100, max_depth=12, random_state=42, n_jobs=-1)
    rf.fit(X_train_f, y_train)

    t0 = time.time()
    rf_preds = rf.predict(X_test_f)
    rf_lat = ((time.time() - t0) / len(X_test_f)) * 1000.0

    rf_train_acc = accuracy_score(y_train, rf.predict(X_train_f)) * 100.0
    rf_test_acc = accuracy_score(y_test, rf_preds) * 100.0
    rf_macro_f1 = f1_score(y_test, rf_preds, average='macro') * 100.0
    rf_f1_classes = f1_score(y_test, rf_preds, average=None) * 100.0

    rf_json_path = os.path.join(models_dir, "random_forest.json")
    rf_size_kb = export_rf_to_json(rf, rf_json_path) / 1024.0

    benchmark_results.append({
        "name": "Random Forest (Ensemble)",
        "train_acc": rf_train_acc,
        "test_acc": rf_test_acc,
        "macro_f1": rf_macro_f1,
        "f1_sitting": rf_f1_classes[0],
        "f1_standing": rf_f1_classes[1],
        "f1_walking": rf_f1_classes[2],
        "f1_jumping": rf_f1_classes[3],
        "latency_ms": rf_lat,
        "size_kb": rf_size_kb
    })

    # =========================================================================
    # MODEL 5: K-Nearest Neighbors (k=5, Distance Weighted)
    # =========================================================================
    print("\n" + "=" * 60)
    print("TRAINING MODEL 5/5: K-Nearest Neighbors (k=5)")
    print("=" * 60)
    knn = KNeighborsClassifier(n_neighbors=5, weights='distance')
    knn.fit(X_train_f_norm, y_train)

    t0 = time.time()
    knn_preds = knn.predict(X_test_f_norm)
    knn_lat = ((time.time() - t0) / len(X_test_f_norm)) * 1000.0

    knn_train_acc = accuracy_score(y_train, knn.predict(X_train_f_norm)) * 100.0
    knn_test_acc = accuracy_score(y_test, knn_preds) * 100.0
    knn_macro_f1 = f1_score(y_test, knn_preds, average='macro') * 100.0
    knn_f1_classes = f1_score(y_test, knn_preds, average=None) * 100.0

    knn_json_path = os.path.join(models_dir, "knn_centroids.json")
    knn_size_kb = export_knn_centroids(knn, scaler, CANONICAL_ACTIVITIES, knn_json_path) / 1024.0

    benchmark_results.append({
        "name": "K-Nearest Neighbors (KNN)",
        "train_acc": knn_train_acc,
        "test_acc": knn_test_acc,
        "macro_f1": knn_macro_f1,
        "f1_sitting": knn_f1_classes[0],
        "f1_standing": knn_f1_classes[1],
        "f1_walking": knn_f1_classes[2],
        "f1_jumping": knn_f1_classes[3],
        "latency_ms": knn_lat,
        "size_kb": knn_size_kb
    })

    # =========================================================================
    # MULTI-MODEL ENSEMBLE (Soft-Voting: 1D-CNN + Conv1D-GRU + Logistic Regression)
    # =========================================================================
    ens_probs = (cnn_probs + gru_probs + lr_probs) / 3.0
    ens_preds = np.argmax(ens_probs, axis=1)

    ens_train_probs = (
        cnn_model.predict(X_train_seq, verbose=0) +
        gru_model.predict(X_train_seq, verbose=0) +
        logreg_deploy.predict(X_train_f, verbose=0)
    ) / 3.0
    ens_train_acc = accuracy_score(y_train, np.argmax(ens_train_probs, axis=1)) * 100.0
    ens_test_acc = accuracy_score(y_test, ens_preds) * 100.0
    ens_macro_f1 = f1_score(y_test, ens_preds, average='macro') * 100.0
    ens_f1_classes = f1_score(y_test, ens_preds, average=None) * 100.0
    ens_lat = cnn_lat + gru_lat + lr_lat

    print("\n[EVALUATION MATRIX: Multi-Model Ensemble (Soft-Voting)]")
    print(classification_report(y_test, ens_preds, target_names=CANONICAL_ACTIVITIES, zero_division=0))
    print("Confusion Matrix:\n", confusion_matrix(y_test, ens_preds))

    benchmark_results.append({
        "name": "Soft-Voting Ensemble (CNN+GRU+LR)",
        "train_acc": ens_train_acc,
        "test_acc": ens_test_acc,
        "macro_f1": ens_macro_f1,
        "f1_sitting": ens_f1_classes[0],
        "f1_standing": ens_f1_classes[1],
        "f1_walking": ens_f1_classes[2],
        "f1_jumping": ens_f1_classes[3],
        "latency_ms": ens_lat,
        "size_kb": cnn_size_kb + gru_size_kb + lr_size_kb
    })

    # Write labels
    labels_path = os.path.join(models_dir, "labels.txt")
    with open(labels_path, "w", encoding="utf-8") as f:
        for act in CANONICAL_ACTIVITIES:
            f.write(f"{act}\n")

    # =========================================================================
    # PUBLICATION-GRADE COMPARISON TABLE
    # =========================================================================
    print("\n" + "=" * 100)
    print("PUBLICATION-GRADE MODEL COMPARISON BENCHMARK (16-CHANNEL ORIENTATION-INVARIANT PIPELINE)")
    print("=" * 100)

    header = "| Model Architecture | Train Acc (%) | Test Acc (%) | Macro F1 (%) | Sitting F1 | Standing F1 | Walking F1 | Jumping F1 | Latency (ms) | Size (KB) |"
    separator = "| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |"
    print(header)
    print(separator)

    for r in benchmark_results:
        row = (
            f"| **{r['name']}** "
            f"| {r['train_acc']:.2f}% "
            f"| **{r['test_acc']:.2f}%** "
            f"| **{r['macro_f1']:.2f}%** "
            f"| {r['f1_sitting']:.1f}% "
            f"| {r['f1_standing']:.1f}% "
            f"| {r['f1_walking']:.1f}% "
            f"| {r['f1_jumping']:.1f}% "
            f"| {r['latency_ms']:.2f} ms "
            f"| {r['size_kb']:.1f} KB |"
        )
        print(row)
    print("=" * 100)

    # Save benchmark table to markdown file
    with open("benchmark_results/model_comparison.md", "w", encoding="utf-8") as f:
        f.write("# Model Comparison Benchmark (16-Channel Invariant Dual-Band HAR)\n\n")
        f.write(header + "\n" + separator + "\n")
        for r in benchmark_results:
            row = (
                f"| **{r['name']}** "
                f"| {r['train_acc']:.2f}% "
                f"| **{r['test_acc']:.2f}%** "
                f"| **{r['macro_f1']:.2f}%** "
                f"| {r['f1_sitting']:.1f}% "
                f"| {r['f1_standing']:.1f}% "
                f"| {r['f1_walking']:.1f}% "
                f"| {r['f1_jumping']:.1f}% "
                f"| {r['latency_ms']:.2f} ms "
                f"| {r['size_kb']:.1f} KB |\n"
            )
            f.write(row)
    print("Saved benchmark report to benchmark_results/model_comparison.md")

if __name__ == "__main__":
    main()
