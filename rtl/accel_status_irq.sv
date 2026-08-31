// Sticky completion/error status and interrupt generation.
// Reset has highest priority. New events take priority over W1C clears.
module accel_status_irq (
  input  logic       clk,
  input  logic       rst_n,

  input  logic       done_event,
  input  logic       dma_error_event,
  input  logic       compute_config_error_event,

  input  logic [1:0] int_enable, // bit 0: DONE, bit 1: ERROR
  input  logic [1:0] w1c_clear,  // bit 0: DONE, bit 1: ERROR

  output logic       done_status,
  output logic       error_status,
  output logic [1:0] int_status,
  output logic       irq
);

  localparam int unsigned DONE_BIT  = 0;
  localparam int unsigned ERROR_BIT = 1;

  logic [1:0] status_q;
  logic error_event;

  always_comb begin
    error_event  = dma_error_event || compute_config_error_event;
    done_status  = status_q[DONE_BIT];
    error_status = status_q[ERROR_BIT];
    int_status   = status_q;
    irq          = |(status_q & int_enable);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      status_q <= '0;
    end else begin
      if (done_event) begin
        status_q[DONE_BIT] <= 1'b1;
      end else if (w1c_clear[DONE_BIT]) begin
        status_q[DONE_BIT] <= 1'b0;
      end

      if (error_event) begin
        status_q[ERROR_BIT] <= 1'b1;
      end else if (w1c_clear[ERROR_BIT]) begin
        status_q[ERROR_BIT] <= 1'b0;
      end
    end
  end

`ifndef SYNTHESIS
  property p_reset_clears_status;
    @(posedge clk)
      !rst_n |-> (int_status == 2'b00);
  endproperty

  property p_done_event_is_sticky;
    @(posedge clk) disable iff (!rst_n)
      done_event |=> done_status;
  endproperty

  property p_error_event_is_sticky;
    @(posedge clk) disable iff (!rst_n)
      error_event |=> error_status;
  endproperty

  property p_done_clear_without_event;
    @(posedge clk) disable iff (!rst_n)
      (w1c_clear[DONE_BIT] && !done_event) |=> !done_status;
  endproperty

  property p_error_clear_without_event;
    @(posedge clk) disable iff (!rst_n)
      (w1c_clear[ERROR_BIT] && !error_event) |=> !error_status;
  endproperty

  property p_done_holds_without_update;
    @(posedge clk) disable iff (!rst_n)
      (!done_event && !w1c_clear[DONE_BIT]) |=> $stable(done_status);
  endproperty

  property p_error_holds_without_update;
    @(posedge clk) disable iff (!rst_n)
      (!error_event && !w1c_clear[ERROR_BIT]) |=> $stable(error_status);
  endproperty

  property p_irq_matches_enabled_status;
    @(posedge clk) disable iff (!rst_n)
      irq == (|(int_status & int_enable));
  endproperty

  assert property (p_reset_clears_status)
    else $error("accel_status_irq status was set during reset");
  assert property (p_done_event_is_sticky)
    else $error("accel_status_irq lost a completion event");
  assert property (p_error_event_is_sticky)
    else $error("accel_status_irq lost an error event");
  assert property (p_done_clear_without_event);
  assert property (p_error_clear_without_event);
  assert property (p_done_holds_without_update);
  assert property (p_error_holds_without_update);
  assert property (p_irq_matches_enabled_status);
`endif

endmodule
