# Feeder experiment

The first feeder reads one A value and one B value at a time. Filling a four-lane
vector therefore takes several cycles even though the MAC array can accept a
new outer product every cycle.

I kept that implementation in the project as the scalar baseline. The parallel
version gives each lane a scratchpad read port and uses a two-entry FIFO between
the memory response and the compute controller. APB, DMA, the MAC array, output
formatting, and the test data are unchanged.

For the 8x8x8 FPGA test, RTL simulation measured 309 compute cycles with the
scalar feeder and 67 with the parallel feeder. End-to-end time changed from
1037 to 795 cycles because both runs still spend 704 cycles in DMA.

The two DE25 builds showed the same total counts on the seven-segment display:
`040d` for scalar and `031b` for parallel.

The full per-case data is generated in
`verification/results/feeder_comparison.csv`. The useful point here is not that
every workload becomes five times faster. Operand delivery became faster, but
the simple one-word DMA is now the larger bottleneck.
