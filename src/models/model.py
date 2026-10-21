"""
Dual-Stream Cross-Attention ConvNet (X-ConvTrans) Architecture for Dual-Wearable HAR.

Part of the BANDANA Human Activity Recognition Research Engine.
Architecture:
- Wrist Branch: 1D Multi-Scale Conv + Residual blocks with smaller kernels (3, 5)
  optimized for high-frequency micro-movements, gestural typing, and arm swinging.
- Ankle Branch: 1D Multi-Scale Conv + Residual blocks with wider kernels (5, 7)
  optimized for lower-frequency locomotor gait cadence, stepping impacts, and pedaling.
- Cross-Attention Fusion Layer: Asymmetric multi-head cross-attention mechanism
  modeling inter-limb spatiotemporal phase coordination.
- Classifier Head: Global Average Pooling -> Dense -> Softmax.
- Under 150k parameters for sub-10ms mobile edge execution.
"""

from __future__ import annotations

import math
from typing import Dict, List, Optional, Tuple

import torch
import torch.nn as nn
import torch.nn.functional as F


class Conv1DBlock(nn.Module):
    """Basic 1D Convolutional block with BatchNorm, GELU, and Dropout."""

    def __init__(
        self,
        in_channels: int,
        out_channels: int,
        kernel_size: int,
        stride: int = 1,
        padding: Optional[int] = None,
        dropout: float = 0.1,
    ):
        super().__init__()
        if padding is None:
            padding = kernel_size // 2
        self.conv = nn.Conv1d(
            in_channels,
            out_channels,
            kernel_size=kernel_size,
            stride=stride,
            padding=padding,
            bias=False,
        )
        self.bn = nn.BatchNorm1d(out_channels)
        self.act = nn.GELU()
        self.drop = nn.Dropout(dropout) if dropout > 0 else nn.Identity()

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.drop(self.act(self.bn(self.conv(x))))


class Residual1DBlock(nn.Module):
    """Residual 1D Conv block with dual convolutions and skip connection."""

    def __init__(
        self,
        channels: int,
        kernel_size: int,
        dropout: float = 0.1,
    ):
        super().__init__()
        self.conv1 = nn.Conv1d(
            channels,
            channels,
            kernel_size=kernel_size,
            padding=kernel_size // 2,
            bias=False,
        )
        self.bn1 = nn.BatchNorm1d(channels)
        self.act = nn.GELU()
        self.conv2 = nn.Conv1d(
            channels,
            channels,
            kernel_size=kernel_size,
            padding=kernel_size // 2,
            bias=False,
        )
        self.bn2 = nn.BatchNorm1d(channels)
        self.drop = nn.Dropout(dropout) if dropout > 0 else nn.Identity()

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        res = x
        out = self.act(self.bn1(self.conv1(x)))
        out = self.bn2(self.conv2(out))
        out = self.drop(out)
        return self.act(out + res)


class WristBranch(nn.Module):
    """
    Wrist Feature Extractor.
    Uses smaller kernels (3, 5) tuned for high-frequency hand/arm dynamics.
    Input: (B, 6, T) -> Output: (B, D, T_down)
    """

    def __init__(self, in_channels: int = 6, embed_dim: int = 32, dropout: float = 0.1):
        super().__init__()
        # Initial projection
        self.stem = Conv1DBlock(in_channels, embed_dim // 2, kernel_size=3, stride=1, dropout=dropout)
        # Downsample 1 (100 -> 50)
        self.down1 = Conv1DBlock(embed_dim // 2, embed_dim, kernel_size=3, stride=2, dropout=dropout)
        self.res1 = Residual1DBlock(embed_dim, kernel_size=3, dropout=dropout)
        # Downsample 2 (50 -> 25)
        self.down2 = Conv1DBlock(embed_dim, embed_dim, kernel_size=5, stride=2, dropout=dropout)
        self.res2 = Residual1DBlock(embed_dim, kernel_size=5, dropout=dropout)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # x: (B, 6, 100)
        x = self.stem(x)
        x = self.down1(x)
        x = self.res1(x)
        x = self.down2(x)
        x = self.res2(x)
        return x  # (B, 32, 25)


class AnkleBranch(nn.Module):
    """
    Ankle Feature Extractor.
    Uses wider kernels (5, 7) tuned for lower-frequency gait, impacts, and cadence.
    Input: (B, 6, T) -> Output: (B, D, T_down)
    """

    def __init__(self, in_channels: int = 6, embed_dim: int = 32, dropout: float = 0.1):
        super().__init__()
        # Initial projection with wider kernel
        self.stem = Conv1DBlock(in_channels, embed_dim // 2, kernel_size=5, stride=1, dropout=dropout)
        # Downsample 1 (100 -> 50)
        self.down1 = Conv1DBlock(embed_dim // 2, embed_dim, kernel_size=5, stride=2, dropout=dropout)
        self.res1 = Residual1DBlock(embed_dim, kernel_size=5, dropout=dropout)
        # Downsample 2 (50 -> 25)
        self.down2 = Conv1DBlock(embed_dim, embed_dim, kernel_size=7, stride=2, dropout=dropout)
        self.res2 = Residual1DBlock(embed_dim, kernel_size=7, dropout=dropout)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # x: (B, 6, 100)
        x = self.stem(x)
        x = self.down1(x)
        x = self.res1(x)
        x = self.down2(x)
        x = self.res2(x)
        return x  # (B, 32, 25)


class CrossAttentionFusion(nn.Module):
    """
    Bi-directional Asymmetric Cross-Attention Layer.
    Wrist queries Ankle: captures how hand motion synchronizes with leg strides.
    Ankle queries Wrist: captures how leg propulsion correlates with arm drive.
    """

    def __init__(self, embed_dim: int = 32, num_heads: int = 4, dropout: float = 0.1):
        super().__init__()
        self.embed_dim = embed_dim
        self.num_heads = num_heads

        self.wrist_to_ankle_attn = nn.MultiheadAttention(
            embed_dim=embed_dim,
            num_heads=num_heads,
            dropout=dropout,
            batch_first=True,
        )
        self.ankle_to_wrist_attn = nn.MultiheadAttention(
            embed_dim=embed_dim,
            num_heads=num_heads,
            dropout=dropout,
            batch_first=True,
        )

        self.norm_w = nn.LayerNorm(embed_dim)
        self.norm_a = nn.LayerNorm(embed_dim)

        # Feed-forward post attention
        self.mlp_w = nn.Sequential(
            nn.Linear(embed_dim, embed_dim * 2),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(embed_dim * 2, embed_dim),
        )
        self.mlp_a = nn.Sequential(
            nn.Linear(embed_dim, embed_dim * 2),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(embed_dim * 2, embed_dim),
        )
        self.norm_w2 = nn.LayerNorm(embed_dim)
        self.norm_a2 = nn.LayerNorm(embed_dim)

    def forward(
        self,
        f_wrist: torch.Tensor,
        f_ankle: torch.Tensor,
    ) -> Tuple[torch.Tensor, torch.Tensor]:
        # Input: (B, D, L) -> transpose to (B, L, D) for MultiheadAttention
        hw = f_wrist.transpose(1, 2)
        ha = f_ankle.transpose(1, 2)

        # Wrist queries Ankle: (query=w, key=a, value=a)
        w_cross, _ = self.wrist_to_ankle_attn(query=hw, key=ha, value=ha)
        hw = self.norm_w(hw + w_cross)
        hw = self.norm_w2(hw + self.mlp_w(hw))

        # Ankle queries Wrist: (query=a, key=w, value=w)
        a_cross, _ = self.ankle_to_wrist_attn(query=ha, key=hw, value=hw)
        ha = self.norm_a(ha + a_cross)
        ha = self.norm_a2(ha + self.mlp_a(ha))

        return hw.transpose(1, 2), ha.transpose(1, 2)


class XConvTrans(nn.Module):
    """
    Proposed Dual-Stream Cross-Attention ConvNet (X-ConvTrans).
    Full publication architecture satisfying sub-150k parameter budget.
    """

    def __init__(
        self,
        num_classes: int = 7,
        in_channels: int = 6,
        embed_dim: int = 32,
        num_heads: int = 4,
        dropout: float = 0.15,
    ):
        super().__init__()
        self.num_classes = num_classes
        self.embed_dim = embed_dim

        # Asymmetric limb encoders
        self.wrist_encoder = WristBranch(in_channels=in_channels, embed_dim=embed_dim, dropout=dropout)
        self.ankle_encoder = AnkleBranch(in_channels=in_channels, embed_dim=embed_dim, dropout=dropout)

        # Cross-attention fusion
        self.cross_attention = CrossAttentionFusion(embed_dim=embed_dim, num_heads=num_heads, dropout=dropout)

        # Joint limb representation
        fused_dim = embed_dim * 2
        self.fusion_conv = nn.Sequential(
            Conv1DBlock(fused_dim, fused_dim, kernel_size=3, dropout=dropout),
            Residual1DBlock(fused_dim, kernel_size=3, dropout=dropout),
        )

        # Global pooling and classification head
        self.gap = nn.AdaptiveAvgPool1d(1)
        self.classifier = nn.Sequential(
            nn.Linear(fused_dim, 64),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(64, num_classes),
        )

    def forward(self, x_wrist: torch.Tensor, x_ankle: torch.Tensor) -> torch.Tensor:
        """
        Forward pass.
        Args:
            x_wrist: (B, 6, 100) or (B, 100, 6)
            x_ankle: (B, 6, 100) or (B, 100, 6)
        Returns:
            logits: (B, num_classes)
        """
        # Ensure channels-first (B, 6, 100)
        if x_wrist.shape[1] != 6 and x_wrist.shape[2] == 6:
            x_wrist = x_wrist.transpose(1, 2)
        if x_ankle.shape[1] != 6 and x_ankle.shape[2] == 6:
            x_ankle = x_ankle.transpose(1, 2)

        # Extract asymmetric features
        f_w = self.wrist_encoder(x_wrist)  # (B, 48, 25)
        f_a = self.ankle_encoder(x_ankle)  # (B, 48, 25)

        # Cross-limb attention
        f_w_fused, f_a_fused = self.cross_attention(f_w, f_a)

        # Concatenate coordinated representations
        joint = torch.cat([f_w_fused, f_a_fused], dim=1)  # (B, 96, 25)
        joint = self.fusion_conv(joint)

        # Global average pooling
        pooled = self.gap(joint).squeeze(-1)  # (B, 96)

        # Logits
        logits = self.classifier(pooled)
        return logits

    @property
    def total_parameters(self) -> int:
        """Returns total number of trainable model parameters."""
        return sum(p.numel() for p in self.parameters() if p.requires_grad)


# ── Comparative Ablation Models for Scientific Paper ──

class WristOnlyConvNet(nn.Module):
    """Ablation: Wrist-only ConvNet classifier."""

    def __init__(self, num_classes: int = 7, in_channels: int = 6, embed_dim: int = 32, dropout: float = 0.15):
        super().__init__()
        self.encoder = WristBranch(in_channels=in_channels, embed_dim=embed_dim, dropout=dropout)
        self.gap = nn.AdaptiveAvgPool1d(1)
        self.classifier = nn.Sequential(
            nn.Linear(embed_dim, 64),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(64, num_classes),
        )

    def forward(self, x_wrist: torch.Tensor, x_ankle: Optional[torch.Tensor] = None) -> torch.Tensor:
        if x_wrist.shape[1] != 6 and x_wrist.shape[2] == 6:
            x_wrist = x_wrist.transpose(1, 2)
        f = self.encoder(x_wrist)
        pooled = self.gap(f).squeeze(-1)
        return self.classifier(pooled)


class AnkleOnlyConvNet(nn.Module):
    """Ablation: Ankle-only ConvNet classifier."""

    def __init__(self, num_classes: int = 7, in_channels: int = 6, embed_dim: int = 32, dropout: float = 0.15):
        super().__init__()
        self.encoder = AnkleBranch(in_channels=in_channels, embed_dim=embed_dim, dropout=dropout)
        self.gap = nn.AdaptiveAvgPool1d(1)
        self.classifier = nn.Sequential(
            nn.Linear(embed_dim, 64),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(64, num_classes),
        )

    def forward(self, x_wrist: Optional[torch.Tensor] = None, x_ankle: Optional[torch.Tensor] = None) -> torch.Tensor:
        inp = x_ankle if x_ankle is not None else x_wrist
        if inp.shape[1] != 6 and inp.shape[2] == 6:
            inp = inp.transpose(1, 2)
        f = self.encoder(inp)
        pooled = self.gap(f).squeeze(-1)
        return self.classifier(pooled)


class DualStreamEarlyFusion(nn.Module):
    """Ablation: Dual-stream early concatenation without cross-attention."""

    def __init__(self, num_classes: int = 7, in_channels: int = 6, embed_dim: int = 32, dropout: float = 0.15):
        super().__init__()
        self.wrist_encoder = WristBranch(in_channels=in_channels, embed_dim=embed_dim, dropout=dropout)
        self.ankle_encoder = AnkleBranch(in_channels=in_channels, embed_dim=embed_dim, dropout=dropout)
        fused_dim = embed_dim * 2
        self.fusion = nn.Sequential(
            Conv1DBlock(fused_dim, fused_dim, kernel_size=3, dropout=dropout),
            Residual1DBlock(fused_dim, kernel_size=3, dropout=dropout),
        )
        self.gap = nn.AdaptiveAvgPool1d(1)
        self.classifier = nn.Sequential(
            nn.Linear(fused_dim, 64),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(64, num_classes),
        )

    def forward(self, x_wrist: torch.Tensor, x_ankle: torch.Tensor) -> torch.Tensor:
        if x_wrist.shape[1] != 6 and x_wrist.shape[2] == 6:
            x_wrist = x_wrist.transpose(1, 2)
        if x_ankle.shape[1] != 6 and x_ankle.shape[2] == 6:
            x_ankle = x_ankle.transpose(1, 2)

        f_w = self.wrist_encoder(x_wrist)
        f_a = self.ankle_encoder(x_ankle)
        joint = torch.cat([f_w, f_a], dim=1)
        joint = self.fusion(joint)
        pooled = self.gap(joint).squeeze(-1)
        return self.classifier(pooled)
