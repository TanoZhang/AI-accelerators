// Per-command cycle counters. The accepted START and terminal event cycles count.
module perf_counters #(
  parameter int unsigned COUNTER_W = 32
) (
  input  logic                 clk,
  input  logic                 rst_n,

  input  logic                 start_accepted,
  input  logic                 done_event,
  input  logic                 error_event,
  input  logic                 compute_active,
  input  logic                 mac_en,
  input  logic                 dma_active,
  input  logic                 compute_stall,
  input  logic                 dma_stall,

  output logic [COUNTER_W-1:0] perf_cycles,
  output logic [COUNTER_W-1:0] perf_compute_cycles,
  output logic [COUNTER_W-1:0] perf_mac_cycles,
  output logic [COUNTER_W-1:0] perf_dma_cycles,
  output logic [COUNTER_W-1:0] perf_stall_cycles
);

  logic job_active_q;
  logic terminal_event;
  logic stall_cycle;

  function automatic logic [COUNTER_W-1:0] saturating_increment(
    input logic [COUNTER_W-1:0] value
  );
    begin
      if (&value) begin
        return value;
      end
      return value + 1'b1;
    end
  endfunction

  always_comb begin
    terminal_event = done_event || error_event;
    stall_cycle = (compute_active && compute_stall)
               || (dma_active && dma_stall);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      job_active_q       <= 1'b0;
      perf_cycles        <= '0;
      perf_compute_cycles <= '0;
      perf_mac_cycles    <= '0;
      perf_dma_cycles    <= '0;
      perf_stall_cycles  <= '0;
    end else if (start_accepted) begin
      job_active_q        <= !terminal_event;
      perf_cycles         <= {{(COUNTER_W-1){1'b0}}, 1'b1};
      perf_compute_cycles <= compute_active
                           ? {{(COUNTER_W-1){1'b0}}, 1'b1} : '0;
      perf_mac_cycles     <= mac_en
                           ? {{(COUNTER_W-1){1'b0}}, 1'b1} : '0;
      perf_dma_cycles     <= dma_active
                           ? {{(COUNTER_W-1){1'b0}}, 1'b1} : '0;
      perf_stall_cycles   <= stall_cycle
                           ? {{(COUNTER_W-1){1'b0}}, 1'b1} : '0;
    end else if (job_active_q) begin
      perf_cycles <= saturating_increment(perf_cycles);

      if (compute_active) begin
        perf_compute_cycles <= saturating_increment(perf_compute_cycles);
      end
      if (mac_en) begin
        perf_mac_cycles <= saturating_increment(perf_mac_cycles);
      end
      if (dma_active) begin
        perf_dma_cycles <= saturating_increment(perf_dma_cycles);
      end
      if (stall_cycle) begin
        perf_stall_cycles <= saturating_increment(perf_stall_cycles);
      end

      if (terminal_event) begin
        job_active_q <= 1'b0;
      end
    end
  end

`ifndef SYNTHESIS
  property p_start_only_when_idle;
    @(posedge clk) disable iff (!rst_n)
      start_accepted |-> !job_active_q;
  endproperty

  property p_total_never_wraps;
    @(posedge clk) disable iff (!rst_n)
      ((&perf_cycles) && !start_accepted) |=> (&perf_cycles);
  endproperty

  property p_compute_never_wraps;
    @(posedge clk) disable iff (!rst_n)
      ((&perf_compute_cycles) && !start_accepted)
      |=> (&perf_compute_cycles);
  endproperty

  property p_mac_never_wraps;
    @(posedge clk) disable iff (!rst_n)
      ((&perf_mac_cycles) && !start_accepted) |=> (&perf_mac_cycles);
  endproperty

  property p_dma_never_wraps;
    @(posedge clk) disable iff (!rst_n)
      ((&perf_dma_cycles) && !start_accepted) |=> (&perf_dma_cycles);
  endproperty

  property p_stall_never_wraps;
    @(posedge clk) disable iff (!rst_n)
      ((&perf_stall_cycles) && !start_accepted) |=> (&perf_stall_cycles);
  endproperty

  assert property (p_start_only_when_idle)
    else $error("perf_counters received START while a job was active");
  assert property (p_total_never_wraps);
  assert property (p_compute_never_wraps);
  assert property (p_mac_never_wraps);
  assert property (p_dma_never_wraps);
  assert property (p_stall_never_wraps);
`endif

endmodule
