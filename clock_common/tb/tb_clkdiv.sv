// -----------------------------------------------------------------------------
// tb_clkdiv — self-checking testbench for a clock divider
//
// Works for any divider with the interface (i_clk, i_reset_n, o_clk).
//   - DIV_MODULE  : module under test (default clkdiv_sync)
//   - PARAM_N = 1 : DUT is parameterized as #(.N(DIV)) (e.g. clkdiv_sync)
//   - PARAM_N = 0 : DUT is a fixed-ratio module (e.g. clkdiv2/4/8); DIV is just
//                   the expected ratio for the checks
//
// Checks:
//   - divide ratio: o_clk period == DIV * i_clk period, over N_PERIODS
//     consecutive periods (also catches jitter/drift — all periods must match)
//   - duty cycle: high time == low time == (DIV/2) * i_clk period  (even DIV)
//     For odd DIV the tb checks |high - low| <= 1 i_clk period instead.
//   - edge alignment: every o_clk transition lands on an i_clk rising edge
//     (meaningful with SDF/delay back-annotation; in zero-delay RTL both a
//      synchronous and a ripple divider pass, so a 0 here is necessary not
//      sufficient — run gate-sim to actually catch ripple skew)
//   - o_clk is a defined 0 while in reset
//   - recovers to the correct ratio after a mid-run reset pulse
//
// Parameters (override with -Ptb_clkdiv.NAME=value):
//   DIV, T_PS, N_PERIODS, PARAM_N
//
// Examples (from clock_common/):
//   iverilog -g2012 -Ptb_clkdiv.DIV=8  -o sim tb/tb_clkdiv.sv clkdiv_sync.sv && vvp sim
//   iverilog -g2012 -Ptb_clkdiv.DIV=6  -o sim tb/tb_clkdiv.sv clkdiv_sync.sv && vvp sim
//   iverilog -g2012 -DDIV_MODULE=clkdiv4 -Ptb_clkdiv.PARAM_N=0 -Ptb_clkdiv.DIV=4 \
//            -o sim tb/tb_clkdiv.sv clkdiv2.sv clkdiv4.sv && vvp sim
//
// Pass criterion: "RESULT: PASS" with errors == 0.
// -----------------------------------------------------------------------------
`timescale 1ps/1ps

`ifndef DIV_MODULE
  `define DIV_MODULE clkdiv_sync
`endif

module tb_clkdiv;
  parameter int unsigned DIV       = 8;
  parameter int unsigned T_PS      = 1000;   // i_clk period (even)
  parameter int unsigned N_PERIODS = 24;     // consecutive o_clk periods to check
  parameter bit          PARAM_N   = 1'b1;

  logic i_clk = 0, i_reset_n, o_clk;

  generate
    if (PARAM_N)
      `DIV_MODULE #(.N(DIV)) dut (.i_clk(i_clk), .i_reset_n(i_reset_n), .o_clk(o_clk));
    else
      `DIV_MODULE            dut (.i_clk(i_clk), .i_reset_n(i_reset_n), .o_clk(o_clk));
  endgenerate

  always #(T_PS/2) i_clk = ~i_clk;

  int unsigned errors = 0;

  // ---- edge-alignment monitor ----
  time last_rise = 0;
  always @(posedge i_clk) last_rise = $time;
  always @(o_clk) begin
    if (i_reset_n && ($time != last_rise)) begin
      $error("[%0t] o_clk edge not on an i_clk rising edge (last rise %0t)", $time, last_rise);
      errors++;
    end
  end

  // ---- main sequence ----
  time  t_rise, t_fall, t_rise2, t_prev;
  real  period, high, low;
  int   i;

  task automatic check_one_cycle(input string tag);
    @(posedge o_clk); t_rise  = $time;
    @(negedge o_clk); t_fall  = $time;
    @(posedge o_clk); t_rise2 = $time;
    period = t_rise2 - t_rise;
    high   = t_fall  - t_rise;
    low    = period  - high;
    if (period != DIV * T_PS) begin
      $error("%s period=%0.0f ps, expected %0d ps (DIV=%0d x %0d)", tag, period, DIV*T_PS, DIV, T_PS);
      errors++;
    end
    if (DIV % 2 == 0) begin
      if (high != (DIV/2)*T_PS || low != (DIV/2)*T_PS) begin
        $error("%s duty not 50%%: high=%0.0f low=%0.0f (expect %0d each)", tag, high, low, (DIV/2)*T_PS);
        errors++;
      end
    end else begin
      if ((high > low ? high - low : low - high) > T_PS) begin
        $error("%s odd-DIV duty off by >1 i_clk: high=%0.0f low=%0.0f", tag, high, low);
        errors++;
      end
    end
  endtask

  initial begin
    i_reset_n = 1'b0;
    repeat (6) @(posedge i_clk);
    if (o_clk !== 1'b0) begin
      $error("o_clk = %b during reset (expected 0)", o_clk);
      errors++;
    end
    @(negedge i_clk) i_reset_n = 1'b1;

    // settle, then verify N_PERIODS consecutive periods are all exactly DIV*T_PS
    repeat (2*DIV + 4) @(posedge i_clk);
    @(posedge o_clk) t_prev = $time;
    for (i = 0; i < N_PERIODS; i++) begin
      @(posedge o_clk);
      if (($time - t_prev) != DIV * T_PS) begin
        $error("period %0d = %0d ps, expected %0d ps", i, $time - t_prev, DIV*T_PS);
        errors++;
      end
      t_prev = $time;
    end

    check_one_cycle("steady:");

    // mid-run reset pulse, then re-check
    @(negedge i_clk) i_reset_n = 1'b0;
    repeat (3) @(posedge i_clk);
    if (o_clk !== 1'b0) begin $error("o_clk=%b during mid-run reset", o_clk); errors++; end
    @(negedge i_clk) i_reset_n = 1'b1;
    repeat (2*DIV + 4) @(posedge i_clk);
    check_one_cycle("post-reset:");

    $display("--------------------------------------------------");
    $display("DIV=%0d  T_PS=%0d  periods_checked=%0d  errors=%0d", DIV, T_PS, N_PERIODS, errors);
    if (errors == 0) $display("RESULT: PASS");
    else             $display("RESULT: FAIL");
    $display("--------------------------------------------------");
    $finish;
  end

  initial begin
    #(200 * (N_PERIODS + 4) * DIV * T_PS);
    $display("RESULT: FAIL (timeout)");
    $finish;
  end
endmodule
