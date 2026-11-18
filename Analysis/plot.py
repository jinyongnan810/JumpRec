#!/usr/bin/env python3
"""Generate acceleration and rotation visualization plots for motion CSV files."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.patches import Patch


AXIS_COLORS = {
    "X": "#FF6B6B",
    "Y": "#4ECDC4",
    "Z": "#F5D000",
}
PLOT_BG_COLOR = "#E5ECF6"
TITLE_COLOR = "#2A3F5F"
JUMP_LINE_COLOR = "#5DADE2"
DU_HIGHLIGHT_COLOR = "#FF8C00"


@dataclass(frozen=True)
class WatchDoubleUnderConfig:
    """Thresholds mirroring JumpDetector's Watch double-under confirmation logic."""

    min_interval: float = 0.16
    max_interval: float = 0.33
    first_turn_min_peak: float = 5.0
    first_turn_max_trough: float = -4.0
    min_peak_to_peak: float = 9.5
    second_turn_min_peak: float = 2.5


def infer_profile(stem: str) -> str:
    """Infers the JumpDetector profile name from a CSV filename stem."""
    return "watch" if stem.lower().startswith("watch") else "headphones"


def detect_motion_events(
    times: np.ndarray,
    az_values: np.ndarray,
    profile: str,
) -> tuple[list[float], list[tuple[float, float]]]:
    """Replays JumpDetector on AZ samples and returns jump times and Watch DU pairs."""
    is_watch = profile == "watch"
    threshold = 0.8 if is_watch else -1.2
    rearm_threshold = -0.1 if is_watch else 0.1
    minimum_interval = 0.1
    du_cfg = WatchDoubleUnderConfig()

    can_detect_next_jump = True
    last_accepted_ts: float | None = None
    jump_times: list[float] = []
    double_under_pairs: list[tuple[float, float]] = []

    has_tracked_turn = False
    active_turn_ts = 0.0
    active_turn_max = 0.0
    active_turn_min = 0.0
    active_turn_consumed = False
    pending_second_turn = False
    pending_first_turn_ts = 0.0

    for t, val in zip(times, az_values):
        t = float(t)
        val = float(val)

        if not can_detect_next_jump:
            if is_watch and has_tracked_turn and val > active_turn_max:
                active_turn_max = val
                if pending_second_turn and active_turn_max >= du_cfg.second_turn_min_peak:
                    double_under_pairs.append((pending_first_turn_ts, active_turn_ts))
                    pending_second_turn = False
                    active_turn_consumed = True

            rearmed = val <= rearm_threshold if is_watch else val >= rearm_threshold
            if not rearmed:
                continue
            can_detect_next_jump = True

        if is_watch and has_tracked_turn and val < active_turn_min:
            active_turn_min = val

        is_candidate = val > threshold if is_watch else val < threshold
        if not is_candidate:
            continue

        if last_accepted_ts is not None and (t - last_accepted_ts) < minimum_interval:
            continue

        can_detect_next_jump = False
        last_accepted_ts = t
        jump_times.append(t)

        if is_watch:
            should_pend = False
            first_ts = active_turn_ts
            if has_tracked_turn and not active_turn_consumed:
                interval = t - active_turn_ts
                peak_to_peak = active_turn_max - active_turn_min
                should_pend = (
                    du_cfg.min_interval <= interval <= du_cfg.max_interval
                    and active_turn_max >= du_cfg.first_turn_min_peak
                    and active_turn_min <= du_cfg.first_turn_max_trough
                    and peak_to_peak >= du_cfg.min_peak_to_peak
                )

            has_tracked_turn = True
            active_turn_ts = t
            active_turn_max = val
            active_turn_min = 0.0
            active_turn_consumed = False
            pending_second_turn = should_pend
            pending_first_turn_ts = first_ts

            if pending_second_turn and active_turn_max >= du_cfg.second_turn_min_peak:
                double_under_pairs.append((pending_first_turn_ts, active_turn_ts))
                pending_second_turn = False
                active_turn_consumed = True

    return jump_times, double_under_pairs


def choose_detail_window(
    times: np.ndarray,
    jump_times: list[float],
    double_under_pairs: list[tuple[float, float]],
    stem: str,
    window_seconds: float = 10.0,
) -> tuple[float, float]:
    """Selects a 10-second detail window highlighting double-unders or steady jumping."""
    t_min = float(times[0])
    t_max = float(times[-1])
    if t_max - t_min <= window_seconds:
        return t_min, t_max

    if double_under_pairs:
        best_count = -1
        best_center = (double_under_pairs[0][0] + double_under_pairs[0][1]) / 2.0
        for t_start, t_end in double_under_pairs:
            mid = (t_start + t_end) / 2.0
            w_start = max(t_min, min(t_max - window_seconds, mid - window_seconds / 2.0))
            w_end = w_start + window_seconds
            in_win = [
                (a + b) / 2.0
                for a, b in double_under_pairs
                if w_start + 0.4 <= a and b <= w_end - 0.4
            ]
            if len(in_win) > best_count:
                best_count = len(in_win)
                best_center = (min(in_win) + max(in_win)) / 2.0
        start = max(t_min, min(t_max - window_seconds, best_center - window_seconds / 2.0))
        return start, start + window_seconds

    if "doubleunder" in stem.lower() and len(jump_times) > 1:
        for i in range(1, len(jump_times)):
            if jump_times[i] - jump_times[i - 1] > 1.5:
                start = max(t_min, min(t_max - window_seconds, jump_times[i - 1] - 3.5))
                return start, start + window_seconds

    start = max(t_min, min(t_max - window_seconds, t_min + 10.0))
    return start, start + window_seconds


def style_axis(ax: plt.Axes, ylabel: str, title: str) -> None:
    """Applies consistent Plotly-inspired styling to a matplotlib axis."""
    ax.set_facecolor(PLOT_BG_COLOR)
    ax.axhline(0.0, color="white", linewidth=1.6, zorder=1)
    ax.grid(True, color="white", linewidth=0.9, zorder=0)
    for spine in ax.spines.values():
        spine.set_visible(False)
    ax.tick_params(colors=TITLE_COLOR, labelsize=10)
    ax.set_ylabel(ylabel, fontsize=11, color=TITLE_COLOR)
    ax.set_title(title, fontsize=12, fontweight="bold", color=TITLE_COLOR, loc="left", pad=8)


def plot_component_group(
    df: pd.DataFrame,
    stem: str,
    profile: str,
    jump_times: list[float],
    double_under_pairs: list[tuple[float, float]],
    detail_window: tuple[float, float],
    component_prefix: str,
    y_label: str,
    chart_title: str,
    output_path: Path,
) -> None:
    """Creates a two-panel (overview + 10s zoom) PNG for acceleration or rotation."""
    times = df["Time"].to_numpy()
    cols = [f"{component_prefix}{axis}" for axis in ("X", "Y", "Z")]
    w_start, w_end = detail_window
    detail_mask = (times >= w_start) & (times <= w_end)

    fig, (ax_full, ax_zoom) = plt.subplots(
        2,
        1,
        figsize=(16, 9),
        dpi=180,
        gridspec_kw={"height_ratios": [1.0, 1.1], "hspace": 0.34},
    )
    fig.patch.set_facecolor("white")

    du_label = (
        f"Double-Unders: {len(double_under_pairs)}"
        if profile == "watch"
        else "Double-Unders: N/A (Headphones)"
    )
    fig.suptitle(
        f"{stem} — {chart_title}  |  Detected Jumps: {len(jump_times)}  |  {du_label}",
        fontsize=14,
        fontweight="bold",
        color=TITLE_COLOR,
        x=0.06,
        y=0.96,
        ha="left",
    )

    # Top panel: Full session overview.
    for axis, col in zip(("X", "Y", "Z"), cols):
        ax_full.plot(
            times,
            df[col].to_numpy(),
            color=AXIS_COLORS[axis],
            linewidth=0.9,
            alpha=0.92,
            label=col,
            zorder=3,
        )

    for jt in jump_times:
        ax_full.axvline(
            jt,
            color=JUMP_LINE_COLOR,
            linestyle="--",
            linewidth=0.75,
            alpha=0.45,
            zorder=2,
        )

    for t0, t1 in double_under_pairs:
        ax_full.axvspan(t0, t1, color=DU_HIGHLIGHT_COLOR, alpha=0.25, zorder=2)

    ax_full.axvspan(w_start, w_end, color=TITLE_COLOR, alpha=0.07, zorder=1)
    ax_full.set_xlim(float(times[0]), float(times[-1]))
    style_axis(
        ax_full,
        ylabel=y_label,
        title=f"Full Session Overview (0.0s – {times[-1]:.1f}s; shaded region shows detail window)",
    )

    # Bottom panel: 10-second detail view.
    for axis, col in zip(("X", "Y", "Z"), cols):
        ax_zoom.plot(
            times[detail_mask],
            df[col].to_numpy()[detail_mask],
            color=AXIS_COLORS[axis],
            linewidth=1.8,
            label=col,
            zorder=3,
        )

    for jt in jump_times:
        if w_start <= jt <= w_end:
            ax_zoom.axvline(
                jt,
                color=JUMP_LINE_COLOR,
                linestyle="--",
                linewidth=1.2,
                alpha=0.75,
                zorder=2,
            )

    for idx, (t0, t1) in enumerate(double_under_pairs, start=1):
        if t1 >= w_start and t0 <= w_end:
            ax_zoom.axvspan(t0, t1, color=DU_HIGHLIGHT_COLOR, alpha=0.24, zorder=2)
            ax_zoom.axvline(t0, color=DU_HIGHLIGHT_COLOR, linewidth=1.3, alpha=0.85, zorder=4)
            ax_zoom.axvline(t1, color=DU_HIGHLIGHT_COLOR, linewidth=1.3, alpha=0.85, zorder=4)
            y_top = ax_zoom.get_ylim()[1]
            ax_zoom.text(
                (t0 + t1) / 2.0,
                y_top * 0.92,
                f"DU #{idx}\n{t1 - t0:.2f}s",
                ha="center",
                va="top",
                fontsize=8.5,
                fontweight="bold",
                color="#B75400",
                bbox={"boxstyle": "round,pad=0.2", "facecolor": "white", "alpha": 0.85, "edgecolor": DU_HIGHLIGHT_COLOR},
                zorder=5,
            )

    ax_zoom.set_xlim(w_start, w_end)
    ax_zoom.set_xlabel("Time (seconds)", fontsize=11, color=TITLE_COLOR)
    style_axis(
        ax_zoom,
        ylabel=y_label,
        title=f"Detail View ({w_start:.1f}s – {w_end:.1f}s)",
    )

    legend_handles: list[Line2D | Patch] = [
        Line2D([0], [0], color=AXIS_COLORS[axis], linewidth=2, label=f"{component_prefix}{axis}")
        for axis in ("X", "Y", "Z")
    ]
    legend_handles.append(
        Line2D([0], [0], color=JUMP_LINE_COLOR, linestyle="--", linewidth=1.4, label="Detected Jump")
    )
    if double_under_pairs:
        legend_handles.append(
            Patch(facecolor=DU_HIGHLIGHT_COLOR, edgecolor=DU_HIGHLIGHT_COLOR, alpha=0.35, label="Double-Under Pair")
        )

    ax_full.legend(
        handles=legend_handles,
        loc="upper left",
        bbox_to_anchor=(1.01, 1.0),
        frameon=False,
        fontsize=10,
        labelcolor=TITLE_COLOR,
    )

    fig.subplots_adjust(left=0.06, right=0.87, top=0.89, bottom=0.08)
    fig.savefig(output_path, dpi=180)
    plt.close(fig)


def process_csv(csv_path: Path, results_dir: Path) -> None:
    """Loads one motion CSV and saves its acceleration and rotation plots."""
    df = pd.read_csv(csv_path)
    df = df.rename(columns={"time": "Time"})

    stem = csv_path.stem
    profile = infer_profile(stem)
    jump_times, double_under_pairs = detect_motion_events(
        df["Time"].to_numpy(),
        df["AZ"].to_numpy(),
        profile=profile,
    )
    detail_window = choose_detail_window(
        df["Time"].to_numpy(),
        jump_times,
        double_under_pairs,
        stem=stem,
    )

    acc_path = results_dir / f"{stem}-a.png"
    rot_path = results_dir / f"{stem}-r.png"

    plot_component_group(
        df=df,
        stem=stem,
        profile=profile,
        jump_times=jump_times,
        double_under_pairs=double_under_pairs,
        detail_window=detail_window,
        component_prefix="A",
        y_label="Acceleration (g)",
        chart_title="Acceleration Components vs Time",
        output_path=acc_path,
    )
    plot_component_group(
        df=df,
        stem=stem,
        profile=profile,
        jump_times=jump_times,
        double_under_pairs=double_under_pairs,
        detail_window=detail_window,
        component_prefix="R",
        y_label="Rotation (rad/s)",
        chart_title="Rotation Components vs Time",
        output_path=rot_path,
    )

    print(
        f"{csv_path.name}: profile={profile}, jumps={len(jump_times)}, "
        f"double_unders={len(double_under_pairs)} -> {acc_path.name}, {rot_path.name}"
    )


def main() -> None:
    """Generates acceleration and rotation graphs for all CSVs in Analysis/motion-data."""
    analysis_dir = Path(__file__).resolve().parent
    motion_data_dir = analysis_dir / "motion-data"
    results_dir = analysis_dir / "results"
    results_dir.mkdir(parents=True, exist_ok=True)

    csv_files = sorted(motion_data_dir.glob("*.csv"))
    if not csv_files:
        raise FileNotFoundError(f"No CSV files found in {motion_data_dir}")

    for csv_path in csv_files:
        process_csv(csv_path, results_dir)


if __name__ == "__main__":
    main()
