"""Independent software reference and deterministic end-to-end vector generator."""

from __future__ import annotations

import argparse
import random
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence


def wrap_int32(value: int) -> int:
    """Wrap an integer to the accelerator's signed two's-complement INT32."""
    value &= 0xFFFF_FFFF
    return value - 0x1_0000_0000 if value & 0x8000_0000 else value


def format_output(value: int, output_int8: bool, relu: bool, shift: int) -> int:
    """Apply the documented output ordering: ReLU, shift, then INT8 saturation."""
    if not 0 <= shift <= 31:
        raise ValueError(f"shift must be in [0, 31], got {shift}")
    value = wrap_int32(value)
    if relu and value < 0:
        value = 0
    if not output_int8:
        return value
    shifted = value >> shift
    return max(-128, min(127, shifted))


def gemm_reference(
    a: Sequence[int],
    b: Sequence[int],
    m: int,
    n: int,
    k: int,
    *,
    output_int8: bool,
    relu: bool,
    shift: int,
) -> list[int]:
    """Compute row-major C=A*B using signed INT8 operands and INT32 accumulation."""
    if (m <= 0) or (n <= 0) or (k <= 0):
        raise ValueError("matrix dimensions must be non-zero")
    if len(a) != m * k or len(b) != k * n:
        raise ValueError("input list length does not match matrix dimensions")
    if any(value < -128 or value > 127 for value in (*a, *b)):
        raise ValueError("all operands must be signed INT8 values")

    result: list[int] = []
    for row in range(m):
        for col in range(n):
            accumulator = 0
            for reduction in range(k):
                accumulator = wrap_int32(
                    accumulator + a[row * k + reduction] * b[reduction * n + col]
                )
            result.append(
                format_output(accumulator, output_int8, relu, shift)
            )
    return result


@dataclass(frozen=True)
class VerificationCase:
    name: str
    m: int
    n: int
    k: int
    output_int8: bool
    relu: bool
    shift: int
    stall_mode: int
    response_delay: int
    a: tuple[int, ...]
    b: tuple[int, ...]
    benchmark: bool = False

    @property
    def expected(self) -> list[int]:
        return gemm_reference(
            self.a,
            self.b,
            self.m,
            self.n,
            self.k,
            output_int8=self.output_int8,
            relu=self.relu,
            shift=self.shift,
        )


def _random_values(count: int, seed: int) -> tuple[int, ...]:
    generator = random.Random(seed)
    values = [generator.randint(-128, 127) for _ in range(count)]
    if count >= 4:
        values[:4] = [-128, -7, 5, 127]
    return tuple(values)


def benchmark_cases() -> list[VerificationCase]:
    """Directed cases retained as the concise performance benchmark set."""
    return [
        VerificationCase(
            "signed_min_1x1_int32", 1, 1, 1, False, False, 0, 0, 0,
            (-128,), (1,), benchmark=True,
        ),
        VerificationCase(
            "basic_2x2_int32", 2, 2, 2, False, False, 0, 0, 1,
            (1, 2, 3, 4), (5, 6, 7, 8), benchmark=True,
        ),
        VerificationCase(
            "fpga_ab_8x8x8_int32", 8, 8, 8, False, False, 0, 0, 0,
            tuple(value for value in (-4, -3, -2, -1, 1, 2, 3, 4)
                  for _ in range(8)),
            tuple(-1 if col < 4 else 1
                  for _ in range(8) for col in range(8)),
            benchmark=True,
        ),
        VerificationCase(
            "edge_5x3x7_int32", 5, 3, 7, False, False, 0, 0, 2,
            _random_values(5 * 7, 0x537A), _random_values(7 * 3, 0x537B),
            benchmark=True,
        ),
        VerificationCase(
            "edge_3x5x5_quant_shift2", 3, 5, 5, True, False, 2, 0, 1,
            _random_values(3 * 5, 0x355A), _random_values(5 * 5, 0x355B),
            benchmark=True,
        ),
        VerificationCase(
            "positive_saturation", 4, 4, 8, True, False, 0, 0, 0,
            (127,) * (4 * 8), (127,) * (8 * 4), benchmark=True,
        ),
        VerificationCase(
            "negative_saturation", 4, 4, 8, True, False, 0, 0, 1,
            (127,) * (4 * 8), (-128,) * (8 * 4), benchmark=True,
        ),
        VerificationCase(
            "edge_7x6x3_quant_relu", 7, 6, 3, True, True, 1, 0, 2,
            _random_values(7 * 3, 0x763A), _random_values(3 * 6, 0x763B),
            benchmark=True,
        ),
        VerificationCase(
            "relu_2x3x4_int32", 2, 3, 4, False, True, 0, 0, 1,
            (1, -2, 3, -4, -5, 6, -7, 8),
            (2, -3, 4, -5, 6, -7, 8, -9, 10, -11, 12, -13),
            benchmark=True,
        ),
        VerificationCase(
            "edge_6x5x7_int32", 6, 5, 7, False, False, 0, 0, 0,
            _random_values(6 * 7, 0x657A), _random_values(7 * 5, 0x657B),
            benchmark=True,
        ),
        VerificationCase(
            "backpressured_5x5x5_quant", 5, 5, 5, True, False, 3, 2, 3,
            _random_values(5 * 5, 0x555A), _random_values(5 * 5, 0x555B),
            benchmark=True,
        ),
        VerificationCase(
            "backpressured_1x6x5_relu", 1, 6, 5, True, True, 2, 1, 4,
            _random_values(1 * 5, 0x165A), _random_values(5 * 6, 0x165B),
            benchmark=True,
        ),
    ]


def stress_cases(count: int = 52) -> list[VerificationCase]:
    """Deterministic constrained-random jobs that fit all three scratchpads."""
    generator = random.Random(0xACC3_51)
    shifts = (0, 1, 2, 3, 7, 15, 31)
    cases: list[VerificationCase] = []
    while len(cases) < count:
        m = generator.randint(1, 15)
        n = generator.randint(1, 15)
        k = generator.randint(1, 15)
        if max(m * k, k * n, m * n) > 256:
            continue

        index = len(cases)
        output_int8 = bool(index & 1)
        relu = bool((index // 2) & 1)
        shift = shifts[index % len(shifts)]
        if index % 11 == 0:
            stall_mode = 2
        elif index % 7 == 0:
            stall_mode = 1
        else:
            stall_mode = 0
        response_delay = index % 5
        a_seed = generator.randrange(1 << 30)
        b_seed = generator.randrange(1 << 30)
        cases.append(
            VerificationCase(
                f"stress_{index:02d}_{m}x{n}x{k}",
                m,
                n,
                k,
                output_int8,
                relu,
                shift,
                stall_mode,
                response_delay,
                _random_values(m * k, a_seed),
                _random_values(k * n, b_seed),
            )
        )
    return cases


def verification_cases() -> list[VerificationCase]:
    """64 jobs with directed benchmarks and constrained-random stress jobs."""
    return benchmark_cases() + stress_cases()


def _u32(value: int) -> int:
    return value & 0xFFFF_FFFF


def _write_words(handle, values: Iterable[int]) -> None:
    for value in values:
        handle.write(f"{_u32(value):08x}\n")


def write_vectors(path: Path) -> None:
    cases = verification_cases()
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii", newline="\n") as handle:
        handle.write(f"{len(cases)}\n")
        for case in cases:
            handle.write(
                f"{case.name} {case.m} {case.n} {case.k} "
                f"{int(case.output_int8)} {int(case.relu)} {case.shift} "
                f"{case.stall_mode} {case.response_delay} {int(case.benchmark)}\n"
            )
            _write_words(handle, case.a)
            _write_words(handle, case.b)
            _write_words(handle, case.expected)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("tb/generated/e2e_vectors.txt"),
        help="destination vector file",
    )
    args = parser.parse_args()
    write_vectors(args.output)
    print(f"Generated {len(verification_cases())} reference cases in {args.output}")


if __name__ == "__main__":
    main()
