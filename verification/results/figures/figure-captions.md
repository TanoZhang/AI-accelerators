# Figure captions

**Figure 1 — Cycle-accurate RTL waveform.** ModelSim trace for a 5×5×5 signed-INT8 GEMM with shift-3 INT8 output and two forced ready-stall cycles per DMA request. The full-job panel shows serialized load, compute, output-write, and completion phases. The handshake zoom demonstrates a counted `mem_req_valid && !mem_req_ready` stall.

**Figure 2 — Directed benchmark performance.** Cycle-accurate counter values read through APB after each completed job. Total latency is separated into DMA-active, compute-active, and controller/other cycles; red diamonds show stall-cycle counts. MAC utilization measures useful scalar MACs divided by the 16 available lanes over `PERF_MAC_CYCLES`; effective operations/cycle is `2×M×N×K/PERF_CYCLES`.
