`timescale 1ns/1ps

module tb_perf_counters;

  logic clk;
  logic rst_n;
  logic start_accepted;
  logic done_event;
  logic error_event;
  logic compute_active;
  logic mac_en;
  logic dma_active;
  logic compute_stall;
  logic dma_stall;

  logic [31:0] perf_cycles;
  logic [31:0] perf_compute_cycles;
  logic [31:0] perf_mac_cycles;
  logic [31:0] perf_dma_cycles;
  logic [31:0] perf_stall_cycles;

  logic [3:0] small_cycles;
  logic [3:0] small_compute_cycles;
  logic [3:0] small_mac_cycles;
  logic [3:0] small_dma_cycles;
  logic [3:0] small_stall_cycles;

  int unsigned checks;

  perf_counters dut (
    .clk                 (clk),
    .rst_n               (rst_n),
    .start_accepted      (start_accepted),
    .done_event          (done_event),
    .error_event         (error_event),
    .compute_active      (compute_active),
    .mac_en              (mac_en),
    .dma_active          (dma_active),
    .compute_stall       (compute_stall),
    .dma_stall           (dma_stall),
    .perf_cycles         (perf_cycles),
    .perf_compute_cycles (perf_compute_cycles),
    .perf_mac_cycles     (perf_mac_cycles),
    .perf_dma_cycles     (perf_dma_cycles),
    .perf_stall_cycles   (perf_stall_cycles)
  );

  perf_counters #(
    .COUNTER_W (4)
  ) saturation_dut (
    .clk                 (clk),
    .rst_n               (rst_n),
    .start_accepted      (start_accepted),
    .done_event          (done_event),
    .error_event         (error_event),
    .compute_active      (compute_active),
    .mac_en              (mac_en),
    .dma_active          (dma_active),
    .compute_stall       (compute_stall),
    .dma_stall           (dma_stall),
    .perf_cycles         (small_cycles),
    .perf_compute_cycles (small_compute_cycles),
    .perf_mac_cycles     (small_mac_cycles),
    .perf_dma_cycles     (small_dma_cycles),
    .perf_stall_cycles   (small_stall_cycles)
  );

  always #5 clk = ~clk;

  task automatic fail(input string label, input string detail);
    begin
      $error("%s: %s", label, detail);
      $fatal(1, "tb_perf_counters failed");
    end
  endtask

  task automatic tick(
    input logic next_start,
    input logic next_done,
    input logic next_error,
    input logic next_compute_active,
    input logic next_mac_en,
    input logic next_dma_active,
    input logic next_compute_stall,
    input logic next_dma_stall
  );
    begin
      @(negedge clk);
      start_accepted = next_start;
      done_event     = next_done;
      error_event    = next_error;
      compute_active = next_compute_active;
      mac_en         = next_mac_en;
      dma_active     = next_dma_active;
      compute_stall  = next_compute_stall;
      dma_stall      = next_dma_stall;
      @(posedge clk);
      #1;
    end
  endtask

  task automatic check_counts(
    input logic [31:0] expected_total,
    input logic [31:0] expected_compute,
    input logic [31:0] expected_mac,
    input logic [31:0] expected_dma,
    input logic [31:0] expected_stall,
    input string       label
  );
    begin
      checks += 5;
      if ((perf_cycles !== expected_total)
          || (perf_compute_cycles !== expected_compute)
          || (perf_mac_cycles !== expected_mac)
          || (perf_dma_cycles !== expected_dma)
          || (perf_stall_cycles !== expected_stall)) begin
        $error("%s: got total=%0d compute=%0d mac=%0d dma=%0d stall=%0d",
               label, perf_cycles, perf_compute_cycles, perf_mac_cycles,
               perf_dma_cycles, perf_stall_cycles);
        fail(label, "counter mismatch");
      end
    end
  endtask

  initial begin
    clk            = 1'b0;
    rst_n          = 1'b1;
    start_accepted = 1'b0;
    done_event     = 1'b0;
    error_event    = 1'b0;
    compute_active = 1'b0;
    mac_en         = 1'b0;
    dma_active     = 1'b0;
    compute_stall  = 1'b0;
    dma_stall      = 1'b0;
    checks         = 0;

    #1;
    rst_n = 1'b0;
    #1;
    check_counts(0, 0, 0, 0, 0, "reset");
    @(negedge clk);
    rst_n = 1'b1;

    tick(0, 0, 0, 1, 1, 1, 1, 1);
    check_counts(0, 0, 0, 0, 0, "activity before START");

    tick(1, 0, 0, 0, 0, 1, 0, 1);
    check_counts(1, 0, 0, 1, 1, "accepted START cycle");

    tick(0, 0, 0, 0, 0, 1, 0, 0);
    check_counts(2, 0, 0, 2, 1, "DMA progress cycle");

    tick(0, 0, 0, 0, 0, 0, 0, 0);
    check_counts(3, 0, 0, 2, 1, "active idle cycle");

    tick(0, 0, 0, 1, 0, 0, 1, 0);
    check_counts(4, 1, 0, 2, 2, "compute stall cycle");

    tick(0, 0, 0, 1, 1, 0, 0, 0);
    check_counts(5, 2, 1, 2, 2, "MAC cycle");

    tick(0, 0, 0, 1, 0, 1, 1, 1);
    check_counts(6, 3, 1, 3, 3, "overlapping stall counts once");

    tick(0, 1, 0, 0, 0, 1, 0, 1);
    check_counts(7, 3, 1, 4, 4, "completion cycle included");

    tick(0, 0, 0, 1, 1, 1, 1, 1);
    check_counts(7, 3, 1, 4, 4, "final values preserved");

    tick(1, 1, 0, 1, 1, 0, 0, 0);
    check_counts(1, 1, 1, 0, 0, "single-cycle command");

    tick(0, 0, 0, 1, 1, 1, 1, 1);
    check_counts(1, 1, 1, 0, 0, "single-cycle values preserved");

    tick(1, 0, 1, 0, 0, 1, 0, 0);
    check_counts(1, 0, 0, 1, 0, "error on accepted START");

    tick(1, 0, 0, 1, 1, 1, 1, 1);
    repeat (20) begin
      tick(0, 0, 0, 1, 1, 1, 1, 1);
    end
    tick(0, 1, 0, 1, 1, 1, 1, 1);
    checks += 5;
    if ((small_cycles !== 4'hF)
        || (small_compute_cycles !== 4'hF)
        || (small_mac_cycles !== 4'hF)
        || (small_dma_cycles !== 4'hF)
        || (small_stall_cycles !== 4'hF)) begin
      fail("saturation", "a counter wrapped or stopped below maximum");
    end

    repeat (3) begin
      tick(0, 0, 0, 1, 1, 1, 1, 1);
    end
    checks += 5;
    if ((small_cycles !== 4'hF)
        || (small_compute_cycles !== 4'hF)
        || (small_mac_cycles !== 4'hF)
        || (small_dma_cycles !== 4'hF)
        || (small_stall_cycles !== 4'hF)) begin
      fail("post-completion saturation", "saturated values changed");
    end

    $display("tb_perf_counters PASS (%0d self-checks)", checks);
    $finish;
  end

endmodule
