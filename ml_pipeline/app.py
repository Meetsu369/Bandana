"""
BANDANA: Dual-Band IMU Human Activity Recognition (HAR)
Streamlit Training, Evaluation, and On-Device Mobile Deployment Studio
Wrapper redirecting to root train_ui.py
"""

import sys
from pathlib import Path

# Add project root to sys.path
root_dir = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(root_dir))

from train_ui import main

if __name__ == "__main__":
    main()
