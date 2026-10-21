"""
Synthetic Biomechanical Dual-IMU Dataset Generator.

Generates realistic 40 Hz dual-band (wrist + ankle) sensor data for:
- Walking (natural reciprocal arm swing + step impacts)
- Pushing Cart / Stroller (stepping legs + stationary hands holding bar)
- Desk Typing (active hands + stationary feet)
- Cycling (smooth circular pedaling cadence + fixed grip)
- Running (high-impact vertical shocks + vigorous arm pump)
- Jumping Jacks (in-phase synchronized arm-leg abduction)
- Jump Rope (rapid bi-podal bouncing + circular wrist rotation)

Follows BANDANA CSV Schema Version 2 format.
"""

from __future__ import annotations

import math
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import numpy as np
import pandas as pd


class SyntheticDualBandGenerator:
    """Generates authentic dual-wearable IMU time-series for benchmark evaluation."""

    ACTIVITIES = [
        "Walking",
        "Cart Pushing",
        "Desk Typing",
        "Cycling",
        "Running",
        "Jumping Jacks",
        "Jump Rope",
    ]

    def __init__(self, sampling_rate_hz: float = 40.0, random_seed: int = 42):
        self.sampling_rate_hz = sampling_rate_hz
        self.period_ms = 1000.0 / sampling_rate_hz
        self.rng = np.random.default_rng(random_seed)

    def generate_session(
        self,
        session_id: int,
        participant_id: str,
        activity: str,
        duration_sec: float = 30.0,
        add_jitter_and_bursts: bool = True,
    ) -> pd.DataFrame:
        """
        Synthesizes a realistic dual-band session dataframe with biomechanical kinetics.
        """
        num_samples = int(duration_sec * self.sampling_rate_hz)
        t = np.arange(num_samples) / self.sampling_rate_hz  # seconds
        t_ms = (t * 1000.0).astype(int)

        # Base gravity vector (approx 9.81 m/s^2 along Z or Y depending on limb orientation)
        w_ax, w_ay, w_az = np.zeros(num_samples), np.zeros(num_samples), np.full(num_samples, 9.81)
        w_gx, w_gy, w_gz = np.zeros(num_samples), np.zeros(num_samples), np.zeros(num_samples)

        a_ax, a_ay, a_az = np.zeros(num_samples), np.zeros(num_samples), np.full(num_samples, 9.81)
        a_gx, a_gy, a_gz = np.zeros(num_samples), np.zeros(num_samples), np.zeros(num_samples)

        noise_w = self.rng.normal(0, 0.15, (num_samples, 6))
        noise_a = self.rng.normal(0, 0.15, (num_samples, 6))

        if activity == "Walking":
            # Ankle: 1.8 Hz stepping impacts, strong pitch gyro
            step_freq = 1.8
            a_az += 3.5 * np.sin(2 * np.pi * step_freq * t) + 2.0 * np.maximum(0, np.sin(2 * np.pi * step_freq * t))**4
            a_ax += 1.2 * np.cos(2 * np.pi * step_freq * t)
            a_gy += 2.8 * np.sin(2 * np.pi * step_freq * t)

            # Wrist: 0.9 Hz reciprocal arm swing (half step frequency per limb)
            swing_freq = step_freq / 2.0
            w_ax += 1.8 * np.sin(2 * np.pi * swing_freq * t + np.pi / 4)
            w_ay += 0.8 * np.cos(2 * np.pi * swing_freq * t)
            w_gy += 1.5 * np.cos(2 * np.pi * swing_freq * t)

        elif activity == "Cart Pushing":
            # Ankle: Identical walking step impacts (1.8 Hz)
            step_freq = 1.8
            a_az += 3.5 * np.sin(2 * np.pi * step_freq * t) + 2.0 * np.maximum(0, np.sin(2 * np.pi * step_freq * t))**4
            a_ax += 1.2 * np.cos(2 * np.pi * step_freq * t)
            a_gy += 2.8 * np.sin(2 * np.pi * step_freq * t)

            # Wrist: Fixed on handlebar, NO arm swing, but high-frequency rolling vibrations
            rolling_vib = 0.6 * np.sin(2 * np.pi * 14.0 * t) + 0.4 * np.sin(2 * np.pi * 22.0 * t)
            w_az += rolling_vib
            w_ax += 0.2 * rolling_vib
            w_gy += 0.1 * np.sin(2 * np.pi * 1.8 * t)  # slight torso sway only

        elif activity == "Desk Typing":
            # Ankle: Static on floor (zero dynamics, only gravity + sensor noise)
            pass

            # Wrist: High-frequency small stochastic key strikes & finger motions
            key_events = self.rng.choice([0, 1], size=num_samples, p=[0.75, 0.25])
            w_az += key_events * self.rng.normal(1.2, 0.4, size=num_samples)
            w_gx += 0.5 * np.sin(2 * np.pi * 4.5 * t) * key_events
            w_gy += 0.7 * np.cos(2 * np.pi * 3.8 * t) * key_events

        elif activity == "Cycling":
            # Ankle: Smooth circular cadence at 1.4 Hz (high sinusoidal angular velocity, low sharp vertical impact)
            pedal_freq = 1.4
            a_ay += 4.2 * np.sin(2 * np.pi * pedal_freq * t)
            a_az += 3.8 * np.cos(2 * np.pi * pedal_freq * t)
            a_gx += 4.5 * np.sin(2 * np.pi * pedal_freq * t)

            # Wrist: Fixed handlebar grip with road vibration
            w_az += 0.4 * np.sin(2 * np.pi * 12.0 * t)
            w_ax += 0.3 * np.cos(2 * np.pi * 12.0 * t)

        elif activity == "Running":
            # Ankle: High-impact foot strikes (>4-6g) at 2.8 Hz cadence
            run_freq = 2.8
            a_az += 7.0 * np.maximum(0, np.sin(2 * np.pi * run_freq * t))**3
            a_ax += 3.5 * np.cos(2 * np.pi * run_freq * t)
            a_gy += 5.5 * np.sin(2 * np.pi * run_freq * t)

            # Wrist: Vigorous coordinated arm pump at 1.4 Hz
            pump_freq = run_freq / 2.0
            w_ax += 4.5 * np.sin(2 * np.pi * pump_freq * t)
            w_az += 3.0 * np.cos(2 * np.pi * pump_freq * t)
            w_gy += 3.8 * np.sin(2 * np.pi * pump_freq * t)

        elif activity == "Jumping Jacks":
            # Symmetrical arm/leg abduction at 1.2 Hz
            jack_freq = 1.2
            a_az += 5.0 * np.maximum(0, np.sin(2 * np.pi * jack_freq * t))**2
            a_ax += 3.0 * np.sin(2 * np.pi * jack_freq * t)
            w_az += 6.0 * np.sin(2 * np.pi * jack_freq * t)
            w_ax += 4.5 * np.cos(2 * np.pi * jack_freq * t)
            w_gz += 4.0 * np.sin(2 * np.pi * jack_freq * t)

        elif activity == "Jump Rope":
            # Ankle: Rapid vertical bouncing (2.2 Hz)
            hop_freq = 2.2
            a_az += 6.5 * np.maximum(0, np.sin(2 * np.pi * hop_freq * t))**3
            # Wrist: Rapid circular wrist revolutions to turn the rope (2.2 Hz high gyro)
            w_gx += 6.0 * np.sin(2 * np.pi * hop_freq * t)
            w_gy += 6.0 * np.cos(2 * np.pi * hop_freq * t)
            w_az += 1.5 * np.sin(2 * np.pi * hop_freq * t)

        # Add noise
        w_ax += noise_w[:, 0]
        w_ay += noise_w[:, 1]
        w_az += noise_w[:, 2]
        w_gx += noise_w[:, 3]
        w_gy += noise_w[:, 4]
        w_gz += noise_w[:, 5]

        a_ax += noise_a[:, 0]
        a_ay += noise_a[:, 1]
        a_az += noise_a[:, 2]
        a_gx += noise_a[:, 3]
        a_gy += noise_a[:, 4]
        a_gz += noise_a[:, 5]

        # Calculate magnitudes
        w_acc_mag = np.sqrt(w_ax**2 + w_ay**2 + w_az**2)
        w_gyr_mag = np.sqrt(w_gx**2 + w_gy**2 + w_gz**2)
        a_acc_mag = np.sqrt(a_ax**2 + a_ay**2 + a_az**2)
        a_gyr_mag = np.sqrt(a_gx**2 + a_gy**2 + a_gz**2)

        # Build interleaved rows
        rows = []
        for i in range(num_samples):
            # Wrist row
            w_jitter = self.rng.integers(-3, 4) if add_jitter_and_bursts else 0
            rows.append({
                "sessionId": session_id,
                "participantId": participant_id,
                "activity": activity,
                "bandRole": "wrist",
                "captureTimestampMs": int(t_ms[i] + w_jitter),
                "receiveTimestamp": f"2026-10-16T10:00:{t[i]:06.3f}Z",
                "deviceId": "AA:BB:CC:DD:EE:01",
                "deviceName": "BANDANA-WRIST",
                "ax": float(w_ax[i]),
                "ay": float(w_ay[i]),
                "az": float(w_az[i]),
                "gx": float(w_gx[i]),
                "gy": float(w_gy[i]),
                "gz": float(w_gz[i]),
                "accelMag": float(w_acc_mag[i]),
                "gyroMag": float(w_gyr_mag[i]),
            })
            # Ankle row (simulating slight BLE transmission interleaving delay)
            a_jitter = self.rng.integers(-4, 5) if add_jitter_and_bursts else 0
            rows.append({
                "sessionId": session_id,
                "participantId": participant_id,
                "activity": activity,
                "bandRole": "ankle",
                "captureTimestampMs": int(t_ms[i] + 5 + a_jitter),
                "receiveTimestamp": f"2026-10-16T10:00:{t[i]+0.005:06.3f}Z",
                "deviceId": "AA:BB:CC:DD:EE:02",
                "deviceName": "BANDANA-ANKLE",
                "ax": float(a_ax[i]),
                "ay": float(a_ay[i]),
                "az": float(a_az[i]),
                "gx": float(a_gx[i]),
                "gy": float(a_gy[i]),
                "gz": float(a_gz[i]),
                "accelMag": float(a_acc_mag[i]),
                "gyroMag": float(a_gyr_mag[i]),
            })

        df = pd.DataFrame(rows)
        return df

    def generate_full_benchmark_dataset(
        self,
        output_dir: Union[str, Path],
        num_participants: int = 4,
        session_duration_sec: float = 20.0,
    ) -> List[Path]:
        """
        Generates benchmark CSV files across multiple participants and all target activities.
        """
        out_p = Path(output_dir)
        out_p.mkdir(parents=True, exist_ok=True)
        created_files = []

        session_counter = 101
        for p_idx in range(1, num_participants + 1):
            part_id = f"participant_{p_idx}"
            for act in self.ACTIVITIES:
                df = self.generate_session(
                    session_id=session_counter,
                    participant_id=part_id,
                    activity=act,
                    duration_sec=session_duration_sec,
                )
                filename = f"{part_id}_{act.lower().replace(' ', '_')}_{session_counter}.csv"
                file_path = out_p / filename

                with open(file_path, "w", encoding="utf-8") as f:
                    f.write("# BANDANA IMU Session Export\n")
                    f.write("# Schema Version: 2\n")
                    f.write(f"# Session ID: {session_counter}\n")
                    f.write(f"# Participant ID: {part_id}\n")
                    f.write(f"# Activity: {act}\n")
                    f.write("# Start Time: 2026-10-16T10:00:00.000Z\n")
                    df.to_csv(f, index=False)

                created_files.append(file_path)
                session_counter += 1

        print(f"[Generator] Created {len(created_files)} benchmark CSV sessions in {out_p}")
        return created_files
