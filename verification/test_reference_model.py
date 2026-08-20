import unittest

from reference_model import (
    format_output,
    gemm_reference,
    verification_cases,
    wrap_int32,
)


class ReferenceModelTests(unittest.TestCase):
    def test_signed_int8_gemm(self) -> None:
        self.assertEqual(
            gemm_reference(
                [1, -2, 3, -4], [5, 6, -7, 8], 2, 2, 2,
                output_int8=False, relu=False, shift=0,
            ),
            [19, -10, 43, -14],
        )

    def test_quantization_saturates_both_limits(self) -> None:
        self.assertEqual(format_output(1000, True, False, 0), 127)
        self.assertEqual(format_output(-1000, True, False, 0), -128)

    def test_arithmetic_shift_precedes_saturation(self) -> None:
        self.assertEqual(format_output(508, True, False, 2), 127)
        self.assertEqual(format_output(-9, True, False, 2), -3)

    def test_relu_applies_to_both_output_modes(self) -> None:
        self.assertEqual(format_output(-77, False, True, 0), 0)
        self.assertEqual(format_output(-77, True, True, 3), 0)

    def test_int32_accumulation_wraps(self) -> None:
        self.assertEqual(wrap_int32(0x8000_0000), -0x8000_0000)
        self.assertEqual(wrap_int32(0x1_0000_0001), 1)

    def test_stress_suite_is_balanced_and_fits_scratchpads(self) -> None:
        cases = verification_cases()
        self.assertEqual(len(cases), 64)
        self.assertEqual(sum(case.benchmark for case in cases), 11)
        self.assertTrue(any(case.output_int8 for case in cases))
        self.assertTrue(any(not case.output_int8 for case in cases))
        self.assertTrue(any(case.relu for case in cases))
        self.assertTrue(any(case.stall_mode for case in cases))
        self.assertEqual({0, 1, 2, 3, 7, 15, 31}, {case.shift for case in cases})
        for case in cases:
            self.assertLessEqual(max(case.m * case.k, case.k * case.n, case.m * case.n), 256)


if __name__ == "__main__":
    unittest.main()
