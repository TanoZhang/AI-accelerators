"""Parse ModelSim logs and write CSV and Markdown results."""

from __future__ import annotations

import argparse
import csv
import re
from dataclasses import dataclass
from pathlib import Path


PASS_RE = re.compile(r"#\s+(tb_[A-Za-z0-9_]+) PASS \((.+)\)")
ERROR_SCENARIO_RE = re.compile(r"#\s+ERROR_SCENARIO,([^,]+),(PASS)")
METRIC_RE = re.compile(
    r"#\s+METRIC,([^,]+),(\d+),(\d+),(\d+),(\d+),(\d+),(\d+),"
    r"(\d+),(\d+),(\d+),(\d+),(\d+),(\d+),(\d+),"
    r"([0-9.]+),([0-9.]+)"
)


@dataclass(frozen=True)
class Metric:
    name: str
    m: int
    n: int
    k: int
    output_int8: int
    relu: int
    shift: int
    stall_mode: int
    benchmark: int
    total_cycles: int
    mac_cycles: int
    compute_cycles: int
    dma_cycles: int
    stall_cycles: int
    mac_utilization_pct: float
    effective_ops_per_cycle: float

    @classmethod
    def from_match(cls, match: re.Match[str]) -> "Metric":
        values = match.groups()
        return cls(
            values[0],
            *map(int, values[1:14]),
            float(values[14]),
            float(values[15]),
        )


def read_passes(log_directory: Path) -> dict[str, str]:
    passes: dict[str, str] = {}
    for path in sorted(log_directory.glob("tb_*.log")):
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            match = PASS_RE.search(line)
            if match:
                passes[match.group(1)] = match.group(2)
    return passes


def read_metrics(path: Path) -> list[Metric]:
    metrics: list[Metric] = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = METRIC_RE.search(line)
        if match:
            metrics.append(Metric.from_match(match))
    return metrics


def read_error_scenarios(path: Path) -> list[tuple[str, str]]:
    scenarios: list[tuple[str, str]] = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = ERROR_SCENARIO_RE.search(line)
        if match:
            scenarios.append((match.group(1), match.group(2)))
    return scenarios


def write_error_csv(path: Path, scenarios: list[tuple[str, str]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["integrated_scenario", "result"])
        writer.writerows(scenarios)


def write_csv(path: Path, metrics: list[Metric]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            [
                "case",
                "M",
                "N",
                "K",
                "output_mode",
                "relu",
                "quant_shift",
                "memory_profile",
                "case_class",
                "total_cycles",
                "mac_cycles",
                "compute_cycles",
                "dma_cycles",
                "stall_cycles",
                "mac_utilization_pct",
                "effective_ops_per_cycle",
            ]
        )
        for metric in metrics:
            writer.writerow(
                [
                    metric.name,
                    metric.m,
                    metric.n,
                    metric.k,
                    "INT8" if metric.output_int8 else "INT32",
                    "enabled" if metric.relu else "disabled",
                    metric.shift,
                    "zero-wait" if metric.stall_mode == 0 else f"stalled-{metric.stall_mode}",
                    "directed-benchmark" if metric.benchmark else "constrained-random-stress",
                    metric.total_cycles,
                    metric.mac_cycles,
                    metric.compute_cycles,
                    metric.dma_cycles,
                    metric.stall_cycles,
                    f"{metric.mac_utilization_pct:.3f}",
                    f"{metric.effective_ops_per_cycle:.6f}",
                ]
            )


def write_report(
    path: Path,
    passes: dict[str, str],
    metrics: list[Metric],
    error_scenarios: list[tuple[str, str]],
) -> None:
    unit_passes = {
        name: detail for name, detail in passes.items()
        if not name.startswith("tb_end_to_end")
    }
    benchmarks = [metric for metric in metrics if metric.benchmark]
    stress = [metric for metric in metrics if not metric.benchmark]
    lines = [
        "# Verification results",
        "",
        "## Result",
        "",
        f"**PASS:** {len(unit_passes)} RTL unit benches, {len(metrics)} full-system jobs, and 6 error/recovery scenarios.",
        "",
        "Each job is programmed through APB and runs through DMA, scratchpads, the 4×4 MAC array, output formatting, and writeback. Results are checked against `verification/reference_model.py`.",
        "",
        "## Requirement coverage",
        "",
        "| Area | Coverage |",
        "|---|---|",
        f"| Several matrix multiplications | {len(benchmarks)} directed jobs plus {len(stress)} deterministic constrained-random jobs |",
        "| Dimensions not divisible by four | Shapes from 1 through 15, including edge-heavy M/N/K values and multi-tile matrices |",
        "| Negative INT8 values | Mixed signed random vectors and explicit -128 operand |",
        "| Saturation | Dedicated positive-to-127 and negative-to--128 cases |",
        "| Quantized outputs | Shifts 0, 1, 2, 3, 7, 15, and 31 with and without ReLU |",
        "| INT32 outputs | Signed, multi-tile, and ReLU-enabled INT32 cases |",
        "| DMA correctness | Exact request count and logical A/B/C address bounds checked per job |",
        "| Edge-write safety | Canary words immediately before and after C checked per job |",
        "| Performance | Total, MAC, compute, DMA, stall, utilization, and effective ops/cycle recorded below |",
        "| Backpressure | Two request-stall patterns and response delays from 0 through 4 cycles |",
        "| Error handling | Zero dimension, misalignment, DMA read error, DMA write error, start-while-busy, and clean recovery |",
        "",
        "## Performance measurements",
        "",
        "MAC utilization is `useful MACs / (16 × PERF_MAC_CYCLES)`. Operations per cycle is `2 × M × N × K / PERF_CYCLES`. Values come from RTL simulation.",
        "",
        "| Case | Shape | Output | Memory | Total | MAC | Compute | DMA | Stall | MAC util. | Ops/cycle |",
        "|---|---:|---|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for metric in benchmarks:
        output = "INT8" if metric.output_int8 else "INT32"
        memory = "zero-wait" if metric.stall_mode == 0 else f"stalled-{metric.stall_mode}"
        lines.append(
            f"| `{metric.name}` | {metric.m}×{metric.n}×{metric.k} | {output} | {memory} | "
            f"{metric.total_cycles} | {metric.mac_cycles} | {metric.compute_cycles} | "
            f"{metric.dma_cycles} | {metric.stall_cycles} | "
            f"{metric.mac_utilization_pct:.3f}% | {metric.effective_ops_per_cycle:.6f} |"
        )

    best = max(metrics, key=lambda metric: metric.effective_ops_per_cycle)
    worst_util = min(metrics, key=lambda metric: metric.mac_utilization_pct)
    lines.extend(
        [
            "",
            "## Interpretation",
            "",
            f"The best measured effective throughput is **{best.effective_ops_per_cycle:.6f} ops/cycle** on `{best.name}`. Full 4×4 tiles reach 100% array utilization; narrow and edge-heavy matrices reduce useful-lane utilization, with the lowest measured value **{worst_util.mac_utilization_pct:.3f}%** on `{worst_util.name}`.",
            "",
            "DMA dominates latency because requests transfer one word at a time and load, compute, and store do not overlap. `PERF_STALL_CYCLES` counts request backpressure; response delay is included in `PERF_DMA_CYCLES`.",
            "",
            f"The table shows {len(benchmarks)} directed cases. `performance.csv` contains all {len(metrics)} jobs, including {len(stress)} fixed-seed random cases.",
            "",
            "## Files",
            "",
            "- `verification/results/figures/rtl-waveform-backpressured-5x5.png`: control and ready/valid waveform",
            "- `verification/results/figures/performance-benchmark-summary.png`: cycle, utilization, and throughput plots",
            "- `verification/results/figures/rtl-waveform-backpressured-5x5.csv`: plotted signal transitions",
            "- `verification/results/rtl_trace.vcd`: source waveform",
            "- `verification/results/performance.csv` and `verification/results/error_scenarios.csv`: raw results",
            "",
            "SVG versions and captions are stored with the PNG files.",
            "",
            "## Error handling",
            "",
        ]
    )
    for scenario, result in error_scenarios:
        lines.append(f"- `{scenario}`: {result}")
    lines.extend(
        [
            "",
            "## Regression inventory",
            "",
        ]
    )
    for name, detail in sorted(unit_passes.items()):
        lines.append(f"- `{name}`: PASS ({detail})")
    lines.extend(
        [
            "",
            "The Python model has six tests for signed GEMM, saturation, shifts, ReLU, INT32 wrapping, and test-vector bounds.",
            "",
            "## Reproduce",
            "",
            "From the repository root on Windows with ModelSim and Python available:",
            "",
            "```powershell",
            "powershell -ExecutionPolicy Bypass -File .\\run_regression.ps1",
            "```",
            "",
            "Performance data is in `verification/results/performance.csv`; logs are in `verification/logs/`.",
        ]
    )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--logs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    passes = read_passes(args.logs)
    metrics = read_metrics(args.logs / "tb_end_to_end.log")
    error_scenarios = read_error_scenarios(args.logs / "tb_end_to_end_errors.log")
    if len(metrics) != 64:
        raise SystemExit(f"expected 64 METRIC records, found {len(metrics)}")
    if "tb_end_to_end" not in passes:
        raise SystemExit("end-to-end PASS signature is missing")
    if "tb_end_to_end_errors" not in passes:
        raise SystemExit("integrated error-path PASS signature is missing")
    if len(error_scenarios) != 6:
        raise SystemExit(f"expected 6 error scenarios, found {len(error_scenarios)}")

    write_csv(args.output / "performance.csv", metrics)
    write_error_csv(args.output / "error_scenarios.csv", error_scenarios)
    write_report(
        args.output / "verification_report.md",
        passes,
        metrics,
        error_scenarios,
    )
    print(f"Wrote results for {len(metrics)} end-to-end cases to {args.output}")


if __name__ == "__main__":
    main()
