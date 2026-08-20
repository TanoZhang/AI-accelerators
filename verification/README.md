# Verification

Run the complete regression from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .\run_regression.ps1
```

The script:

1. Tests the Python reference model.
2. Generates 64 signed INT8 matrix jobs.
3. Compiles the RTL and testbenches.
4. Runs 13 unit benches.
5. Runs 6 error and recovery cases.
6. Runs 64 full-system jobs and records a VCD.
7. Writes the report, CSV files, and plots.

Generated artifacts:

- `verification/results/verification_report.md`: summary and cycle counts
- `verification/results/performance.csv`: performance data for all jobs
- `verification/results/error_scenarios.csv`: error-path results
- `verification/results/rtl_trace.vcd`: waveform capture
- `verification/results/figures/`: plots and captions
- `verification/logs/`: compiler and simulator logs
- `tb/generated/e2e_vectors.txt`: generated test vectors

Each external-memory word holds one matrix element. The integration test checks exactly `M*K + K*N + M*N` DMA transfers.
