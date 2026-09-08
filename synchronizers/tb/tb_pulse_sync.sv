// -----------------------------------------------------------------------------
// tb_pulse_sync - self-checking testbench for the pulse synchronizer.
//
//   #(MAX_CNT, ASYNC_BOUNDARY) (i_src_clk, i_src_reset_n, i_pulse,
//                               i_dst_clk, i_dst_reset_n, o_pulse, o_error)
//
// Two unrelated clocks by default (ASYNC_BOUNDARY = 1, Gray-coded pointers
// through `sync`); pass -DSYNC_BOUNDARY to test ASYNC_BOUNDARY = 0 with a
// single shared clock.
//
// Reference: the source accepts a pulse unless MAX_CNT are already in flight,
// in which case it is dropped and o_error latches (sticky). Every accepted
// pulse must produce exactly one o_pulse on the destination side.
//
//   Phase A (lossless): low input rate, large MAX_CNT margin ->
//     o_error stays 0 and o_pulse count == offered count.
//   Phase B (overrun): i_pulse every source cycle, destination drains slower ->
//     o_error latches, some pulses are dropped, but every *accepted* pulse
//     still comes out.
//   Always: o_pulse is a one-cycle strobe (never two cycles back to back);
//     o_error, once set, never clears.
//
// accepted-pulse count is read from dut.src_wr_ptr_q (it only ever increments
// by one per cycle) so the check does not depend on modelling the synchronizer
// latency.
//
// Run from synchronizers/:
//   iverilog -g2012 -o sim tb/tb_pulse_sync.sv pulse_sync.sv sync.sv && vvp sim
//   iverilog -g2012 -DSYNC_BOUNDARY -o sim tb/tb_pulse_sync.sv pulse_sync.sv sync.sv && vvp sim
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_pulse_sync;

  parameter int unsigned MAX_CNT     = 8;
  parameter int unsigned SRC_CLK_PS  = 7000;
  parameter int unsigned DST_CLK_PS  = 11000;
  parameter int unsigned N_PULSES_A  = 600;
  parameter int unsigned N_CYCLES_B  = 4000;

`ifdef SYNC_BOUNDARY
  localparam bit          ASYNC_BOUNDARY = 1'b0;
  localparam int unsigned DST_EFF_PS     = SRC_CLK_PS;   // dst_clk follows src_clk
`else
  localparam bit          ASYNC_BOUNDARY = 1'b1;
  localparam int unsigned DST_EFF_PS     = DST_CLK_PS;
`endif

  // Phase A drives an evenly spaced pulse train (one pulse every SPACING_A
  // source cycles). The gap is set to several destination periods so each
  // pulse is fully drained -- plus synchronizer round-trip latency -- before
  // the next arrives, keeping the in-flight count at 1-2 regardless of MAX_CNT
  // or clock ratio. That makes Phase A losslessly checkable for any MAX_CNT.
  localparam int unsigned SPACING_A =
      ((10 * DST_EFF_PS + SRC_CLK_PS - 1) / SRC_CLK_PS) < 4 ? 4
      : ((10 * DST_EFF_PS + SRC_CLK_PS - 1) / SRC_CLK_PS);

  logic src_clk = 0, dst_clk = 0;
  logic src_rst_n, dst_rst_n;
  logic i_pulse;
  logic o_pulse, o_error;

  always #(SRC_CLK_PS/2.0/1000.0) src_clk = ~src_clk;
`ifdef SYNC_BOUNDARY
  always @* dst_clk = src_clk;
`else
  always #(DST_CLK_PS/2.0/1000.0) dst_clk = ~dst_clk;
`endif

  pulse_sync #(
    .MAX_CNT        (MAX_CNT),
    .ASYNC_BOUNDARY (ASYNC_BOUNDARY)
  ) dut (
    .i_src_clk     (src_clk),
    .i_src_reset_n (src_rst_n),
    .i_pulse       (i_pulse),
    .i_dst_clk     (dst_clk),
    .i_dst_reset_n (dst_rst_n),
    .o_pulse       (o_pulse),
    .o_error       (o_error)
  );

  int unsigned errors     = 0;
  int unsigned n_offered  = 0;   // i_pulse asserted at a source edge
  int unsigned n_accepted = 0;   // src_wr_ptr_q advanced
  int unsigned n_out      = 0;   // o_pulse strobes seen

  logic [$bits(dut.src_wr_ptr_q)-1:0] wr_prev = '0;
  logic o_error_prev = 1'b0;
  logic o_pulse_prev = 1'b0;

  // ---- source-side observation ----
  always @(posedge src_clk) begin
    if (src_rst_n) begin
      if (i_pulse) n_offered++;
      if (dut.src_wr_ptr_q !== wr_prev) n_accepted++;
      if (o_error_prev && !o_error) begin
        errors++; $error("[%0t] o_error de-asserted (must be sticky)", $time);
      end
    end
    wr_prev      <= dut.src_wr_ptr_q;
    o_error_prev <= o_error;
  end

  // ---- destination-side observation ----
  always @(posedge dst_clk) begin
    if (dst_rst_n) begin
      if (o_pulse) begin
        n_out++;
        if (o_pulse_prev) begin
          errors++; $error("[%0t] o_pulse asserted two cycles in a row", $time);
        end
      end
    end
    o_pulse_prev <= o_pulse;
  end

  // ---- stimulus ----
  // Evenly spaced train: one pulse every `spacing` source cycles.
  task automatic src_pulse_train(input int unsigned n_pulses, input int unsigned spacing);
    for (int unsigned i = 0; i < n_pulses; i++) begin
      @(negedge src_clk);
      i_pulse = 1'b1;
      @(negedge src_clk);
      i_pulse = 1'b0;
      repeat (spacing - 1) @(negedge src_clk);
    end
  endtask

  // Every source cycle at `pct` percent probability.
  task automatic src_pulse_burst(input int unsigned n_cycles, input int unsigned pct);
    for (int unsigned i = 0; i < n_cycles; i++) begin
      @(negedge src_clk);
      i_pulse = ($urandom_range(0, 99) < pct);
    end
    @(negedge src_clk);
    i_pulse = 1'b0;
  endtask

  initial begin
    i_pulse   = 1'b0;
    src_rst_n = 1'b0;
    dst_rst_n = 1'b0;
    repeat (5) @(negedge src_clk);
    repeat (5) @(negedge dst_clk);
    src_rst_n = 1'b1;
    dst_rst_n = 1'b1;
    repeat (4) @(negedge src_clk);

    // Phase A: evenly spaced train below the drain rate, must be lossless.
    src_pulse_train(N_PULSES_A, SPACING_A);
    repeat (400) @(negedge dst_clk);        // let everything drain

    if (o_error !== 1'b0) begin
      errors++; $error("phase A: o_error set with a lossless input rate");
    end
    if (n_accepted !== n_offered) begin
      errors++; $error("phase A: accepted %0d != offered %0d", n_accepted, n_offered);
    end
    if (n_out !== n_accepted) begin
      errors++; $error("phase A: o_pulse count %0d != accepted %0d", n_out, n_accepted);
    end
    $display("phase A: offered=%0d accepted=%0d out=%0d error=%0b",
             n_offered, n_accepted, n_out, o_error);

    // Phase B: hammer the input every source cycle. Whether this overruns
    // depends on the clock ratio; the invariants hold either way.
    src_pulse_burst(N_CYCLES_B, 100);
    repeat (2000) @(negedge dst_clk);       // drain the backlog

    if (n_out !== n_accepted) begin
      errors++; $error("phase B: o_pulse count %0d != accepted %0d (accepted pulse lost)",
                       n_out, n_accepted);
    end
    if (n_accepted < n_offered) begin
      // pulses were dropped -> error must have latched
      if (o_error !== 1'b1) begin
        errors++; $error("phase B: %0d pulses dropped but o_error not set",
                         n_offered - n_accepted);
      end
    end else begin
      // destination kept up -> nothing dropped, error must stay clear
      if (o_error !== 1'b0) begin
        errors++; $error("phase B: o_error set but no pulse was dropped");
      end
      $display("phase B: destination kept up at this clock ratio, no drops");
    end

    $display("--------------------------------------------------");
    $display("MAX_CNT=%0d async=%0b offered=%0d accepted=%0d dropped=%0d out=%0d errors=%0d",
             MAX_CNT, ASYNC_BOUNDARY, n_offered, n_accepted,
             n_offered - n_accepted, n_out, errors);
    if (errors == 0) $display("RESULT: PASS");
    else             $display("RESULT: FAIL");
    $display("--------------------------------------------------");
    $finish;
  end

  initial begin #50_000_000; $error("TIMEOUT"); $finish; end

endmodule
