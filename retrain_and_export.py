import os
import glob
import numpy as np
import pandas as pd
from scipy.signal import butter, lfilter
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, confusion_matrix
import tensorflow as tf

CANONICAL_ACTIVITIES = ["Sitting", "Standing_HandMove", "Walking", "Jumping"]
CHANNELS_12 = [
    "wrist_ax", "wrist_ay", "wrist_az",
    "wrist_gx", "wrist_gy", "wrist_gz",
    "ankle_ax", "ankle_ay", "ankle_az",
    "ankle_gx", "ankle_gy", "ankle_gz"
]
SCALE_VECTOR = np.array([4.0, 4.0, 4.0, 250.0, 250.0, 250.0, 4.0, 4.0, 4.0, 250.0, 250.0, 250.0], dtype=np.float32)

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

    return df, norm_act

def butterworth_filter(data: np.ndarray, cutoff_hz: float = 15.0, fs: float = 50.0, order: int = 4) -> np.ndarray:
    nyq = 0.5 * fs
    normal_cutoff = cutoff_hz / nyq
    b, a = butter(order, normal_cutoff, btype='low', analog=False)
    filtered = np.zeros_like(data)
    for ch in range(data.shape[1]):
        filtered[:, ch] = lfilter(b, a, data[:, ch])
    return filtered

def build_1d_cnn(input_shape=(100, 12), num_classes=4):
    inp = tf.keras.layers.Input(shape=input_shape, name="imu_input")
    x = tf.keras.layers.Conv1D(32, kernel_size=5, padding='same', activation='relu')(inp)
    x = tf.keras.layers.BatchNormalization()(x)
    x = tf.keras.layers.MaxPool1D(pool_size=2)(x)  # (50, 32)

    x = tf.keras.layers.Conv1D(64, kernel_size=3, padding='same', activation='relu')(x)
    x = tf.keras.layers.BatchNormalization()(x)
    x = tf.keras.layers.GlobalAveragePooling1D()(x)  # (64)

    x = tf.keras.layers.Dense(32, activation='relu')(x)
    x = tf.keras.layers.Dropout(0.3)(x)
    out = tf.keras.layers.Dense(num_classes, activation='softmax', name="activity_output")(x)

    return tf.keras.models.Model(inputs=inp, outputs=out, name="DualBand_1D_CNN")

def main():
    csv_files = sorted(glob.glob("data/raw_sessions/*.csv"))
    print(f"Found {len(csv_files)} CSV files in data/raw_sessions/")

    label_map = {name: idx for idx, name in enumerate(CANONICAL_ACTIVITIES)}
    X, y = [], []

    class_counts = {act: 0 for act in CANONICAL_ACTIVITIES}

    for fpath in csv_files:
        df, act = parse_session_csv(fpath)
        if act not in label_map:
            print(f"Skipping {fpath} with unmapped activity '{act}'")
            continue
        missing = [c for c in CHANNELS_12 if c not in df.columns]
        if missing:
            print(f"Missing channels in {fpath}: {missing}")
            continue
        
        data = df[CHANNELS_12].values.astype(np.float32)
        filtered = butterworth_filter(data, cutoff_hz=15.0, fs=50.0)
        scaled = filtered / SCALE_VECTOR

        window_size = 100
        stride = 50
        n_samples = len(scaled)
        act_idx = label_map[act]

        extracted = 0
        for start in range(0, n_samples - window_size + 1, stride):
            window = scaled[start:start + window_size]
            X.append(window)
            y.append(act_idx)
            extracted += 1
        
        class_counts[act] += extracted

    X = np.array(X, dtype=np.float32)
    y = np.array(y, dtype=np.int32)
    print(f"\nExtracted total {len(X)} windows:")
    for act, count in class_counts.items():
        print(f"  - {act} (Class {label_map[act]}): {count} windows")

    # Stratified Train/Test Split
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )
    print(f"\nSplit into {len(X_train)} train windows and {len(X_test)} test windows.")

    # Model training
    model = build_1d_cnn(input_shape=(100, 12), num_classes=4)
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=0.001),
        loss='sparse_categorical_crossentropy',
        metrics=['accuracy']
    )
    model.summary()

    print("\nStarting training for 30 epochs...")
    history = model.fit(
        X_train, y_train,
        validation_data=(X_test, y_test),
        epochs=30,
        batch_size=32,
        verbose=1
    )

    # Evaluate
    y_pred_probs = model.predict(X_test)
    y_pred = np.argmax(y_pred_probs, axis=1)

    print("\n" + "="*50)
    print("FINAL EVALUATION ON TEST SET")
    print("="*50)
    print(classification_report(y_test, y_pred, target_names=CANONICAL_ACTIVITIES, zero_division=0))
    print("Confusion Matrix:")
    print(confusion_matrix(y_test, y_pred))

    # TFLite Conversion (Float16)
    print("\nConverting model to FP16 TFLite...")
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]
    tflite_model = converter.convert()

    tflite_path = "assets/models/dual_band_model.tflite"
    os.makedirs(os.path.dirname(tflite_path), exist_ok=True)
    with open(tflite_path, "wb") as f:
        f.write(tflite_model)
    print(f"Successfully saved TFLite model to {tflite_path} ({len(tflite_model) / 1024:.2f} KB)")

    # Write labels
    labels_path = "assets/models/labels.txt"
    with open(labels_path, "w", encoding="utf-8") as f:
        for act in CANONICAL_ACTIVITIES:
            f.write(f"{act}\n")
    print(f"Successfully written labels to {labels_path}")

if __name__ == "__main__":
    main()
