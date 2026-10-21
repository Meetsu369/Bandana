"""
BANDANA: Dual-Band IMU Human Activity Recognition (HAR)
Streamlit Training, Evaluation, and On-Device Mobile Deployment Studio
"""

import os
import glob
import time
import io
from pathlib import Path
from typing import Dict, List, Tuple, Optional

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from scipy import signal
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, confusion_matrix, f1_score, accuracy_score
from sklearn.ensemble import RandomForestClassifier

import streamlit as st

# Set Streamlit Page Configuration
st.set_page_config(
    page_title="BANDANA ML Studio | Dual-Band HAR",
    page_icon="⚡",
    layout="wide",
    initial_sidebar_state="expanded",
)

# Custom High-Tech Styling
st.markdown("""
<style>
    .main-title {
        font-size: 2.2rem;
        font-weight: 800;
        background: linear-gradient(90deg, #00F0FF, #00FFA3);
        -webkit-background-clip: text;
        -webkit-text-fill-color: transparent;
        margin-bottom: 0.2rem;
    }
    .sub-title {
        color: #94A3B8;
        font-size: 1.05rem;
        margin-bottom: 1.5rem;
    }
    .metric-card {
        background-color: #1E293B;
        border-radius: 10px;
        padding: 18px;
        border: 1px solid #334155;
        box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
        text-align: center;
    }
    .stButton>button {
        border-radius: 8px;
        font-weight: 600;
        transition: all 0.2s ease-in-out;
    }
</style>
""", unsafe_allow_html=True)

# Canonical 12 IMU Channels
CHANNELS_12 = [
    'wrist_ax', 'wrist_ay', 'wrist_az', 'wrist_gx', 'wrist_gy', 'wrist_gz',
    'ankle_ax', 'ankle_ay', 'ankle_az', 'ankle_gx', 'ankle_gy', 'ankle_gz'
]

CANONICAL_ACTIVITIES = ["Sitting", "Standing_HandMove", "Walking", "Jumping"]

# Activity mapping dictionary to normalize synonyms from synthetic or collection variations
ACTIVITY_SYNONYMS = {
    "sitting": "Sitting",
    "sit": "Sitting",
    "seated": "Sitting",
    "resting": "Sitting",
    "chair": "Sitting",
    "standing_handmove": "Standing_HandMove",
    "standing handmove": "Standing_HandMove",
    "standing_hand_move": "Standing_HandMove",
    "standing hand move": "Standing_HandMove",
    "standing_hand_movement": "Standing_HandMove",
    "standing hand movement": "Standing_HandMove",
    "standinghandmove": "Standing_HandMove",
    "standinghandmovement": "Standing_HandMove",
    "desk typing": "Standing_HandMove",
    "desk_typing": "Standing_HandMove",
    "typing": "Standing_HandMove",
    "cart pushing": "Standing_HandMove",
    "cart_pushing": "Standing_HandMove",
    "standing": "Standing_HandMove",
    "handmove": "Standing_HandMove",
    "hand move": "Standing_HandMove",
    "hand movement": "Standing_HandMove",
    "hand_movement": "Standing_HandMove",
    "walking": "Walking",
    "walk": "Walking",
    "running": "Walking",
    "run": "Walking",
    "cycling": "Walking",
    "cycle": "Walking",
    "jogging": "Walking",
    "jog": "Walking",
    "jumping": "Jumping",
    "jumping_jacks": "Jumping",
    "jumping jacks": "Jumping",
    "jumping_jack": "Jumping",
    "jumping jack": "Jumping",
    "jumpingjacks": "Jumping",
    "jumpingjack": "Jumping",
    "jump rope": "Jumping",
    "jump_rope": "Jumping",
    "jumprope": "Jumping",
    "jump": "Jumping",
    "skipping": "Jumping",
}


def normalize_activity_label(label: str) -> str:
    """Normalize label strings to handle spaces, underscores, and case."""
    if not isinstance(label, str):
        return ""
    clean = label.strip().lower().replace("_", " ")
    # Map common variations to canonical target names
    if "stand" in clean and ("hand" in clean or "move" in clean):
        return "Standing_HandMove"
    elif "jump" in clean:
        return "Jumping"
    elif "walk" in clean or "run" in clean or "cycl" in clean:
        return "Walking"
    elif "sit" in clean or "rest" in clean:
        return "Sitting"
    elif "stand" in clean:
        return "Standing_HandMove"
    return label.strip()


# ============================================================================
# 1. SIGNAL PROCESSING & CSV DATA PIPELINE
# ============================================================================

def butterworth_filter(data: np.ndarray, cutoff_hz: float = 15.0, fs: float = 50.0, order: int = 4) -> np.ndarray:
    """Applies a 4th-order zero-phase low-pass Butterworth filter."""
    nyquist = 0.5 * fs
    normal_cutoff = min(cutoff_hz / nyquist, 0.99)
    b, a = signal.butter(order, normal_cutoff, btype='low', analog=False)
    if len(data) <= 3 * max(len(a), len(b)):
        return data
    return signal.filtfilt(b, a, data, axis=0)


def parse_session_csv(file_source, default_activity: str = "Unknown") -> Tuple[pd.DataFrame, str]:
    """
    Parses a session CSV file supporting:
    1. Schema A: Standardized Synchronized 16-column layout.
    2. Schema B: Row-interleaved dual-band log (bandRole = wrist / ankle).
    3. File header comment parsing (# Activity: ...).
    """
    detected_activity = default_activity

    if isinstance(file_source, (str, Path)):
        with open(file_source, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
        filename = Path(file_source).name
    else:
        # UploadedFile in Streamlit
        content = file_source.getvalue().decode('utf-8', errors='ignore')
        lines = content.splitlines()
        filename = getattr(file_source, 'name', 'uploaded.csv')

    # Parse metadata header comments
    clean_lines = []
    for line in lines:
        if line.startswith('#'):
            lower_line = line.lower()
            if 'activity:' in lower_line:
                parts = line.split(':', 1)
                if len(parts) > 1:
                    raw_act = parts[1].strip()
                    detected_activity = normalize_activity_label(raw_act)
        else:
            clean_lines.append(line)

    if not clean_lines:
        return pd.DataFrame(), detected_activity

    df = pd.read_csv(io.StringIO("\n".join(clean_lines)))

    # Fallback activity detection from filename if still unknown
    if detected_activity == "Unknown":
        detected_activity = normalize_activity_label(filename)

    # Determine schema
    cols = [c.strip().lower() for c in df.columns]
    df.columns = cols

    # Case 1: Synchronized Dual-Band CSV
    has_wrist = any('wrist_ax' in c for c in cols)
    has_ankle = any('ankle_ax' in c for c in cols)

    if has_wrist and has_ankle:
        # Check if activity column is inside table
        if 'activity' in df.columns:
            non_empty_acts = df['activity'].dropna()
            if not non_empty_acts.empty:
                act_val = str(non_empty_acts.iloc[0]).strip()
                detected_activity = normalize_activity_label(act_val)
        
        # Clean missing values & interpolate
        for ch in CHANNELS_12:
            if ch not in df.columns:
                df[ch] = 0.0
        df[CHANNELS_12] = df[CHANNELS_12].interpolate(method='linear').bfill().ffill()
        df['canonical_activity'] = detected_activity
        return df, detected_activity

    # Case 2: Row-interleaved (bandRole: wrist / ankle)
    if 'bandrole' in cols and 'ax' in cols and 'az' in cols:
        if 'activity' in df.columns:
            non_empty_acts = df['activity'].dropna()
            if not non_empty_acts.empty:
                act_val = str(non_empty_acts.iloc[0]).strip()
                detected_activity = normalize_activity_label(act_val)

        wrist_rows = df[df['bandrole'].str.lower() == 'wrist'].copy().reset_index(drop=True)
        ankle_rows = df[df['bandrole'].str.lower() == 'ankle'].copy().reset_index(drop=True)

        min_len = min(len(wrist_rows), len(ankle_rows))
        if min_len < 10:
            return pd.DataFrame(), detected_activity

        wrist_rows = wrist_rows.iloc[:min_len]
        ankle_rows = ankle_rows.iloc[:min_len]

        synced = pd.DataFrame()
        synced['wrist_ax'] = wrist_rows['ax'].values
        synced['wrist_ay'] = wrist_rows['ay'].values
        synced['wrist_az'] = wrist_rows['az'].values
        synced['wrist_gx'] = wrist_rows['gx'].values
        synced['wrist_gy'] = wrist_rows['gy'].values
        synced['wrist_gz'] = wrist_rows['gz'].values

        synced['ankle_ax'] = ankle_rows['ax'].values
        synced['ankle_ay'] = ankle_rows['ay'].values
        synced['ankle_az'] = ankle_rows['az'].values
        synced['ankle_gx'] = ankle_rows['gx'].values
        synced['ankle_gy'] = ankle_rows['gy'].values
        synced['ankle_gz'] = ankle_rows['gz'].values

        synced[CHANNELS_12] = synced[CHANNELS_12].interpolate(method='linear').bfill().ffill()
        synced['canonical_activity'] = detected_activity
        return synced, detected_activity

    return pd.DataFrame(), detected_activity


def generate_synthetic_trial_dataset(output_dir: str = "data/raw_sessions") -> List[str]:
    """Generates synthetic 50 Hz sessions for all 4 canonical activities for rapid testing."""
    os.makedirs(output_dir, exist_ok=True)
    created_files = []
    
    fs = 50.0
    duration_s = 25.0
    n_samples = int(fs * duration_s)
    t = np.linspace(0, duration_s, n_samples)

    specs = [
        ("Sitting", 0.05, 0.02, 0.1, 0.05, 9.81, 9.81),
        ("Standing_HandMove", 1.8, 0.03, 120.0, 0.2, 9.81, 9.81),
        ("Walking", 1.2, 3.5, 90.0, 140.0, 9.81, 9.81),
        ("Jumping", 4.2, 5.8, 220.0, 260.0, 9.81, 9.81),
    ]

    for participant in ["P01_Trial", "P02_Trial"]:
        for act, w_dyn, a_dyn, w_gyro, a_gyro, w_grav, a_grav in specs:
            df = pd.DataFrame()
            df['timestamp_phone_ms'] = (t * 1000).astype(int)
            df['sensor_tick_ms'] = (t * 1000).astype(int)
            df['seq'] = np.arange(n_samples) % 65536

            # Generate synthetic IMU signals
            freq = 1.6 if act in ["Walking", "Jumping", "Jumping_Jacks"] else (0.8 if act == "Standing_HandMove" else 0.05)
            
            df['wrist_ax'] = w_dyn * np.sin(2 * np.pi * freq * t) + np.random.normal(0, 0.05, n_samples)
            df['wrist_ay'] = w_dyn * np.cos(2 * np.pi * freq * t) + np.random.normal(0, 0.05, n_samples)
            df['wrist_az'] = w_grav + w_dyn * 0.5 * np.sin(4 * np.pi * freq * t) + np.random.normal(0, 0.05, n_samples)
            df['wrist_gx'] = w_gyro * np.sin(2 * np.pi * freq * t) + np.random.normal(0, 1.0, n_samples)
            df['wrist_gy'] = w_gyro * np.cos(2 * np.pi * freq * t) + np.random.normal(0, 1.0, n_samples)
            df['wrist_gz'] = w_gyro * 0.3 * np.sin(np.pi * freq * t) + np.random.normal(0, 1.0, n_samples)

            df['ankle_ax'] = a_dyn * 0.4 * np.sin(2 * np.pi * freq * t) + np.random.normal(0, 0.05, n_samples)
            df['ankle_ay'] = a_dyn * 0.8 * np.sin(2 * np.pi * freq * t) + np.random.normal(0, 0.05, n_samples)
            # Impact spikes for walking/jumping
            impact = (a_dyn * 2.0 * np.maximum(0, np.sin(2 * np.pi * freq * t))) if a_dyn > 0.5 else 0
            df['ankle_az'] = a_grav + impact + np.random.normal(0, 0.05, n_samples)
            df['ankle_gx'] = a_gyro * np.cos(2 * np.pi * freq * t) + np.random.normal(0, 1.0, n_samples)
            df['ankle_gy'] = a_gyro * np.sin(2 * np.pi * freq * t) + np.random.normal(0, 1.0, n_samples)
            df['ankle_gz'] = a_gyro * 0.2 * np.sin(np.pi * freq * t) + np.random.normal(0, 1.0, n_samples)
            df['activity'] = act

            filename = f"{participant}_{act.lower()}_synth.csv"
            fpath = os.path.join(output_dir, filename)
            
            with open(fpath, "w", encoding="utf-8") as f:
                f.write(f"# BANDANA IMU Session Export\n# Activity: {act}\n# Participant: {participant}\n")
                df.to_csv(f, index=False)
            created_files.append(fpath)

    return created_files


def extract_windows_from_dataframes(
    dfs_with_labels: List[Tuple[pd.DataFrame, str]],
    target_classes: List[str],
    window_size: int = 100,
    stride: int = 50,
    apply_filter: bool = True
) -> Tuple[np.ndarray, np.ndarray, Dict[str, int]]:
    """Segments session dataframes into fixed sliding windows."""
    label_map = {name: idx for idx, name in enumerate(target_classes)}
    X, y = [], []

    for df, act in dfs_with_labels:
        norm_act = normalize_activity_label(act)
        matched_idx = None
        for cls_name, idx in label_map.items():
            if cls_name == act or normalize_activity_label(cls_name) == norm_act:
                matched_idx = idx
                break
        if matched_idx is None:
            continue
        label_idx = matched_idx

        data = df[CHANNELS_12].values.astype(np.float32)
        if apply_filter:
            data = butterworth_filter(data, cutoff_hz=15.0, fs=50.0)

        # Physical scaling vector (accel in +/-4g range, gyro in +/-250 dps range)
        scale_vector = np.array([4.0, 4.0, 4.0, 250.0, 250.0, 250.0, 4.0, 4.0, 4.0, 250.0, 250.0, 250.0], dtype=np.float32)
        norm_data = data / scale_vector

        n_samples = len(norm_data)
        for start in range(0, n_samples - window_size + 1, stride):
            window = norm_data[start:start + window_size]
            X.append(window)
            y.append(label_idx)

    return np.array(X, dtype=np.float32), np.array(y, dtype=np.int32), label_map


def extract_rf_features(X_windows: np.ndarray) -> np.ndarray:
    """Extracts statistical and temporal features from windows for Random Forest baseline."""
    n_windows, window_size, n_channels = X_windows.shape
    features_list = []

    for i in range(n_windows):
        w = X_windows[i]  # (100, 12)
        feats = []
        for ch in range(n_channels):
            col = w[:, ch]
            feats.append(np.mean(col))
            feats.append(np.std(col))
            feats.append(np.sqrt(np.mean(col**2)))  # RMS
            feats.append(np.max(col))
            feats.append(np.min(col))
            feats.append(np.max(col) - np.min(col))  # Peak-to-peak
            # Zero-crossing rate
            zcr = ((col[:-1] * col[1:]) < 0).sum() / float(window_size)
            feats.append(zcr)

        # Cross-Limb correlations (wrist_ax with ankle_ax, etc.)
        for axis_offset in range(6):
            wrist_col = w[:, axis_offset]
            ankle_col = w[:, 6 + axis_offset]
            if np.std(wrist_col) > 1e-4 and np.std(ankle_col) > 1e-4:
                corr = np.corrcoef(wrist_col, ankle_col)[0, 1]
                feats.append(0.0 if np.isnan(corr) else corr)
            else:
                feats.append(0.0)

        features_list.append(feats)

    return np.array(features_list, dtype=np.float32)


# ============================================================================
# 2. NEURAL NETWORK ARCHITECTURES & TFLITE EXPORTER
# ============================================================================

def build_1d_cnn_model(input_shape: Tuple[int, int], num_classes: int):
    """Constructs Shallow 1D-CNN (~10.7k parameters)."""
    import tensorflow as tf
    from tensorflow.keras import layers, models

    inp = layers.Input(shape=input_shape, name="imu_input")
    x = layers.Conv1D(32, kernel_size=5, padding='same', activation='relu')(inp)
    x = layers.BatchNormalization()(x)
    x = layers.MaxPool1D(pool_size=2)(x)  # (50, 32)

    x = layers.Conv1D(64, kernel_size=3, padding='same', activation='relu')(x)
    x = layers.BatchNormalization()(x)
    x = layers.GlobalAveragePooling1D()(x)  # (64)

    x = layers.Dense(32, activation='relu')(x)
    x = layers.Dropout(0.3)(x)
    out = layers.Dense(num_classes, activation='softmax', name="activity_output")(x)

    return models.Model(inputs=inp, outputs=out, name="DualBand_1D_CNN")


def build_conv_gru_model(input_shape: Tuple[int, int], num_classes: int):
    """Constructs Conv1D-GRU Hybrid Spatial-Temporal Model (~18k parameters)."""
    import tensorflow as tf
    from tensorflow.keras import layers, models

    inp = layers.Input(shape=input_shape, name="imu_input")
    x = layers.Conv1D(32, kernel_size=5, padding='same', activation='relu')(inp)
    x = layers.BatchNormalization()(x)
    x = layers.MaxPool1D(pool_size=2)(x)  # (50, 32)

    x = layers.Conv1D(64, kernel_size=3, padding='same', activation='relu')(x)
    x = layers.BatchNormalization()(x)
    x = layers.MaxPool1D(pool_size=2)(x)  # (25, 64)

    x = layers.GRU(32, return_sequences=False)(x)
    x = layers.Dropout(0.3)(x)
    out = layers.Dense(num_classes, activation='softmax', name="activity_output")(x)

    return models.Model(inputs=inp, outputs=out, name="DualBand_Conv_GRU")


def convert_and_save_tflite(keras_model, output_path: str) -> bytes:
    """Converts a trained Keras model into FP16 Quantized TFLite binary."""
    import tensorflow as tf

    converter = tf.lite.TFLiteConverter.from_keras_model(keras_model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]
    tflite_blob = converter.convert()

    out_dir = os.path.dirname(output_path)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    with open(output_path, "wb") as f:
        f.write(tflite_blob)

    return tflite_blob


# ============================================================================
# 3. STREAMLIT APPLICATION UI
# ============================================================================

def main():
    st.markdown('<div class="main-title">BANDANA Dual-Band ML Studio</div>', unsafe_allow_html=True)
    st.markdown('<div class="sub-title">Train, Evaluate, and Deploy 50 Hz Wrist+Ankle Human Activity Recognition Models</div>', unsafe_allow_html=True)

    # ── SIDEBAR: DATA & MODEL CONFIGURATION ──
    with st.sidebar:
        st.header("⚙️ Data & Model Setup")

        # Session File Scanner & Selector
        st.subheader("1. Session Data Sources")
        search_dirs = ["data/raw_sessions", "data", "."]
        found_csvs = []
        for d in search_dirs:
            if os.path.exists(d):
                found_csvs.extend(glob.glob(os.path.join(d, "*.csv")))
        found_csvs = sorted(list(set(found_csvs)))

        selected_files = st.multiselect(
            "Select Session CSV Files",
            options=found_csvs,
            default=found_csvs if found_csvs else [],
            help="Select recorded trial CSVs from data/raw_sessions or upload new ones below."
        )

        uploaded_files = st.file_uploader(
            "Or Upload Session CSVs",
            type=["csv"],
            accept_multiple_files=True,
            help="Upload participant trial exports directly from the phone app."
        )

        if st.button("🧪 Generate 4-Class Synthetic Data"):
            synth_files = generate_synthetic_trial_dataset()
            st.success(f"Generated {len(synth_files)} synthetic session CSVs in data/raw_sessions!")
            st.rerun()

        # Architecture Selector
        st.subheader("2. Model Architecture")
        model_choice = st.selectbox(
            "Choose Algorithm",
            options=[
                "1D-CNN (Fast, Low Latency - ~10.7k params)",
                "Conv1D-GRU (Hybrid Spatial-Temporal - ~18k params)",
                "Random Forest Baseline (Handcrafted Features)"
            ],
            index=0
        )

        # Hyperparameters
        with st.expander("🛠️ Hyperparameters", expanded=False):
            window_size = st.number_input("Window Length (samples)", min_value=25, max_value=250, value=100, step=25, help="100 samples = 2.0s @ 50 Hz")
            stride = st.number_input("Stride / Step (samples)", min_value=10, max_value=100, value=50, step=10, help="50 samples = 50% overlap / 1.0s")
            epochs = st.slider("Training Epochs", min_value=5, max_value=50, value=30, step=5)
            batch_size = st.selectbox("Batch Size", options=[16, 32, 64], index=1)
            learning_rate = st.select_slider("Learning Rate", options=[1e-4, 5e-4, 1e-3, 2e-3], value=1e-3)
            apply_lpf = st.checkbox("Apply 15 Hz Butterworth Filter", value=True)

        # Target Activities
        st.subheader("3. Target Classes")
        available_classes = list(dict.fromkeys(CANONICAL_ACTIVITIES))
        for fp in selected_files:
            _, act = parse_session_csv(fp)
            norm_act = normalize_activity_label(act)
            if norm_act and norm_act != "Unknown" and norm_act not in available_classes:
                available_classes.append(norm_act)
        if uploaded_files:
            for uf in uploaded_files:
                _, act = parse_session_csv(uf)
                norm_act = normalize_activity_label(act)
                if norm_act and norm_act != "Unknown" and norm_act not in available_classes:
                    available_classes.append(norm_act)

        selected_classes = st.multiselect(
            "Activities to Classify",
            options=available_classes,
            default=[c for c in CANONICAL_ACTIVITIES if c in available_classes],
            help="Select activities to train on. 'Jumping' and 'Standing_HandMove' variations are automatically normalized."
        )

    # ── LOAD & PREPARE DATA ──
    all_sessions_data = []

    # Process selected disk files
    for fp in selected_files:
        df, act = parse_session_csv(fp)
        norm_act = normalize_activity_label(act)
        if not df.empty:
            matched_class = None
            for sc in selected_classes:
                if sc == act or normalize_activity_label(sc) == norm_act:
                    matched_class = sc
                    break
            if matched_class:
                all_sessions_data.append((df, matched_class, Path(fp).name))

    # Process uploaded files
    if uploaded_files:
        for uf in uploaded_files:
            df, act = parse_session_csv(uf)
            norm_act = normalize_activity_label(act)
            if not df.empty:
                matched_class = None
                for sc in selected_classes:
                    if sc == act or normalize_activity_label(sc) == norm_act:
                        matched_class = sc
                        break
                if matched_class:
                    all_sessions_data.append((df, matched_class, uf.name))

    # ── MAIN PANEL: EXPLORATION & VISUALIZATIONS ──
    if not all_sessions_data:
        st.warning("⚠️ No valid trial CSV files selected or uploaded. Select session files in the sidebar or click '🧪 Generate 4-Class Synthetic Data'.")
        return

    # Extract windows
    dfs_to_window = [(df, act) for df, act, _ in all_sessions_data]
    X, y, label_map = extract_windows_from_dataframes(
        dfs_to_window,
        target_classes=selected_classes,
        window_size=window_size,
        stride=stride,
        apply_filter=apply_lpf
    )

    tab_explore, tab_train, tab_deploy = st.tabs(["📊 Dataset Exploration", "🚀 Model Training & Evaluation", "📲 Mobile Deployment"])

    with tab_explore:
        col_dist, col_preview = st.columns([1, 2])

        with col_dist:
            st.subheader("Class Distribution")
            class_counts = {cls_name: int(np.sum(y == idx)) for cls_name, idx in label_map.items()}
            counts_df = pd.DataFrame(list(class_counts.items()), columns=["Activity", "Windows"])

            fig_bar, ax_bar = plt.subplots(figsize=(5, 3.5))
            sns.barplot(data=counts_df, x="Activity", y="Windows", palette="viridis", ax=ax_bar)
            ax_bar.set_xticklabels(ax_bar.get_xticklabels(), rotation=25, ha="right")
            ax_bar.set_title(f"Total Extracted Windows: {len(X)}")
            st.pyplot(fig_bar)

            # Imbalance check
            if len(class_counts) < len(selected_classes):
                st.error("🚨 Warning: Some selected classes have zero windows in this dataset!")
            elif max(class_counts.values()) > 3 * min(class_counts.values()):
                st.warning("⚠️ Note: Class imbalance detected (max class has >3x windows of min class).")
            else:
                st.success("✅ Dataset is well-balanced across selected classes.")

        with col_preview:
            st.subheader("Synchronized Kinematic Signal Preview")
            sample_session_name = st.selectbox("Select Session to Inspect", options=[name for _, _, name in all_sessions_data])
            selected_sample_df = next(df for df, _, name in all_sessions_data if name == sample_session_name)

            fig_sig, (ax_w, ax_a) = plt.subplots(2, 1, figsize=(9, 4.5), sharex=True)
            slice_len = min(250, len(selected_sample_df))  # 5 seconds @ 50 Hz
            t_axis = np.arange(slice_len) / 50.0

            ax_w.plot(t_axis, selected_sample_df['wrist_ax'].iloc[:slice_len], label='Wrist Ax (g)', color='#38BDF8')
            ax_w.plot(t_axis, selected_sample_df['wrist_ay'].iloc[:slice_len], label='Wrist Ay (g)', color='#818CF8')
            ax_w.plot(t_axis, selected_sample_df['wrist_az'].iloc[:slice_len], label='Wrist Az (g)', color='#C084FC')
            ax_w.set_ylabel("Wrist Accel (g)")
            ax_w.legend(loc='upper right', fontsize='small', ncol=3)
            ax_w.grid(True, linestyle='--', alpha=0.5)

            ax_a.plot(t_axis, selected_sample_df['ankle_ax'].iloc[:slice_len], label='Ankle Ax (g)', color='#34D399')
            ax_a.plot(t_axis, selected_sample_df['ankle_ay'].iloc[:slice_len], label='Ankle Ay (g)', color='#FBBF24')
            ax_a.plot(t_axis, selected_sample_df['ankle_az'].iloc[:slice_len], label='Ankle Az (g)', color='#F87171')
            ax_a.set_ylabel("Ankle Accel (g)")
            ax_a.set_xlabel("Time (seconds)")
            ax_a.legend(loc='upper right', fontsize='small', ncol=3)
            ax_a.grid(True, linestyle='--', alpha=0.5)

            st.pyplot(fig_sig)

    # ── TRAINING & EVALUATION TAB ──
    with tab_train:
        st.subheader("Model Training & Validation")

        if len(np.unique(y)) < 2:
            st.error("Cannot train with fewer than 2 distinct activity classes. Please add more classes or generate synthetic data.")
            return

        if st.button("🚀 Train & Evaluate Model", type="primary", use_container_width=True):
            with st.spinner("Splitting dataset and initializing model..."):
                # Stratified split 80% train / 20% test (safe check: each class must have >= 2 windows)
                unique_classes, class_counts = np.unique(y, return_counts=True)
                min_class_count = np.min(class_counts) if len(class_counts) > 0 else 0

                if min_class_count >= 2:
                    stratify_opt = y
                else:
                    stratify_opt = None
                    low_count_classes = [
                        selected_classes[cls_idx] for cls_idx, c in zip(unique_classes, class_counts) if c < 2
                    ]
                    st.warning(
                        f"⚠️ The following class(es) have fewer than 2 windows: {', '.join(low_count_classes)}. "
                        "Falling back to non-stratified random split."
                    )

                X_train, X_test, y_train, y_test = train_test_split(
                    X, y, test_size=0.2, random_state=42, stratify=stratify_opt
                )

                st.session_state["target_classes"] = selected_classes
                st.session_state["label_map"] = label_map

                if "Random Forest" in model_choice:
                    st.info("Extracting handcrafted statistical features for Random Forest...")
                    X_train_feats = extract_rf_features(X_train)
                    X_test_feats = extract_rf_features(X_test)

                    rf = RandomForestClassifier(n_estimators=100, random_state=42, n_jobs=-1)
                    t0 = time.time()
                    rf.fit(X_train_feats, y_train)
                    train_duration = time.time() - t0

                    t_inf0 = time.time()
                    y_pred = rf.predict(X_test_feats)
                    t_inf = ((time.time() - t_inf0) / len(X_test)) * 1000.0  # ms per window

                    acc = accuracy_score(y_test, y_pred) * 100.0
                    f1 = f1_score(y_test, y_pred, average='macro', zero_division=0) * 100.0

                    st.session_state["trained_model_type"] = "rf"
                    st.session_state["rf_model"] = rf
                    st.session_state["test_metrics"] = {
                        "accuracy": acc,
                        "f1": f1,
                        "latency_ms": t_inf,
                        "y_test": y_test,
                        "y_pred": y_pred,
                        "history": None
                    }

                else:
                    # Neural Models (1D-CNN or Conv1D-GRU)
                    import tensorflow as tf
                    from tensorflow.keras import callbacks

                    input_shape = (window_size, len(CHANNELS_12))
                    num_classes = len(selected_classes)

                    if "1D-CNN" in model_choice:
                        model = build_1d_cnn_model(input_shape, num_classes)
                    else:
                        model = build_conv_gru_model(input_shape, num_classes)

                    model.compile(
                        optimizer=tf.keras.optimizers.Adam(learning_rate=learning_rate),
                        loss='sparse_categorical_crossentropy',
                        metrics=['accuracy']
                    )

                    progress_bar = st.progress(0, text="Training Epochs Progress...")
                    
                    class StreamlitProgressCallback(callbacks.Callback):
                        def on_epoch_end(self, epoch, logs=None):
                            pct = int(((epoch + 1) / epochs) * 100)
                            loss = logs.get('loss', 0.0)
                            val_acc = logs.get('val_accuracy', 0.0)
                            progress_bar.progress(pct, text=f"Epoch {epoch+1}/{epochs} | Loss: {loss:.4f} | Val Acc: {val_acc*100:.1f}%")

                    early_stop = callbacks.EarlyStopping(monitor='val_loss', patience=6, restore_best_weights=True)
                    
                    history = model.fit(
                        X_train, y_train,
                        validation_data=(X_test, y_test),
                        epochs=epochs,
                        batch_size=batch_size,
                        callbacks=[StreamlitProgressCallback(), early_stop],
                        verbose=0
                    )
                    progress_bar.progress(100, text="Training Complete!")

                    # Benchmark Latency
                    t_inf0 = time.time()
                    y_pred_probs = model.predict(X_test, verbose=0)
                    t_inf = ((time.time() - t_inf0) / len(X_test)) * 1000.0  # ms per window
                    y_pred = np.argmax(y_pred_probs, axis=1)

                    acc = accuracy_score(y_test, y_pred) * 100.0
                    f1 = f1_score(y_test, y_pred, average='macro', zero_division=0) * 100.0

                    st.session_state["trained_model_type"] = "nn"
                    st.session_state["keras_model"] = model
                    st.session_state["test_metrics"] = {
                        "accuracy": acc,
                        "f1": f1,
                        "latency_ms": t_inf,
                        "y_test": y_test,
                        "y_pred": y_pred,
                        "history": history.history
                    }

        # Display Metrics & Plots if trained
        if "test_metrics" in st.session_state:
            metrics = st.session_state["test_metrics"]

            # KPI Cards Row
            m_col1, m_col2, m_col3, m_col4 = st.columns(4)
            with m_col1:
                st.metric("Test Accuracy", f"{metrics['accuracy']:.1f}%")
            with m_col2:
                st.metric("Macro F1-Score", f"{metrics['f1']:.1f}%")
            with m_col3:
                st.metric("Inference Latency", f"{metrics['latency_ms']:.2f} ms")
            with m_col4:
                est_size = "~22 KB" if st.session_state.get("trained_model_type") == "nn" else "N/A"
                st.metric("TFLite Model Size", est_size)

            st.divider()

            # Visualizations
            v_col1, v_col2 = st.columns([1, 1])
            target_names = st.session_state["target_classes"]
            num_target_classes = len(target_names)
            class_labels = list(range(num_target_classes))

            with v_col1:
                st.subheader("Confusion Matrix")
                cm = confusion_matrix(metrics['y_test'], metrics['y_pred'], labels=class_labels, normalize='true')
                cm = np.nan_to_num(cm)
                fig_cm, ax_cm = plt.subplots(figsize=(4.5, 3.8))
                sns.heatmap(
                    cm,
                    annot=True,
                    fmt=".1%",
                    cmap="Blues",
                    xticklabels=target_names,
                    yticklabels=target_names,
                    ax=ax_cm
                )
                ax_cm.set_ylabel("True Activity")
                ax_cm.set_xlabel("Predicted Activity")
                st.pyplot(fig_cm)

            with v_col2:
                st.subheader("Classification Report")
                report_dict = classification_report(
                    metrics['y_test'],
                    metrics['y_pred'],
                    labels=class_labels,
                    target_names=target_names,
                    zero_division=0,
                    output_dict=True
                )
                report_df = pd.DataFrame(report_dict).T.round(3)
                st.dataframe(report_df.style.highlight_max(axis=0, color="#1E3A8A"), use_container_width=True)

            # Training Curves for Neural Networks
            if metrics["history"] is not None:
                st.subheader("Epoch Learning Curves")
                hist = metrics["history"]
                fig_loss, (ax_l, ax_a) = plt.subplots(1, 2, figsize=(10, 3.2))

                ax_l.plot(hist['loss'], label='Train Loss', color='#38BDF8')
                ax_l.plot(hist['val_loss'], label='Val Loss', color='#F87171')
                ax_l.set_title("Cross-Entropy Loss")
                ax_l.set_xlabel("Epoch")
                ax_l.legend()
                ax_l.grid(True, linestyle='--', alpha=0.5)

                ax_a.plot(hist['accuracy'], label='Train Acc', color='#34D399')
                ax_a.plot(hist['val_accuracy'], label='Val Acc', color='#FBBF24')
                ax_a.set_title("Classification Accuracy")
                ax_a.set_xlabel("Epoch")
                ax_a.legend()
                ax_a.grid(True, linestyle='--', alpha=0.5)

                st.pyplot(fig_loss)

    # ── MOBILE DEPLOYMENT TAB ──
    with tab_deploy:
        st.subheader("📲 One-Click Mobile Deployment (Flutter App)")
        st.write(
            "Export the trained neural network as a Float16 quantized `.tflite` asset and copy it directly "
            "into the Flutter application assets directory (`Bandana/assets/models/`)."
        )

        app_models_dir = Path("assets/models")
        target_tflite_path = app_models_dir / "dual_band_model.tflite"
        target_labels_path = app_models_dir / "labels.txt"

        if st.session_state.get("trained_model_type") == "rf":
            st.warning("⚠️ The currently trained model is Random Forest Baseline. For mobile edge inference, please train a **1D-CNN** or **Conv1D-GRU** model to export as TFLite.")
        elif "keras_model" not in st.session_state:
            st.info("ℹ️ Train a neural network model in the 'Model Training & Evaluation' tab to enable mobile export.")
        else:
            if st.button("📲 Deploy to Flutter App (assets/models/dual_band_model.tflite)", type="primary"):
                with st.spinner("Quantizing model to Float16 TFLite and writing assets..."):
                    keras_model = st.session_state["keras_model"]
                    tflite_bytes = convert_and_save_tflite(keras_model, str(target_tflite_path))

                    # Update labels.txt
                    active_classes = st.session_state.get("target_classes", CANONICAL_ACTIVITIES)
                    with open(target_labels_path, "w", encoding="utf-8") as f:
                        for cls in active_classes:
                            f.write(f"{cls}\n")

                    size_kb = len(tflite_bytes) / 1024.0

                    st.balloons()
                    st.success(f"🎉 Successfully exported and deployed model!")
                    st.markdown(f"""
                    **Deployment Summary:**
                    - **Target File:** `{target_tflite_path}`
                    - **Quantization:** Float16 (Optimized for Arm Cortex & Hexagon DSP)
                    - **Binary Size:** `{size_kb:.2f} KB`
                    - **Labels File:** `{target_labels_path}` ({len(active_classes)} classes: {', '.join(active_classes)})
                    - **Next Step:** Re-launch or hot-restart the Flutter app. The `ClassifierService` will automatically detect the asset and switch from heuristic mode to active neural inference!
                    """)


if __name__ == "__main__":
    main()
