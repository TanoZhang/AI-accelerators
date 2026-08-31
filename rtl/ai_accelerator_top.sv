module ai_accelerator_top #(
  parameter int unsigned APB_ADDR_W = 12,
  parameter int unsigned DIM_W      = 16,
  parameter int unsigned DATA_W     = 8,
  parameter int unsigned ACC_W      = 32,
  parameter int unsigned ARRAY_DIM  = 4,
  parameter bit          USE_PARALLEL_FEEDER = 1'b1,
  parameter int unsigned SPAD_DEPTH = 1024,
  parameter int unsigned SPAD_ADDR_W = (SPAD_DEPTH > 1)
                                     ? $clog2(SPAD_DEPTH) : 1
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

  output logic                     mem_req_valid,
  input  logic                     mem_req_ready,
  output logic                     mem_req_write,
  output logic [31:0]              mem_req_addr,
  output logic [31:0]              mem_req_wdata,
  output logic [3:0]               mem_req_wstrb,
  input  logic                     mem_rsp_valid,
  output logic                     mem_rsp_ready,
  input  logic [31:0]              mem_rsp_rdata,
  input  logic                     mem_rsp_error,

  output logic                     irq
);

  logic core_rst_n;

  logic start_pulse;
  logic soft_reset_pulse;
  logic [DIM_W-1:0] cfg_m;
  logic [DIM_W-1:0] cfg_n;
  logic [DIM_W-1:0] cfg_k;
  logic [31:0] src_a_addr;
  logic [31:0] src_b_addr;
  logic [31:0] dst_addr;
  logic quant_enable;
  logic relu_enable;
  logic [4:0] quant_shift;
  logic [1:0] int_enable;
  logic [1:0] int_status;
  logic [1:0] int_status_w1c;

  logic accel_start_accepted;
  logic accel_busy;
  logic accel_done;
  logic accel_error;
  logic accel_interrupt_event;
  ai_accel_pkg::accel_state_e accel_state;
  ai_accel_pkg::error_code_e accel_error_code;

  logic dma_start;
  ai_accel_pkg::dma_transfer_e dma_direction;
  logic [31:0] dma_src_addr;
  logic [31:0] dma_dst_addr;
  logic [31:0] dma_length_words;
  logic dma_busy;
  logic dma_done;
  logic dma_error;

  logic compute_start;
  logic compute_start_ready;
  logic compute_busy;
  logic compute_done;
  logic compute_error;
  logic [DIM_W-1:0] active_m;
  logic [DIM_W-1:0] active_n;
  logic [DIM_W-1:0] active_k;
  logic active_quant_enable;
  logic active_relu_enable;
  logic [4:0] active_quant_shift;

  logic activation_write_en;
  logic [SPAD_ADDR_W-1:0] activation_write_addr;
  logic [31:0] activation_write_data;
  logic [ARRAY_DIM-1:0] activation_read_en;
  logic [SPAD_ADDR_W-1:0] activation_read_addr [0:ARRAY_DIM-1];
  logic [DATA_W-1:0] activation_read_data [0:ARRAY_DIM-1];
  logic [ARRAY_DIM-1:0] activation_read_valid;

  logic weight_write_en;
  logic [SPAD_ADDR_W-1:0] weight_write_addr;
  logic [31:0] weight_write_data;
  logic [ARRAY_DIM-1:0] weight_read_en;
  logic [SPAD_ADDR_W-1:0] weight_read_addr [0:ARRAY_DIM-1];
  logic [DATA_W-1:0] weight_read_data [0:ARRAY_DIM-1];
  logic [ARRAY_DIM-1:0] weight_read_valid;

  logic output_read_en;
  logic [SPAD_ADDR_W-1:0] output_read_addr;
  logic [31:0] output_read_data;
  logic output_read_valid;
  logic output_write_en;
  logic [SPAD_ADDR_W-1:0] output_write_addr;
  logic [31:0] output_write_data;

  logic feeder_start;
  logic feeder_busy;
  logic feeder_done;
  logic feeder_compute_valid;
  logic feeder_compute_ready;
  logic feeder_last_k;
  logic signed [DATA_W-1:0] a_vec [0:ARRAY_DIM-1];
  logic signed [DATA_W-1:0] b_vec [0:ARRAY_DIM-1];
  logic [ARRAY_DIM-1:0] feeder_row_mask;
  logic [ARRAY_DIM-1:0] feeder_col_mask;

  logic clear_acc;
  logic mac_en;
  logic signed [ACC_W-1:0] mac_acc [0:ARRAY_DIM-1][0:ARRAY_DIM-1];
  logic [DIM_W-1:0] compute_tile_row;
  logic [DIM_W-1:0] compute_tile_col;
  logic [DIM_W-1:0] compute_k_index;
  logic [DIM_W-1:0] compute_active_m;
  logic [DIM_W-1:0] compute_active_n;
  logic [DIM_W-1:0] compute_active_k;
  logic compute_output_valid;
  logic compute_output_ready;
  logic signed [ACC_W-1:0] compute_output_data [0:ARRAY_DIM-1]
                                                       [0:ARRAY_DIM-1];
  logic [ARRAY_DIM-1:0] compute_row_mask;
  logic [ARRAY_DIM-1:0] compute_col_mask;

  logic output_writer_busy;
  logic output_tile_done;

  logic done_status;
  logic error_status;
  logic non_dma_error_event;

  logic [31:0] perf_cycles;
  logic [31:0] perf_compute_cycles;
  logic [31:0] perf_mac_cycles;
  logic [31:0] perf_dma_cycles;
  logic [31:0] perf_stall_cycles;
  logic compute_stall;
  logic dma_stall;

  assign core_rst_n = rst_n && !soft_reset_pulse;
  assign compute_stall = feeder_compute_valid && !feeder_compute_ready;
  assign dma_stall = mem_req_valid && !mem_req_ready;
  assign non_dma_error_event = accel_error
                            && (accel_error_code != ai_accel_pkg::ERR_DMA_READ)
                            && (accel_error_code != ai_accel_pkg::ERR_DMA_WRITE);

  apb_accel_regs #(
    .APB_ADDR_W (APB_ADDR_W),
    .DIM_W      (DIM_W)
  ) u_apb_accel_regs (
    .clk                 (clk),
    .rst_n               (rst_n),
    .paddr               (paddr),
    .psel                (psel),
    .penable             (penable),
    .pwrite              (pwrite),
    .pwdata              (pwdata),
    .pstrb               (pstrb),
    .prdata              (prdata),
    .pready              (pready),
    .pslverr             (pslverr),
    .start_pulse         (start_pulse),
    .soft_reset_pulse    (soft_reset_pulse),
    .cfg_m               (cfg_m),
    .cfg_n               (cfg_n),
    .cfg_k               (cfg_k),
    .src_a_addr          (src_a_addr),
    .src_b_addr          (src_b_addr),
    .dst_addr            (dst_addr),
    .quant_enable        (quant_enable),
    .relu_enable         (relu_enable),
    .quant_shift         (quant_shift),
    .hw_busy             (accel_busy),
    .int_status          (int_status),
    .int_enable          (int_enable),
    .int_status_w1c      (int_status_w1c),
    .perf_cycles         (perf_cycles),
    .perf_compute_cycles (perf_compute_cycles),
    .perf_mac_cycles     (perf_mac_cycles),
    .perf_dma_cycles     (perf_dma_cycles),
    .perf_stall_cycles   (perf_stall_cycles)
  );

  accel_controller #(
    .DIM_W (DIM_W)
  ) u_accel_controller (
    .clk                 (clk),
    .rst_n               (core_rst_n),
    .start               (start_pulse),
    .cfg_m               (cfg_m),
    .cfg_n               (cfg_n),
    .cfg_k               (cfg_k),
    .src_a_addr          (src_a_addr),
    .src_b_addr          (src_b_addr),
    .dst_addr            (dst_addr),
    .quant_enable        (quant_enable),
    .relu_enable         (relu_enable),
    .quant_shift         (quant_shift),
    .start_accepted      (accel_start_accepted),
    .dma_busy            (dma_busy),
    .dma_done            (dma_done),
    .dma_error           (dma_error),
    .dma_start           (dma_start),
    .dma_direction       (dma_direction),
    .dma_src_addr        (dma_src_addr),
    .dma_dst_addr        (dma_dst_addr),
    .dma_length_words    (dma_length_words),
    .compute_busy        (compute_busy),
    .compute_done        (compute_done),
    .compute_error       (compute_error),
    .output_writer_busy  (output_writer_busy),
    .compute_start       (compute_start),
    .active_m            (active_m),
    .active_n            (active_n),
    .active_k            (active_k),
    .active_quant_enable (active_quant_enable),
    .active_relu_enable  (active_relu_enable),
    .active_quant_shift  (active_quant_shift),
    .busy                (accel_busy),
    .done                (accel_done),
    .error               (accel_error),
    .interrupt_event     (accel_interrupt_event),
    .status_state        (accel_state),
    .error_code          (accel_error_code)
  );

  simple_dma #(
    .SPAD_DEPTH  (SPAD_DEPTH),
    .SPAD_ADDR_W (SPAD_ADDR_W)
  ) u_simple_dma (
    .clk                   (clk),
    .rst_n                 (core_rst_n),
    .start                 (dma_start),
    .direction             (dma_direction),
    .src_addr              (dma_src_addr),
    .dst_addr              (dma_dst_addr),
    .length_words          (dma_length_words),
    .busy                  (dma_busy),
    .done                  (dma_done),
    .error                 (dma_error),
    .mem_req_valid         (mem_req_valid),
    .mem_req_ready         (mem_req_ready),
    .mem_req_write         (mem_req_write),
    .mem_req_addr          (mem_req_addr),
    .mem_req_wdata         (mem_req_wdata),
    .mem_req_wstrb         (mem_req_wstrb),
    .mem_rsp_valid         (mem_rsp_valid),
    .mem_rsp_ready         (mem_rsp_ready),
    .mem_rsp_rdata         (mem_rsp_rdata),
    .mem_rsp_error         (mem_rsp_error),
    .activation_write_en   (activation_write_en),
    .activation_write_addr (activation_write_addr),
    .activation_write_data (activation_write_data),
    .weight_write_en       (weight_write_en),
    .weight_write_addr     (weight_write_addr),
    .weight_write_data     (weight_write_data),
    .output_read_en        (output_read_en),
    .output_read_addr      (output_read_addr),
    .output_read_valid     (output_read_valid),
    .output_read_data      (output_read_data)
  );

  multi_read_scratchpad #(
    .DATA_W     (DATA_W),
    .DEPTH      (SPAD_DEPTH),
    .READ_PORTS (ARRAY_DIM),
    .ADDR_W     (SPAD_ADDR_W)
  ) u_activation_sram (
    .clk        (clk),
    .rst_n      (core_rst_n),
    .read_en    (activation_read_en),
    .read_addr  (activation_read_addr),
    .read_data  (activation_read_data),
    .read_valid (activation_read_valid),
    .write_en   (activation_write_en),
    .write_addr (activation_write_addr),
    .write_data (activation_write_data[DATA_W-1:0])
  );

  multi_read_scratchpad #(
    .DATA_W     (DATA_W),
    .DEPTH      (SPAD_DEPTH),
    .READ_PORTS (ARRAY_DIM),
    .ADDR_W     (SPAD_ADDR_W)
  ) u_weight_sram (
    .clk        (clk),
    .rst_n      (core_rst_n),
    .read_en    (weight_read_en),
    .read_addr  (weight_read_addr),
    .read_data  (weight_read_data),
    .read_valid (weight_read_valid),
    .write_en   (weight_write_en),
    .write_addr (weight_write_addr),
    .write_data (weight_write_data[DATA_W-1:0])
  );

  generate
    if (USE_PARALLEL_FEEDER) begin : gen_parallel_feeder
      parallel_operand_feeder #(
        .DATA_W      (DATA_W),
        .DIM_W       (DIM_W),
        .ARRAY_DIM   (ARRAY_DIM),
        .SPAD_DEPTH  (SPAD_DEPTH),
        .SPAD_ADDR_W (SPAD_ADDR_W)
      ) u_operand_feeder (
        .clk                   (clk),
        .rst_n                 (core_rst_n),
        .start_pulse           (feeder_start),
        .m_dim                 (active_m),
        .n_dim                 (active_n),
        .k_dim                 (active_k),
        .tile_row              (compute_tile_row),
        .tile_col              (compute_tile_col),
        .busy                  (feeder_busy),
        .done_pulse            (feeder_done),
        .activation_read_en    (activation_read_en),
        .activation_read_addr  (activation_read_addr),
        .activation_read_valid (activation_read_valid),
        .activation_read_data  (activation_read_data),
        .weight_read_en        (weight_read_en),
        .weight_read_addr      (weight_read_addr),
        .weight_read_valid     (weight_read_valid),
        .weight_read_data      (weight_read_data),
        .compute_valid         (feeder_compute_valid),
        .compute_ready         (feeder_compute_ready),
        .a_vec                 (a_vec),
        .b_vec                 (b_vec),
        .row_mask              (feeder_row_mask),
        .col_mask              (feeder_col_mask),
        .last_k                (feeder_last_k)
      );
    end else begin : gen_scalar_feeder
      logic scalar_activation_read_en;
      logic [SPAD_ADDR_W-1:0] scalar_activation_read_addr;
      logic scalar_weight_read_en;
      logic [SPAD_ADDR_W-1:0] scalar_weight_read_addr;

      // The baseline uses port zero only. DMA, memories, and the MAC array stay
      // unchanged so the comparison isolates operand delivery.
      always_comb begin
        activation_read_en = '0;
        weight_read_en     = '0;
        for (int unsigned lane = 0; lane < ARRAY_DIM; lane++) begin
          activation_read_addr[lane] = '0;
          weight_read_addr[lane]     = '0;
        end
        activation_read_en[0]   = scalar_activation_read_en;
        activation_read_addr[0] = scalar_activation_read_addr;
        weight_read_en[0]       = scalar_weight_read_en;
        weight_read_addr[0]     = scalar_weight_read_addr;
      end

      operand_feeder #(
        .DATA_W      (DATA_W),
        .DIM_W       (DIM_W),
        .ARRAY_DIM   (ARRAY_DIM),
        .SPAD_DEPTH  (SPAD_DEPTH),
        .SPAD_ADDR_W (SPAD_ADDR_W)
      ) u_operand_feeder (
        .clk                   (clk),
        .rst_n                 (core_rst_n),
        .start_pulse           (feeder_start),
        .m_dim                 (active_m),
        .n_dim                 (active_n),
        .k_dim                 (active_k),
        .tile_row              (compute_tile_row),
        .tile_col              (compute_tile_col),
        .busy                  (feeder_busy),
        .done_pulse            (feeder_done),
        .activation_read_en    (scalar_activation_read_en),
        .activation_read_addr  (scalar_activation_read_addr),
        .activation_read_valid (activation_read_valid[0]),
        .activation_read_data  (activation_read_data[0]),
        .weight_read_en        (scalar_weight_read_en),
        .weight_read_addr      (scalar_weight_read_addr),
        .weight_read_valid     (weight_read_valid[0]),
        .weight_read_data      (weight_read_data[0]),
        .compute_valid         (feeder_compute_valid),
        .compute_ready         (feeder_compute_ready),
        .a_vec                 (a_vec),
        .b_vec                 (b_vec),
        .row_mask              (feeder_row_mask),
        .col_mask              (feeder_col_mask),
        .last_k                (feeder_last_k)
      );
    end
  endgenerate

  compute_controller #(
    .DIM_W     (DIM_W),
    .ACC_W     (ACC_W),
    .ARRAY_DIM (ARRAY_DIM)
  ) u_compute_controller (
    .clk                (clk),
    .rst_n              (core_rst_n),
    .start              (compute_start),
    .m_dim              (active_m),
    .n_dim              (active_n),
    .k_dim              (active_k),
    .start_ready        (compute_start_ready),
    .busy               (compute_busy),
    .done               (compute_done),
    .error              (compute_error),
    .feeder_start_pulse (feeder_start),
    .active_m           (compute_active_m),
    .active_n           (compute_active_n),
    .active_k           (compute_active_k),
    .tile_row           (compute_tile_row),
    .tile_col           (compute_tile_col),
    .k_index            (compute_k_index),
    .operand_valid      (feeder_compute_valid),
    .operand_ready      (feeder_compute_ready),
    .clear_acc          (clear_acc),
    .mac_en             (mac_en),
    .mac_acc            (mac_acc),
    .output_valid       (compute_output_valid),
    .output_ready       (compute_output_ready),
    .output_data        (compute_output_data),
    .row_mask           (compute_row_mask),
    .col_mask           (compute_col_mask)
  );

  mac_array_4x4 #(
    .DATA_W    (DATA_W),
    .ACC_W     (ACC_W),
    .ARRAY_DIM (ARRAY_DIM)
  ) u_mac_array_4x4 (
    .clk       (clk),
    .rst_n     (core_rst_n),
    .clear_acc (clear_acc),
    .mac_en    (mac_en),
    .a_vec     (a_vec),
    .b_vec     (b_vec),
    .acc       (mac_acc)
  );

  output_tile_writer #(
    .DIM_W       (DIM_W),
    .ARRAY_DIM   (ARRAY_DIM),
    .SPAD_DEPTH  (SPAD_DEPTH),
    .SPAD_ADDR_W (SPAD_ADDR_W)
  ) u_output_tile_writer (
    .clk          (clk),
    .rst_n        (core_rst_n),
    .tile_valid   (compute_output_valid),
    .tile_ready   (compute_output_ready),
    .tile_data    (compute_output_data),
    .tile_row     (compute_tile_row),
    .tile_col     (compute_tile_col),
    .row_mask     (compute_row_mask),
    .col_mask     (compute_col_mask),
    .m_dim        (active_m),
    .n_dim        (active_n),
    .quant_enable (active_quant_enable),
    .relu_enable  (active_relu_enable),
    .quant_shift  (active_quant_shift),
    .sram_wr_en   (output_write_en),
    .sram_wr_addr (output_write_addr),
    .sram_wr_data (output_write_data),
    .busy         (output_writer_busy),
    .tile_done    (output_tile_done)
  );

  scratchpad_sram #(
    .DATA_W (32),
    .DEPTH  (SPAD_DEPTH),
    .ADDR_W (SPAD_ADDR_W)
  ) u_output_sram (
    .clk        (clk),
    .rst_n      (core_rst_n),
    .read_en    (output_read_en),
    .read_addr  (output_read_addr),
    .read_data  (output_read_data),
    .read_valid (output_read_valid),
    .write_en   (output_write_en),
    .write_addr (output_write_addr),
    .write_data (output_write_data)
  );

  accel_status_irq u_accel_status_irq (
    .clk                        (clk),
    .rst_n                      (rst_n),
    .done_event                 (accel_done),
    .dma_error_event            (dma_error),
    .compute_config_error_event (non_dma_error_event),
    .int_enable                 (int_enable),
    .w1c_clear                  (int_status_w1c),
    .done_status                (done_status),
    .error_status               (error_status),
    .int_status                 (int_status),
    .irq                        (irq)
  );

  perf_counters u_perf_counters (
    .clk                 (clk),
    .rst_n               (core_rst_n),
    .start_accepted      (accel_start_accepted),
    .done_event          (accel_done),
    .error_event         (accel_error),
    .compute_active      (compute_busy),
    .mac_en              (mac_en),
    .dma_active          (dma_busy),
    .compute_stall       (compute_stall),
    .dma_stall           (dma_stall),
    .perf_cycles         (perf_cycles),
    .perf_compute_cycles (perf_compute_cycles),
    .perf_mac_cycles     (perf_mac_cycles),
    .perf_dma_cycles     (perf_dma_cycles),
    .perf_stall_cycles   (perf_stall_cycles)
  );

`ifndef SYNTHESIS
  property p_compute_output_handshake_connected;
    @(posedge clk) disable iff (!core_rst_n)
      compute_output_valid |-> (compute_output_ready == !output_writer_busy);
  endproperty

  property p_output_dma_waits_for_writer;
    @(posedge clk) disable iff (!core_rst_n)
      output_read_en |-> !output_writer_busy;
  endproperty

  property p_no_dual_operand_write;
    @(posedge clk) disable iff (!core_rst_n)
      !(activation_write_en && weight_write_en);
  endproperty

  assert property (p_compute_output_handshake_connected);
  assert property (p_output_dma_waits_for_writer);
  assert property (p_no_dual_operand_write);
`endif

endmodule
