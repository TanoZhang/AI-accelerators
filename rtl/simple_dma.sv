// Single-outstanding-transaction DMA for 32-bit scratchpad words.
// System-memory addresses are bytes; scratchpad addresses are word indices.
module simple_dma #(
  parameter int unsigned SPAD_DEPTH  = 1024,
  parameter int unsigned SPAD_ADDR_W = (SPAD_DEPTH > 1) ? $clog2(SPAD_DEPTH) : 1
) (
  input  logic                              clk,
  input  logic                              rst_n,

  input  logic                              start,
  input  ai_accel_pkg::dma_transfer_e       direction,
  input  logic [31:0]                       src_addr,
  input  logic [31:0]                       dst_addr,
  input  logic [31:0]                       length_words,
  output logic                              busy,
  output logic                              done,
  output logic                              error,

  output logic                              mem_req_valid,
  input  logic                              mem_req_ready,
  output logic                              mem_req_write,
  output logic [31:0]                       mem_req_addr,
  output logic [31:0]                       mem_req_wdata,
  output logic [3:0]                        mem_req_wstrb,
  input  logic                              mem_rsp_valid,
  output logic                              mem_rsp_ready,
  input  logic [31:0]                       mem_rsp_rdata,
  input  logic                              mem_rsp_error,

  output logic                              activation_write_en,
  output logic [SPAD_ADDR_W-1:0]            activation_write_addr,
  output logic [31:0]                       activation_write_data,
  output logic                              weight_write_en,
  output logic [SPAD_ADDR_W-1:0]            weight_write_addr,
  output logic [31:0]                       weight_write_data,

  output logic                              output_read_en,
  output logic [SPAD_ADDR_W-1:0]            output_read_addr,
  input  logic                              output_read_valid,
  input  logic [31:0]                       output_read_data
);

  typedef enum logic [2:0] {
    DMA_IDLE,
    DMA_LOAD_REQUEST,
    DMA_LOAD_RESPONSE,
    DMA_OUTPUT_REQUEST,
    DMA_OUTPUT_RESPONSE,
    DMA_STORE_REQUEST,
    DMA_STORE_RESPONSE
  } dma_state_e;

  dma_state_e state_q;

  ai_accel_pkg::dma_transfer_e direction_q;
  logic [31:0] length_q;
  logic [32:0] words_completed_q;
  logic [31:0] memory_addr_q;
  logic [31:0] scratchpad_addr_q;
  logic [31:0] store_data_q;

  logic direction_valid;
  logic config_valid;
  logic [33:0] memory_base_full;
  logic [33:0] transfer_byte_offset;
  logic [33:0] last_memory_addr;
  logic [32:0] scratchpad_base_full;
  logic [32:0] last_scratchpad_addr;
  logic successful_response;
  logic final_response;
  logic zero_length_start;

  always_comb begin
    direction_valid = (direction == ai_accel_pkg::DMA_MEM_TO_ACTIVATION)
                   || (direction == ai_accel_pkg::DMA_MEM_TO_WEIGHT)
                   || (direction == ai_accel_pkg::DMA_OUTPUT_TO_MEM);

    if (direction == ai_accel_pkg::DMA_OUTPUT_TO_MEM) begin
      memory_base_full     = {2'b0, dst_addr};
      scratchpad_base_full = {1'b0, src_addr};
    end else begin
      memory_base_full     = {2'b0, src_addr};
      scratchpad_base_full = {1'b0, dst_addr};
    end

    if (length_words == 0) begin
      transfer_byte_offset = '0;
      last_memory_addr     = memory_base_full;
      last_scratchpad_addr = scratchpad_base_full;
    end else begin
      transfer_byte_offset = ({2'b0, length_words} - 1'b1) << 2;
      last_memory_addr = memory_base_full + transfer_byte_offset;
      last_scratchpad_addr = scratchpad_base_full
                           + ({1'b0, length_words} - 1'b1);
    end

    config_valid = direction_valid
                && (memory_base_full[1:0] == 2'b00)
                && (last_memory_addr < 34'h1_0000_0000)
                && (last_scratchpad_addr < SPAD_DEPTH);

    busy  = (state_q != DMA_IDLE);

    mem_req_valid = (state_q == DMA_LOAD_REQUEST)
                 || (state_q == DMA_STORE_REQUEST);
    mem_req_write = (state_q == DMA_STORE_REQUEST);
    mem_req_addr  = memory_addr_q;
    mem_req_wdata = store_data_q;
    mem_req_wstrb = mem_req_write ? 4'hF : 4'h0;
    mem_rsp_ready = (state_q == DMA_LOAD_RESPONSE)
                 || (state_q == DMA_STORE_RESPONSE);

    activation_write_en = (state_q == DMA_LOAD_RESPONSE)
                       && mem_rsp_valid && mem_rsp_ready && !mem_rsp_error
                       && (direction_q == ai_accel_pkg::DMA_MEM_TO_ACTIVATION);
    activation_write_addr = scratchpad_addr_q[SPAD_ADDR_W-1:0];
    activation_write_data = mem_rsp_rdata;

    weight_write_en = (state_q == DMA_LOAD_RESPONSE)
                   && mem_rsp_valid && mem_rsp_ready && !mem_rsp_error
                   && (direction_q == ai_accel_pkg::DMA_MEM_TO_WEIGHT);
    weight_write_addr = scratchpad_addr_q[SPAD_ADDR_W-1:0];
    weight_write_data = mem_rsp_rdata;

    output_read_en   = (state_q == DMA_OUTPUT_REQUEST);
    output_read_addr = scratchpad_addr_q[SPAD_ADDR_W-1:0];

    successful_response = mem_rsp_valid && mem_rsp_ready && !mem_rsp_error;
    final_response = successful_response
                  && ((words_completed_q + 1'b1) == {1'b0, length_q});
    zero_length_start = (state_q == DMA_IDLE) && start
                      && (length_words == 32'd0);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q           <= DMA_IDLE;
      direction_q       <= ai_accel_pkg::DMA_MEM_TO_ACTIVATION;
      length_q          <= '0;
      words_completed_q <= '0;
      memory_addr_q     <= '0;
      scratchpad_addr_q <= '0;
      store_data_q      <= '0;
      done              <= 1'b0;
      error             <= 1'b0;
    end else begin
      done  <= 1'b0;
      error <= 1'b0;

      if (start && (state_q != DMA_IDLE)) begin
        error <= 1'b1;
      end

      case (state_q)
        DMA_IDLE: begin
          if (start) begin
            if (length_words == 32'd0) begin
              done <= 1'b1;
            end else if (!config_valid) begin
              error <= 1'b1;
            end else begin
              direction_q       <= direction;
              length_q          <= length_words;
              words_completed_q <= '0;
              if (direction == ai_accel_pkg::DMA_OUTPUT_TO_MEM) begin
                memory_addr_q     <= dst_addr;
                scratchpad_addr_q <= src_addr;
                state_q           <= DMA_OUTPUT_REQUEST;
              end else begin
                memory_addr_q     <= src_addr;
                scratchpad_addr_q <= dst_addr;
                state_q           <= DMA_LOAD_REQUEST;
              end
            end
          end
        end

        DMA_LOAD_REQUEST: begin
          if (mem_req_ready) begin
            state_q <= DMA_LOAD_RESPONSE;
          end
        end

        DMA_LOAD_RESPONSE: begin
          if (mem_rsp_valid) begin
            if (mem_rsp_error) begin
              error   <= 1'b1;
              state_q <= DMA_IDLE;
            end else if ((words_completed_q + 1'b1) == {1'b0, length_q}) begin
              words_completed_q <= words_completed_q + 1'b1;
              done              <= 1'b1;
              state_q           <= DMA_IDLE;
            end else begin
              words_completed_q <= words_completed_q + 1'b1;
              memory_addr_q     <= memory_addr_q + 32'd4;
              scratchpad_addr_q <= scratchpad_addr_q + 32'd1;
              state_q           <= DMA_LOAD_REQUEST;
            end
          end
        end

        DMA_OUTPUT_REQUEST: begin
          state_q <= DMA_OUTPUT_RESPONSE;
        end

        DMA_OUTPUT_RESPONSE: begin
          if (output_read_valid) begin
            store_data_q <= output_read_data;
            state_q      <= DMA_STORE_REQUEST;
          end
        end

        DMA_STORE_REQUEST: begin
          if (mem_req_ready) begin
            state_q <= DMA_STORE_RESPONSE;
          end
        end

        DMA_STORE_RESPONSE: begin
          if (mem_rsp_valid) begin
            if (mem_rsp_error) begin
              error   <= 1'b1;
              state_q <= DMA_IDLE;
            end else if ((words_completed_q + 1'b1) == {1'b0, length_q}) begin
              words_completed_q <= words_completed_q + 1'b1;
              done              <= 1'b1;
              state_q           <= DMA_IDLE;
            end else begin
              words_completed_q <= words_completed_q + 1'b1;
              memory_addr_q     <= memory_addr_q + 32'd4;
              scratchpad_addr_q <= scratchpad_addr_q + 32'd1;
              state_q           <= DMA_OUTPUT_REQUEST;
            end
          end
        end

        default: begin
          state_q <= DMA_IDLE;
          error   <= 1'b1;
        end
      endcase
    end
  end

`ifndef SYNTHESIS
  property p_request_stable_when_stalled;
    @(posedge clk) disable iff (!rst_n)
      (mem_req_valid && !mem_req_ready)
      |=> (mem_req_valid && $stable(mem_req_write) && $stable(mem_req_addr)
                         && $stable(mem_req_wdata) && $stable(mem_req_wstrb));
  endproperty

  property p_response_only_when_expected;
    @(posedge clk) disable iff (!rst_n)
      mem_rsp_ready |-> ((state_q == DMA_LOAD_RESPONSE)
                      || (state_q == DMA_STORE_RESPONSE));
  endproperty

  property p_transfer_count_in_range;
    @(posedge clk) disable iff (!rst_n)
      busy |-> (words_completed_q < {1'b0, length_q});
  endproperty

  property p_response_advances_count;
    @(posedge clk) disable iff (!rst_n)
      successful_response
      |=> (words_completed_q == ($past(words_completed_q) + 1'b1));
  endproperty

  property p_count_changes_only_on_progress;
    @(posedge clk) disable iff (!rst_n)
      $changed(words_completed_q)
      |-> $past(successful_response
             || ((state_q == DMA_IDLE) && start
              && (length_words != 0) && config_valid));
  endproperty

  property p_done_one_cycle;
    @(posedge clk) disable iff (!rst_n)
      done |=> !done;
  endproperty

  property p_done_has_cause;
    @(posedge clk) disable iff (!rst_n)
      done |-> $past(final_response || zero_length_start);
  endproperty

  property p_busy_start_preserves_command;
    @(posedge clk) disable iff (!rst_n)
      (start && busy) |=> ($stable(direction_q) && $stable(length_q));
  endproperty

  property p_no_dual_scratchpad_write;
    @(posedge clk) disable iff (!rst_n)
      !(activation_write_en && weight_write_en);
  endproperty

  assert property (p_request_stable_when_stalled)
    else $error("simple_dma changed a stalled memory request");
  assert property (p_response_only_when_expected)
    else $error("simple_dma accepted an unexpected memory response");
  assert property (p_transfer_count_in_range)
    else $error("simple_dma transfer count exceeded LENGTH");
  assert property (p_response_advances_count)
    else $error("simple_dma did not count a successful response once");
  assert property (p_count_changes_only_on_progress)
    else $error("simple_dma transfer count changed without progress");
  assert property (p_done_one_cycle)
    else $error("simple_dma done lasted more than one cycle");
  assert property (p_done_has_cause)
    else $error("simple_dma completed without the final response");
  assert property (p_busy_start_preserves_command)
    else $error("simple_dma start while busy changed the active command");
  assert property (p_no_dual_scratchpad_write);
`endif

endmodule
