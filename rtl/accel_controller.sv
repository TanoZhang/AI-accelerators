module accel_controller #(
  parameter int unsigned DIM_W = 16
) (
  input  logic                               clk,
  input  logic                               rst_n,

  input  logic                               start,
  input  logic [DIM_W-1:0]                   cfg_m,
  input  logic [DIM_W-1:0]                   cfg_n,
  input  logic [DIM_W-1:0]                   cfg_k,
  input  logic [31:0]                        src_a_addr,
  input  logic [31:0]                        src_b_addr,
  input  logic [31:0]                        dst_addr,
  input  logic                               quant_enable,
  input  logic                               relu_enable,
  input  logic [4:0]                         quant_shift,
  output logic                               start_accepted,

  input  logic                               dma_busy,
  input  logic                               dma_done,
  input  logic                               dma_error,
  output logic                               dma_start,
  output ai_accel_pkg::dma_transfer_e        dma_direction,
  output logic [31:0]                        dma_src_addr,
  output logic [31:0]                        dma_dst_addr,
  output logic [31:0]                        dma_length_words,

  input  logic                               compute_busy,
  input  logic                               compute_done,
  input  logic                               compute_error,
  input  logic                               output_writer_busy,
  output logic                               compute_start,
  output logic [DIM_W-1:0]                   active_m,
  output logic [DIM_W-1:0]                   active_n,
  output logic [DIM_W-1:0]                   active_k,
  output logic                               active_quant_enable,
  output logic                               active_relu_enable,
  output logic [4:0]                         active_quant_shift,

  output logic                               busy,
  output logic                               done,
  output logic                               error,
  output logic                               interrupt_event,
  output ai_accel_pkg::accel_state_e         status_state,
  output ai_accel_pkg::error_code_e          error_code
);

  typedef enum logic [2:0] {
    CTRL_IDLE,
    CTRL_LOAD_A,
    CTRL_LOAD_B,
    CTRL_COMPUTE,
    CTRL_WAIT_OUTPUT,
    CTRL_STORE_OUTPUT,
    CTRL_DONE,
    CTRL_ERROR
  } state_e;

  state_e state_q;

  logic [DIM_W-1:0] m_q;
  logic [DIM_W-1:0] n_q;
  logic [DIM_W-1:0] k_q;
  logic [31:0] src_a_addr_q;
  logic [31:0] src_b_addr_q;
  logic [31:0] dst_addr_q;
  logic quant_enable_q;
  logic relu_enable_q;
  logic [4:0] quant_shift_q;
  logic [31:0] a_words_q;
  logic [31:0] b_words_q;
  logic [31:0] c_words_q;
  logic operation_issued_q;
  logic retrigger_error_q;

  logic [63:0] a_elements_full;
  logic [63:0] b_elements_full;
  logic [63:0] c_elements_full;
  logic [63:0] a_words_full;
  logic [63:0] b_words_full;
  logic dimensions_valid;
  logic addresses_valid;
  logic lengths_valid;
  logic start_config_valid;
  logic dma_state;

  always_comb begin
    a_elements_full = 64'(cfg_m) * 64'(cfg_k);
    b_elements_full = 64'(cfg_k) * 64'(cfg_n);
    c_elements_full = 64'(cfg_m) * 64'(cfg_n);
    a_words_full    = a_elements_full;
    b_words_full    = b_elements_full;

    dimensions_valid = (cfg_m != '0) && (cfg_n != '0) && (cfg_k != '0);
    addresses_valid  = (src_a_addr[1:0] == 2'b00)
                    && (src_b_addr[1:0] == 2'b00)
                    && (dst_addr[1:0] == 2'b00);
    lengths_valid = (a_words_full[63:32] == 0)
                 && (b_words_full[63:32] == 0)
                 && (c_elements_full[63:32] == 0);
    start_config_valid = dimensions_valid && addresses_valid && lengths_valid;

    dma_state = (state_q == CTRL_LOAD_A)
             || (state_q == CTRL_LOAD_B)
             || (state_q == CTRL_STORE_OUTPUT);

    busy = (state_q == CTRL_LOAD_A)
        || (state_q == CTRL_LOAD_B)
        || (state_q == CTRL_COMPUTE)
        || (state_q == CTRL_WAIT_OUTPUT)
        || (state_q == CTRL_STORE_OUTPUT);
    done  = (state_q == CTRL_DONE);
    error = (state_q == CTRL_ERROR) || retrigger_error_q;
    interrupt_event = done || error;
    start_accepted = start && (state_q == CTRL_IDLE) && start_config_valid;

    dma_start        = dma_state && !operation_issued_q && !dma_busy;
    compute_start    = (state_q == CTRL_COMPUTE)
                    && !operation_issued_q && !compute_busy;
    dma_direction    = ai_accel_pkg::DMA_MEM_TO_ACTIVATION;
    dma_src_addr     = 32'd0;
    dma_dst_addr     = 32'd0;
    dma_length_words = 32'd0;

    case (state_q)
      CTRL_LOAD_A: begin
        dma_direction    = ai_accel_pkg::DMA_MEM_TO_ACTIVATION;
        dma_src_addr     = src_a_addr_q;
        dma_dst_addr     = 32'd0;
        dma_length_words = a_words_q;
      end
      CTRL_LOAD_B: begin
        dma_direction    = ai_accel_pkg::DMA_MEM_TO_WEIGHT;
        dma_src_addr     = src_b_addr_q;
        dma_dst_addr     = 32'd0;
        dma_length_words = b_words_q;
      end
      CTRL_STORE_OUTPUT: begin
        dma_direction    = ai_accel_pkg::DMA_OUTPUT_TO_MEM;
        dma_src_addr     = 32'd0;
        dma_dst_addr     = dst_addr_q;
        dma_length_words = c_words_q;
      end
      default: begin
      end
    endcase

    active_m            = m_q;
    active_n            = n_q;
    active_k            = k_q;
    active_quant_enable = quant_enable_q;
    active_relu_enable  = relu_enable_q;
    active_quant_shift  = quant_shift_q;

    case (state_q)
      CTRL_IDLE:         status_state = ai_accel_pkg::ACCEL_IDLE;
      CTRL_LOAD_A,
      CTRL_LOAD_B:       status_state = ai_accel_pkg::ACCEL_LOAD;
      CTRL_COMPUTE:      status_state = ai_accel_pkg::ACCEL_COMPUTE;
      CTRL_WAIT_OUTPUT:  status_state = ai_accel_pkg::ACCEL_CAPTURE;
      CTRL_STORE_OUTPUT: status_state = ai_accel_pkg::ACCEL_WRITEBACK;
      CTRL_DONE:         status_state = ai_accel_pkg::ACCEL_DONE;
      default:           status_state = ai_accel_pkg::ACCEL_ERROR;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q             <= CTRL_IDLE;
      m_q                 <= '0;
      n_q                 <= '0;
      k_q                 <= '0;
      src_a_addr_q        <= '0;
      src_b_addr_q        <= '0;
      dst_addr_q          <= '0;
      quant_enable_q      <= 1'b0;
      relu_enable_q       <= 1'b0;
      quant_shift_q       <= '0;
      a_words_q           <= '0;
      b_words_q           <= '0;
      c_words_q           <= '0;
      operation_issued_q  <= 1'b0;
      retrigger_error_q   <= 1'b0;
      error_code          <= ai_accel_pkg::ERR_NONE;
    end else begin
      retrigger_error_q <= 1'b0;

      if (start && (state_q != CTRL_IDLE)) begin
        retrigger_error_q <= 1'b1;
        error_code        <= ai_accel_pkg::ERR_START_BUSY;
      end

      case (state_q)
        CTRL_IDLE: begin
          operation_issued_q <= 1'b0;
          if (start) begin
            if (!dimensions_valid || !lengths_valid) begin
              error_code <= ai_accel_pkg::ERR_INVALID_DIM;
              state_q    <= CTRL_ERROR;
            end else if (!addresses_valid) begin
              error_code <= ai_accel_pkg::ERR_ADDR_ALIGN;
              state_q    <= CTRL_ERROR;
            end else begin
              m_q            <= cfg_m;
              n_q            <= cfg_n;
              k_q            <= cfg_k;
              src_a_addr_q   <= src_a_addr;
              src_b_addr_q   <= src_b_addr;
              dst_addr_q     <= dst_addr;
              quant_enable_q <= quant_enable;
              relu_enable_q  <= relu_enable;
              quant_shift_q  <= quant_shift;
              a_words_q      <= a_words_full[31:0];
              b_words_q      <= b_words_full[31:0];
              c_words_q      <= c_elements_full[31:0];
              error_code     <= ai_accel_pkg::ERR_NONE;
              state_q        <= CTRL_LOAD_A;
            end
          end
        end

        CTRL_LOAD_A: begin
          if (dma_start) begin
            operation_issued_q <= 1'b1;
          end else if (operation_issued_q && dma_error) begin
            operation_issued_q <= 1'b0;
            error_code         <= ai_accel_pkg::ERR_DMA_READ;
            state_q            <= CTRL_ERROR;
          end else if (operation_issued_q && dma_done) begin
            operation_issued_q <= 1'b0;
            state_q            <= CTRL_LOAD_B;
          end
        end

        CTRL_LOAD_B: begin
          if (dma_start) begin
            operation_issued_q <= 1'b1;
          end else if (operation_issued_q && dma_error) begin
            operation_issued_q <= 1'b0;
            error_code         <= ai_accel_pkg::ERR_DMA_READ;
            state_q            <= CTRL_ERROR;
          end else if (operation_issued_q && dma_done) begin
            operation_issued_q <= 1'b0;
            state_q            <= CTRL_COMPUTE;
          end
        end

        CTRL_COMPUTE: begin
          if (compute_start) begin
            operation_issued_q <= 1'b1;
          end else if (operation_issued_q && compute_error) begin
            operation_issued_q <= 1'b0;
            error_code         <= ai_accel_pkg::ERR_INTERNAL;
            state_q            <= CTRL_ERROR;
          end else if (operation_issued_q && compute_done) begin
            operation_issued_q <= 1'b0;
            state_q            <= CTRL_WAIT_OUTPUT;
          end
        end

        CTRL_WAIT_OUTPUT: begin
          if (!output_writer_busy) begin
            state_q <= CTRL_STORE_OUTPUT;
          end
        end

        CTRL_STORE_OUTPUT: begin
          if (dma_start) begin
            operation_issued_q <= 1'b1;
          end else if (operation_issued_q && dma_error) begin
            operation_issued_q <= 1'b0;
            error_code         <= ai_accel_pkg::ERR_DMA_WRITE;
            state_q            <= CTRL_ERROR;
          end else if (operation_issued_q && dma_done) begin
            operation_issued_q <= 1'b0;
            state_q            <= CTRL_DONE;
          end
        end

        CTRL_DONE: begin
          state_q <= CTRL_IDLE;
        end

        CTRL_ERROR: begin
          state_q <= CTRL_IDLE;
        end

        default: begin
          operation_issued_q <= 1'b0;
          error_code         <= ai_accel_pkg::ERR_INTERNAL;
          state_q            <= CTRL_ERROR;
        end
      endcase
    end
  end

`ifndef SYNTHESIS
  property p_valid_start_becomes_busy;
    @(posedge clk) disable iff (!rst_n)
      (start && (state_q == CTRL_IDLE) && start_config_valid) |=> busy;
  endproperty

  property p_active_config_stable;
    @(posedge clk) disable iff (!rst_n)
      busy |=> $stable({m_q, n_q, k_q, src_a_addr_q, src_b_addr_q,
                        dst_addr_q, quant_enable_q, relu_enable_q,
                        quant_shift_q, a_words_q, b_words_q, c_words_q});
  endproperty

  property p_dma_start_is_legal;
    @(posedge clk) disable iff (!rst_n)
      dma_start |-> (dma_state && !dma_busy && !operation_issued_q);
  endproperty

  property p_compute_start_is_legal;
    @(posedge clk) disable iff (!rst_n)
      compute_start |-> ((state_q == CTRL_COMPUTE)
                      && !compute_busy && !operation_issued_q);
  endproperty

  property p_dma_start_one_cycle;
    @(posedge clk) disable iff (!rst_n)
      dma_start |=> !dma_start;
  endproperty

  property p_compute_start_one_cycle;
    @(posedge clk) disable iff (!rst_n)
      compute_start |=> !compute_start;
  endproperty

  property p_done_one_cycle;
    @(posedge clk) disable iff (!rst_n)
      done |=> !done;
  endproperty

  property p_idle_transition;
    @(posedge clk) disable iff (!rst_n)
      (state_q == CTRL_IDLE)
      |=> (state_q inside {CTRL_IDLE, CTRL_LOAD_A, CTRL_ERROR});
  endproperty

  property p_load_a_transition;
    @(posedge clk) disable iff (!rst_n)
      (state_q == CTRL_LOAD_A)
      |=> (state_q inside {CTRL_LOAD_A, CTRL_LOAD_B, CTRL_ERROR});
  endproperty

  property p_load_b_transition;
    @(posedge clk) disable iff (!rst_n)
      (state_q == CTRL_LOAD_B)
      |=> (state_q inside {CTRL_LOAD_B, CTRL_COMPUTE, CTRL_ERROR});
  endproperty

  property p_compute_transition;
    @(posedge clk) disable iff (!rst_n)
      (state_q == CTRL_COMPUTE)
      |=> (state_q inside {CTRL_COMPUTE, CTRL_WAIT_OUTPUT, CTRL_ERROR});
  endproperty

  property p_wait_output_transition;
    @(posedge clk) disable iff (!rst_n)
      (state_q == CTRL_WAIT_OUTPUT)
      |=> (state_q inside {CTRL_WAIT_OUTPUT, CTRL_STORE_OUTPUT, CTRL_ERROR});
  endproperty

  property p_store_transition;
    @(posedge clk) disable iff (!rst_n)
      (state_q == CTRL_STORE_OUTPUT)
      |=> (state_q inside {CTRL_STORE_OUTPUT, CTRL_DONE, CTRL_ERROR});
  endproperty

  property p_terminal_transition;
    @(posedge clk) disable iff (!rst_n)
      (state_q inside {CTRL_DONE, CTRL_ERROR}) |=> (state_q == CTRL_IDLE);
  endproperty

  property p_load_a_completion_required;
    @(posedge clk) disable iff (!rst_n)
      (state_q == CTRL_LOAD_B && $past(state_q) == CTRL_LOAD_A)
      |-> $past(operation_issued_q && dma_done);
  endproperty

  property p_load_b_completion_required;
    @(posedge clk) disable iff (!rst_n)
      (state_q == CTRL_COMPUTE && $past(state_q) == CTRL_LOAD_B)
      |-> $past(operation_issued_q && dma_done);
  endproperty

  property p_store_completion_required;
    @(posedge clk) disable iff (!rst_n)
      (state_q == CTRL_DONE && $past(state_q) == CTRL_STORE_OUTPUT)
      |-> $past(operation_issued_q && dma_done);
  endproperty

  property p_compute_completion_required;
    @(posedge clk) disable iff (!rst_n)
      (state_q == CTRL_WAIT_OUTPUT && $past(state_q) == CTRL_COMPUTE)
      |-> $past(operation_issued_q && compute_done);
  endproperty

  property p_dma_error_transition_has_cause;
    @(posedge clk) disable iff (!rst_n)
      ((state_q == CTRL_ERROR)
       && ($past(state_q) inside {CTRL_LOAD_A, CTRL_LOAD_B,
                                  CTRL_STORE_OUTPUT}))
      |-> $past(operation_issued_q && dma_error);
  endproperty

  property p_compute_error_transition_has_cause;
    @(posedge clk) disable iff (!rst_n)
      ((state_q == CTRL_ERROR) && ($past(state_q) == CTRL_COMPUTE))
      |-> $past(operation_issued_q && compute_error);
  endproperty

  property p_no_overlapping_commands;
    @(posedge clk) disable iff (!rst_n)
      !(dma_start && compute_start);
  endproperty

  property p_dma_completion_requires_command;
    @(posedge clk) disable iff (!rst_n)
      (dma_state && (dma_done || dma_error)) |-> operation_issued_q;
  endproperty

  property p_compute_completion_requires_command;
    @(posedge clk) disable iff (!rst_n)
      ((state_q == CTRL_COMPUTE) && (compute_done || compute_error))
      |-> operation_issued_q;
  endproperty

  assert property (p_valid_start_becomes_busy);
  assert property (p_active_config_stable)
    else $error("accel_controller active configuration changed while busy");
  assert property (p_dma_start_is_legal)
    else $error("accel_controller issued an illegal DMA command");
  assert property (p_compute_start_is_legal)
    else $error("accel_controller issued an illegal compute command");
  assert property (p_dma_start_one_cycle);
  assert property (p_compute_start_one_cycle);
  assert property (p_done_one_cycle);
  assert property (p_idle_transition);
  assert property (p_load_a_transition);
  assert property (p_load_b_transition);
  assert property (p_compute_transition);
  assert property (p_wait_output_transition);
  assert property (p_store_transition);
  assert property (p_terminal_transition);
  assert property (p_load_a_completion_required);
  assert property (p_load_b_completion_required);
  assert property (p_store_completion_required);
  assert property (p_compute_completion_required);
  assert property (p_dma_error_transition_has_cause);
  assert property (p_compute_error_transition_has_cause);
  assert property (p_no_overlapping_commands);
  assert property (p_dma_completion_requires_command);
  assert property (p_compute_completion_requires_command);
`endif

endmodule
