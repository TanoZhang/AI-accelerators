module apb_accel_regs #(
  parameter int unsigned APB_ADDR_W = 12,
  parameter int unsigned DIM_W      = 16
) (
  input  logic                     clk,
  input  logic                     rst_n,

  input  logic [APB_ADDR_W-1:0]    paddr,
  input  logic                     psel,
  input  logic                     penable,
  input  logic                     pwrite,
  input  logic [31:0]              pwdata,
  input  logic [3:0]               pstrb,
  output logic [31:0]              prdata,
  output logic                     pready,
  output logic                     pslverr,

  output logic                     start_pulse,
  output logic                     soft_reset_pulse,
  output logic [DIM_W-1:0]         cfg_m,
  output logic [DIM_W-1:0]         cfg_n,
  output logic [DIM_W-1:0]         cfg_k,
  output logic [31:0]              src_a_addr,
  output logic [31:0]              src_b_addr,
  output logic [31:0]              dst_addr,
  output logic                     quant_enable,
  output logic                     relu_enable,
  output logic [4:0]               quant_shift,

  input  logic                     hw_busy,
  input  logic [1:0]               int_status,
  output logic [1:0]               int_enable,
  output logic [1:0]               int_status_w1c,
  input  logic [31:0]              perf_cycles,
  input  logic [31:0]              perf_compute_cycles,
  input  logic [31:0]              perf_mac_cycles,
  input  logic [31:0]              perf_dma_cycles,
  input  logic [31:0]              perf_stall_cycles
);

  logic apb_access;
  logic valid_address;
  logic writable_address;
  logic write_transfer;
  logic config_write;
  logic clear_done;
  logic clear_error;

  function automatic logic [31:0] apply_wstrb(
    input logic [31:0] old_value,
    input logic [31:0] new_value,
    input logic [3:0]  strobes
  );
    logic [31:0] merged;
    begin
      merged = old_value;
      for (int unsigned byte_index = 0; byte_index < 4; byte_index++) begin
        if (strobes[byte_index]) begin
          merged[(byte_index * 8) +: 8] = new_value[(byte_index * 8) +: 8];
        end
      end
      return merged;
    end
  endfunction

  always_comb begin
    apb_access       = psel && penable;
    valid_address    = 1'b0;
    writable_address = 1'b0;
    prdata           = 32'd0;

    if (paddr[1:0] == 2'b00) begin
      case (paddr)
        ai_accel_pkg::CSR_CONTROL: begin
          valid_address    = 1'b1;
          writable_address = 1'b1;
        end
        ai_accel_pkg::CSR_STATUS: begin
          valid_address = 1'b1;
          prdata[0] = hw_busy;
          prdata[1] = int_status[0];
          prdata[2] = int_status[1];
        end
        ai_accel_pkg::CSR_M: begin
          valid_address    = 1'b1;
          writable_address = 1'b1;
          prdata = 32'(cfg_m);
        end
        ai_accel_pkg::CSR_N: begin
          valid_address    = 1'b1;
          writable_address = 1'b1;
          prdata = 32'(cfg_n);
        end
        ai_accel_pkg::CSR_K: begin
          valid_address    = 1'b1;
          writable_address = 1'b1;
          prdata = 32'(cfg_k);
        end
        ai_accel_pkg::CSR_SRC_A_ADDR: begin
          valid_address    = 1'b1;
          writable_address = 1'b1;
          prdata = src_a_addr;
        end
        ai_accel_pkg::CSR_SRC_B_ADDR: begin
          valid_address    = 1'b1;
          writable_address = 1'b1;
          prdata = src_b_addr;
        end
        ai_accel_pkg::CSR_DST_ADDR: begin
          valid_address    = 1'b1;
          writable_address = 1'b1;
          prdata = dst_addr;
        end
        ai_accel_pkg::CSR_QUANT_CONFIG: begin
          valid_address    = 1'b1;
          writable_address = 1'b1;
          prdata[0]   = quant_enable;
          prdata[1]   = relu_enable;
          prdata[6:2] = quant_shift;
        end
        ai_accel_pkg::CSR_INT_ENABLE: begin
          valid_address    = 1'b1;
          writable_address = 1'b1;
          prdata[1:0] = int_enable;
        end
        ai_accel_pkg::CSR_INT_STATUS: begin
          valid_address    = 1'b1;
          writable_address = 1'b1;
          prdata[1:0] = int_status;
        end
        ai_accel_pkg::CSR_PERF_CYCLES: begin
          valid_address = 1'b1;
          prdata = perf_cycles;
        end
        ai_accel_pkg::CSR_PERF_MAC_CYCLES: begin
          valid_address = 1'b1;
          prdata = perf_mac_cycles;
        end
        ai_accel_pkg::CSR_PERF_COMPUTE_CYCLES: begin
          valid_address = 1'b1;
          prdata = perf_compute_cycles;
        end
        ai_accel_pkg::CSR_PERF_DMA_CYCLES: begin
          valid_address = 1'b1;
          prdata = perf_dma_cycles;
        end
        ai_accel_pkg::CSR_PERF_STALL_CYCLES: begin
          valid_address = 1'b1;
          prdata = perf_stall_cycles;
        end
        default: begin
          valid_address = 1'b0;
        end
      endcase
    end

    pready   = 1'b1;
    pslverr  = apb_access
             && (!valid_address || (pwrite && !writable_address));

    write_transfer = apb_access && pwrite && valid_address
                   && writable_address;
    config_write = write_transfer
                && ((paddr == ai_accel_pkg::CSR_M)
                 || (paddr == ai_accel_pkg::CSR_N)
                 || (paddr == ai_accel_pkg::CSR_K)
                 || (paddr == ai_accel_pkg::CSR_SRC_A_ADDR)
                 || (paddr == ai_accel_pkg::CSR_SRC_B_ADDR)
                 || (paddr == ai_accel_pkg::CSR_DST_ADDR)
                 || (paddr == ai_accel_pkg::CSR_QUANT_CONFIG));

    clear_done = write_transfer
              && (paddr == ai_accel_pkg::CSR_INT_STATUS)
              && pstrb[0] && pwdata[0];
    clear_error = write_transfer
               && (paddr == ai_accel_pkg::CSR_INT_STATUS)
               && pstrb[0] && pwdata[1];

    int_status_w1c = {clear_error, clear_done};
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      start_pulse     <= 1'b0;
      soft_reset_pulse <= 1'b0;
      cfg_m           <= '0;
      cfg_n           <= '0;
      cfg_k           <= '0;
      src_a_addr      <= '0;
      src_b_addr      <= '0;
      dst_addr        <= '0;
      quant_enable    <= 1'b0;
      relu_enable     <= 1'b0;
      quant_shift     <= '0;
      int_enable      <= '0;
    end else begin
      start_pulse      <= 1'b0;
      soft_reset_pulse <= 1'b0;

      if (write_transfer) begin
        case (paddr)
          ai_accel_pkg::CSR_CONTROL: begin
            if (pstrb[0]) begin
              start_pulse      <= pwdata[0];
              soft_reset_pulse <= pwdata[1];
            end
          end
          ai_accel_pkg::CSR_M: begin
            cfg_m <= DIM_W'(apply_wstrb(32'(cfg_m), pwdata, pstrb));
          end
          ai_accel_pkg::CSR_N: begin
            cfg_n <= DIM_W'(apply_wstrb(32'(cfg_n), pwdata, pstrb));
          end
          ai_accel_pkg::CSR_K: begin
            cfg_k <= DIM_W'(apply_wstrb(32'(cfg_k), pwdata, pstrb));
          end
          ai_accel_pkg::CSR_SRC_A_ADDR: begin
            src_a_addr <= apply_wstrb(src_a_addr, pwdata, pstrb);
          end
          ai_accel_pkg::CSR_SRC_B_ADDR: begin
            src_b_addr <= apply_wstrb(src_b_addr, pwdata, pstrb);
          end
          ai_accel_pkg::CSR_DST_ADDR: begin
            dst_addr <= apply_wstrb(dst_addr, pwdata, pstrb);
          end
          ai_accel_pkg::CSR_QUANT_CONFIG: begin
            if (pstrb[0]) begin
              quant_enable <= pwdata[0];
              relu_enable  <= pwdata[1];
              quant_shift  <= pwdata[6:2];
            end
          end
          ai_accel_pkg::CSR_INT_ENABLE: begin
            if (pstrb[0]) begin
              int_enable <= pwdata[1:0];
            end
          end
          default: begin
          end
        endcase
      end

    end
  end

`ifndef SYNTHESIS
  property p_enable_requires_select;
    @(posedge clk) disable iff (!rst_n)
      penable |-> psel;
  endproperty

  property p_error_only_in_access;
    @(posedge clk) disable iff (!rst_n)
      pslverr |-> (psel && penable && pready);
  endproperty

  property p_start_source;
    @(posedge clk) disable iff (!rst_n)
      start_pulse |-> $past(write_transfer
                         && (paddr == ai_accel_pkg::CSR_CONTROL)
                         && pstrb[0] && pwdata[0]);
  endproperty

  property p_start_one_cycle;
    @(posedge clk) disable iff (!rst_n)
      start_pulse |=> !start_pulse;
  endproperty

  property p_soft_reset_one_cycle;
    @(posedge clk) disable iff (!rst_n)
      soft_reset_pulse |=> !soft_reset_pulse;
  endproperty

  property p_config_stable;
    @(posedge clk) disable iff (!rst_n)
      !config_write |=> $stable({cfg_m, cfg_n, cfg_k, src_a_addr,
                                 src_b_addr, dst_addr, quant_enable,
                                 relu_enable, quant_shift});
  endproperty

  property p_w1c_has_apb_source;
    @(posedge clk) disable iff (!rst_n)
      (|int_status_w1c) |-> (write_transfer
                          && (paddr == ai_accel_pkg::CSR_INT_STATUS));
  endproperty

  assert property (p_enable_requires_select)
    else $error("APB PENABLE asserted without PSEL");
  assert property (p_error_only_in_access)
    else $error("APB PSLVERR asserted outside an access phase");
  assert property (p_start_source)
    else $error("start_pulse was not caused by a CONTROL write");
  assert property (p_start_one_cycle)
    else $error("start_pulse lasted more than one cycle");
  assert property (p_soft_reset_one_cycle)
    else $error("soft_reset_pulse lasted more than one cycle");
  assert property (p_config_stable)
    else $error("configuration changed without an APB write");
  assert property (p_w1c_has_apb_source);
`endif

endmodule
