"""Plot ModelSim waveforms and performance counters."""

from __future__ import annotations

import argparse
import csv
import re
from bisect import bisect_right
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


WINDOW_RE = re.compile(r"#\s+CASE_WINDOW,([^,]+),(\d+),(\d+)")
TARGET_CASE = "backpressured_5x5x5_quant"


def read_window(path: Path, case_name: str) -> tuple[int, int]:
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = WINDOW_RE.search(line)
        if match and match.group(1) == case_name:
            return int(match.group(2)), int(match.group(3))
    raise ValueError(f"CASE_WINDOW for {case_name} not found in {path}")


def read_metrics(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def parse_vcd(path: Path) -> dict[str, list[tuple[int, str]]]:
    code_to_name: dict[str, str] = {}
    events: dict[str, list[tuple[int, str]]] = {}
    scope: list[str] = []
    in_definitions = True
    current_time = 0

    with path.open("r", encoding="ascii", errors="replace") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line:
                continue
            if in_definitions:
                if line.startswith("$scope"):
                    scope.append(line.split()[2])
                elif line.startswith("$upscope"):
                    scope.pop()
                elif line.startswith("$var"):
                    fields = line.split()
                    code = fields[3]
                    reference = fields[4]
                    full_name = "/".join((*scope, reference))
                    code_to_name[code] = full_name
                    events[full_name] = []
                elif line.startswith("$enddefinitions"):
                    in_definitions = False
                continue

            if line.startswith("#"):
                current_time = int(line[1:])
            elif line[0] in "01xzXZ":
                code = line[1:]
                if code in code_to_name:
                    events[code_to_name[code]].append((current_time, line[0].lower()))
            elif line[0] in "bBrR":
                fields = line.split()
                if len(fields) == 2 and fields[1] in code_to_name:
                    events[code_to_name[fields[1]]].append(
                        (current_time, fields[0][1:].lower())
                    )
    return events


def by_leaf(
    all_events: dict[str, list[tuple[int, str]]], leaf: str
) -> list[tuple[int, str]]:
    matches = [events for name, events in all_events.items() if name.endswith("/" + leaf)]
    if len(matches) != 1:
        raise ValueError(f"expected one VCD signal named {leaf}, found {len(matches)}")
    return matches[0]


def logic_value(value: str) -> int:
    return 1 if value == "1" else 0


def value_at(events: list[tuple[int, str]], time: int) -> int:
    times = [event[0] for event in events]
    index = bisect_right(times, time) - 1
    return logic_value(events[index][1]) if index >= 0 else 0


def clipped_step(
    events: list[tuple[int, str]], start: int, end: int
) -> tuple[np.ndarray, np.ndarray]:
    points: list[tuple[int, int]] = [(start, value_at(events, start))]
    for time, value in events:
        if start < time <= end:
            points.append((time, logic_value(value)))
    points.append((end, points[-1][1]))
    return (
        np.array([(time - start) / 1_000_000 for time, _ in points]),
        np.array([value for _, value in points]),
    )


def first_stall_time(
    valid: list[tuple[int, str]],
    ready: list[tuple[int, str]],
    start: int,
    end: int,
) -> int:
    candidates = sorted(
        {start, end}
        | {time for time, _ in valid if start <= time <= end}
        | {time for time, _ in ready if start <= time <= end}
    )
    for time in candidates:
        if value_at(valid, time) and not value_at(ready, time):
            return time
    raise ValueError("no valid/ready stall was present in the selected case")


def write_waveform_csv(
    path: Path,
    all_events: dict[str, list[tuple[int, str]]],
    signal_names: list[str],
    start: int,
    end: int,
) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["signal", "absolute_time_ps", "time_from_start_ns", "value"])
        for name in signal_names:
            events = by_leaf(all_events, name)
            writer.writerow([name, start, "0.000", value_at(events, start)])
            for time, value in events:
                if start < time <= end:
                    writer.writerow(
                        [name, time, f"{(time - start) / 1000:.3f}", logic_value(value)]
                    )


def render_waveform(
    output: Path,
    vcd_events: dict[str, list[tuple[int, str]]],
    start: int,
    end: int,
    metric: dict[str, str],
) -> None:
    phase_signals = [
        ("accel_busy", "Accelerator busy", "#1f4e79"),
        ("dma_busy", "DMA active", "#2e75b6"),
        ("compute_busy", "Compute active", "#548235"),
        ("mac_en", "MAC update", "#70ad47"),
        ("output_writer_busy", "Output writer", "#8064a2"),
        ("irq", "Completion IRQ", "#c00000"),
    ]
    bus_signals = [
        ("mem_req_valid", "req_valid", "#1f4e79"),
        ("mem_req_ready", "req_ready", "#ed7d31"),
        ("mem_req_write", "req_write", "#8064a2"),
        ("mem_rsp_valid", "rsp_valid", "#548235"),
    ]

    valid = by_leaf(vcd_events, "mem_req_valid")
    ready = by_leaf(vcd_events, "mem_req_ready")
    stall_time = first_stall_time(valid, ready, start, end)
    zoom_start = max(start, stall_time - 30_000)
    zoom_end = min(end, stall_time + 250_000)

    fig, (phase_ax, bus_ax) = plt.subplots(
        2,
        1,
        figsize=(15, 9),
        gridspec_kw={"height_ratios": [2.1, 1]},
        constrained_layout=True,
    )
    fig.suptitle(
        "Measured RTL waveform — 5×5×5 quantized GEMM with DMA backpressure",
        fontsize=16,
        fontweight="bold",
    )

    phase_labels: list[str] = []
    for lane, (name, label, color) in enumerate(reversed(phase_signals)):
        x, values = clipped_step(by_leaf(vcd_events, name), start, end)
        phase_ax.step(x, lane + values * 0.68, where="post", color=color, linewidth=1.5)
        phase_labels.append(label)
    phase_ax.set_yticks(np.arange(len(phase_labels)) + 0.34, phase_labels)
    phase_ax.set_ylim(-0.25, len(phase_labels) + 0.15)
    phase_ax.set_xlim(0, (end - start) / 1_000_000)
    phase_ax.set_xlabel("Time from START command (µs)")
    phase_ax.set_title(
        f"Full job: {metric['total_cycles']} cycles total · "
        f"{metric['dma_cycles']} DMA · {metric['compute_cycles']} compute · "
        f"{metric['stall_cycles']} counted stalls",
        loc="left",
        fontsize=11,
    )
    phase_ax.grid(axis="x", color="#d9d9d9", linewidth=0.7)
    phase_ax.spines[["top", "right", "left"]].set_visible(False)
    phase_ax.tick_params(axis="y", length=0)

    bus_labels: list[str] = []
    for lane, (name, label, color) in enumerate(reversed(bus_signals)):
        events = by_leaf(vcd_events, name)
        points: list[tuple[int, int]] = [(zoom_start, value_at(events, zoom_start))]
        for time, value in events:
            if zoom_start < time <= zoom_end:
                points.append((time, logic_value(value)))
        points.append((zoom_end, points[-1][1]))
        x = np.array([(time - zoom_start) / 1000 for time, _ in points])
        values = np.array([value for _, value in points])
        bus_ax.step(x, lane + values * 0.68, where="post", color=color, linewidth=1.7)
        bus_labels.append(label)
    stall_x = (stall_time - zoom_start) / 1000
    bus_ax.axvline(stall_x, color="#c00000", linestyle="--", linewidth=1.2)
    bus_ax.text(
        stall_x + 4,
        len(bus_labels) - 0.15,
        "valid=1, ready=0\n(counted stall)",
        color="#c00000",
        fontsize=10,
        va="top",
    )
    bus_ax.set_yticks(np.arange(len(bus_labels)) + 0.34, bus_labels)
    bus_ax.set_ylim(-0.25, len(bus_labels) + 0.15)
    bus_ax.set_xlim(0, (zoom_end - zoom_start) / 1000)
    bus_ax.set_xlabel("Time within handshake zoom (ns)")
    bus_ax.set_title("DMA ready/valid handshake zoom", loc="left", fontsize=11)
    bus_ax.grid(axis="x", color="#d9d9d9", linewidth=0.7)
    bus_ax.spines[["top", "right", "left"]].set_visible(False)
    bus_ax.tick_params(axis="y", length=0)

    fig.savefig(output / "rtl-waveform-backpressured-5x5.png", dpi=260)
    fig.savefig(output / "rtl-waveform-backpressured-5x5.svg")
    plt.close(fig)


def short_label(row: dict[str, str]) -> str:
    name = row["case"]
    shape = f"{row['M']}×{row['N']}×{row['K']} {row['output_mode']}"
    if name == "positive_saturation":
        return shape + " sat+"
    if name == "negative_saturation":
        return shape + " sat−"
    if name.startswith("backpressured"):
        return shape + " stalled"
    if "relu" in name:
        return shape + " ReLU"
    return shape


def render_performance(output: Path, metrics: list[dict[str, str]]) -> None:
    rows = [row for row in metrics if row["case_class"] == "directed-benchmark"]
    labels = [short_label(row) for row in rows]
    total = np.array([int(row["total_cycles"]) for row in rows])
    dma = np.array([int(row["dma_cycles"]) for row in rows])
    compute = np.array([int(row["compute_cycles"]) for row in rows])
    overhead = total - dma - compute
    stalls = np.array([int(row["stall_cycles"]) for row in rows])
    utilization = np.array([float(row["mac_utilization_pct"]) for row in rows])
    ops = np.array([float(row["effective_ops_per_cycle"]) for row in rows])
    y = np.arange(len(rows))

    fig = plt.figure(figsize=(16, 12), constrained_layout=True)
    grid = fig.add_gridspec(2, 2, height_ratios=[1.45, 1])
    cycle_ax = fig.add_subplot(grid[0, :])
    util_ax = fig.add_subplot(grid[1, 0])
    ops_ax = fig.add_subplot(grid[1, 1])
    fig.suptitle("Measured accelerator performance — directed RTL benchmarks", fontsize=17, fontweight="bold")

    cycle_ax.barh(y, dma, color="#2e75b6", label="DMA active")
    cycle_ax.barh(y, compute, left=dma, color="#70ad47", label="Compute active")
    cycle_ax.barh(y, overhead, left=dma + compute, color="#bfbfbf", label="Controller/other")
    stalled_rows = np.flatnonzero(stalls > 0)
    cycle_ax.scatter(stalls[stalled_rows], stalled_rows, marker="D", color="#c00000", s=42, label="Stall-cycle count")
    for index in stalled_rows:
        cycle_ax.text(stalls[index] + max(total) * 0.012, index, f"{stalls[index]} stalls", va="center", fontsize=9, color="#c00000")
    cycle_ax.set_yticks(y, labels)
    cycle_ax.invert_yaxis()
    cycle_ax.set_xlabel("Cycles")
    cycle_ax.set_title("Total-cycle composition and measured stall counts", loc="left")
    cycle_ax.grid(axis="x", color="#e0e0e0", linewidth=0.7)
    cycle_ax.legend(ncol=4, frameon=False, loc="lower right")
    cycle_ax.spines[["top", "right", "left"]].set_visible(False)
    cycle_ax.tick_params(axis="y", length=0)

    util_ax.barh(y, utilization, color="#548235")
    for index, value in enumerate(utilization):
        util_ax.text(min(value + 1.5, 96), index, f"{value:.1f}%", va="center", fontsize=9)
    util_ax.set_yticks(y, labels)
    util_ax.invert_yaxis()
    util_ax.set_xlim(0, 105)
    util_ax.set_xlabel("Useful MAC utilization (%)")
    util_ax.set_title("Array utilization", loc="left")
    util_ax.grid(axis="x", color="#e0e0e0", linewidth=0.7)
    util_ax.spines[["top", "right", "left"]].set_visible(False)
    util_ax.tick_params(axis="y", length=0)

    ops_ax.barh(y, ops, color="#8064a2")
    for index, value in enumerate(ops):
        ops_ax.text(value + max(ops) * 0.025, index, f"{value:.3f}", va="center", fontsize=9)
    ops_ax.set_yticks(y, labels)
    ops_ax.invert_yaxis()
    ops_ax.set_xlim(0, max(ops) * 1.2)
    ops_ax.set_xlabel("Effective operations per cycle")
    ops_ax.set_title("End-to-end throughput (2×M×N×K / total cycles)", loc="left")
    ops_ax.grid(axis="x", color="#e0e0e0", linewidth=0.7)
    ops_ax.spines[["top", "right", "left"]].set_visible(False)
    ops_ax.tick_params(axis="y", length=0)

    fig.savefig(output / "performance-benchmark-summary.png", dpi=260)
    fig.savefig(output / "performance-benchmark-summary.svg")
    plt.close(fig)


def write_captions(path: Path) -> None:
    path.write_text(
        "# Figure captions\n\n"
        "**Figure 1 — Cycle-accurate RTL waveform.** ModelSim trace for a 5×5×5 signed-INT8 GEMM with shift-3 INT8 output and two forced ready-stall cycles per DMA request. The full-job panel shows serialized load, compute, output-write, and completion phases. The handshake zoom demonstrates a counted `mem_req_valid && !mem_req_ready` stall.\n\n"
        "**Figure 2 — Directed benchmark performance.** Cycle-accurate counter values read through APB after each completed job. Total latency is separated into DMA-active, compute-active, and controller/other cycles; red diamonds show stall-cycle counts. MAC utilization measures useful scalar MACs divided by the 16 available lanes over `PERF_MAC_CYCLES`; effective operations/cycle is `2×M×N×K/PERF_CYCLES`.\n",
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--vcd", type=Path, required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--metrics", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    metrics = read_metrics(args.metrics)
    metric = next(row for row in metrics if row["case"] == TARGET_CASE)
    start, end = read_window(args.log, TARGET_CASE)
    vcd_events = parse_vcd(args.vcd)
    waveform_signals = [
        "accel_busy",
        "dma_busy",
        "compute_busy",
        "mac_en",
        "output_writer_busy",
        "irq",
        "mem_req_valid",
        "mem_req_ready",
        "mem_req_write",
        "mem_rsp_valid",
    ]
    write_waveform_csv(
        args.output / "rtl-waveform-backpressured-5x5.csv",
        vcd_events,
        waveform_signals,
        start,
        end,
    )
    render_waveform(args.output, vcd_events, start, end, metric)
    render_performance(args.output, metrics)
    write_captions(args.output / "figure-captions.md")
    print(f"Wrote waveform and performance plots to {args.output}")


if __name__ == "__main__":
    main()
