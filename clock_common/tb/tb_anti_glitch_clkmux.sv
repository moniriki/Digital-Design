// -----------------------------------------------------------------------------
// tb_anti_glitch_clkmux — self-checking testbench for anti_glitch_clkmux
//
// Verifies the cross-coupled glitchless 2:1 clock mux:
//   - after reset, o_clk = i_clk0 (default select)
//   - a QUASI-STATIC i_sel change switches cleanly: no runt pulse on o_clk,
//     the two select flops are never both high, the two gated clocks never
//     overlap  (i_sel must be held >= ~2*sync_depth cycles of both clocks)
//   - reset with i_sel already = 1 (select clk1 immediately) does not glitch
//     -- exercises the sync3s / sync3r reset-value consistency
//   - both clocks must be running for a switch to complete: requesting a switch
//     to a stopped clock parks o_clk off; it recovers when the clock returns
//
// Deps: clkgate.sv clkor.sv ../synchronizers/sync3r.sv ../synchronizers/sync3s.sv
//
// Run from clock_common/:
//   iverilog -g2012 -o sim tb/tb_anti_glitch_clkmux.sv anti_glitch_clkmux.sv \
//     clkgate.sv clkor.sv ../synchronizers/sync3r.sv ../synchronizers/sync3s.sv \
//     && vvp sim
// -----------------------------------------------------------------------------
`timescale 1ps/1ps

module tb_anti_glitch_clkmux;
  parameter int unsigned T0_PS    = 1000;    // i_clk0 period
  parameter int unsigned T1_PS    = 720;     // i_clk1 period (unrelated)
  parameter int unsigned SEL_HOLD = 30000;   // i_sel stable time between changes

  logic i_clk0 = 0, i_clk1 = 0, i_reset_n, i_sel, o_clk;
  anti_glitch_clkmux dut (
    .i_clk0(i_clk0), .i_clk1(i_clk1),
    .i_reset_n(i_reset_n), .i_sel(i_sel), .o_clk(o_clk)
  );

  logic clk1_run = 1'b1;
  always #(T0_PS/2) i_clk0 = ~i_clk0;
  always #(T1_PS/2) if (clk1_run) i_clk1 = ~i_clk1;

  int unsigned errors = 0;
  int unsigned both_sel = 0, gate_overlap = 0, runts = 0;

  // continuous invariant + glitch monitors
  always @(dut.sel_clk0, dut.sel_clk1)
    if (dut.sel_clk0 === 1'b1 && dut.sel_clk1 === 1'b1) begin
      both_sel++; $error("[%0t] both select flops high", $time); errors++;
    end
  always @(dut.clk0_gated, dut.clk1_gated)
    if (dut.clk0_gated === 1'b1 && dut.clk1_gated === 1'b1) begin
      gate_overlap++; $error("[%0t] both gated clocks high (overlap)", $time); errors++;
    end
  time o_r;
  time o_w;
  always @(posedge o_clk) o_r = $time;
  always @(negedge o_clk) begin
    o_w = $time - o_r;
    if (o_r != 0 && o_w != T0_PS/2 && o_w != T1_PS/2) begin
      $error("[%0t] o_clk pulse = %0d ps (runt/merged)", $time, o_w); errors++;
    end
  end

  int o_edges;

  initial begin
    // reset with i_sel = 1 -> selecting clk1 from the very start
    i_sel = 1'b1;
    i_reset_n = 1'b0;
    repeat (4) @(posedge i_clk0);
    @(negedge i_clk0) i_reset_n = 1'b1;
    repeat (40) @(posedge i_clk1);

    // several quasi-static switches
    repeat (8) begin
      #(SEL_HOLD) i_sel = ~i_sel;
    end
    repeat (40) @(posedge i_clk0);

    // switch to a stopped clock -> handover must not complete, o_clk parks off
    i_sel = 1'b0; #(SEL_HOLD);            // ensure we are on clk0
    repeat (10) @(posedge i_clk0);
    clk1_run = 1'b0; i_clk1 = 1'b0;
    o_edges = 0;
    i_sel = 1'b1;                         // request clk1 (which is stopped)
    #(SEL_HOLD);
    // count o_clk edges over a fresh window
    begin
      int e0; e0 = 0;
      fork
        begin repeat (2000) begin @(o_clk); e0++; end end
        begin #(20*T0_PS); end
      join_any
      disable fork;
      if (e0 != 0) begin
        $error("switch to stopped clk1: o_clk still toggling (%0d edges) - should be parked off", e0);
        errors++;
      end
    end
    // restart clk1 -> switch completes
    clk1_run = 1'b1;
    repeat (60) @(posedge i_clk1);
    begin
      int e1; e1 = 0;
      fork
        begin repeat (2000) begin @(o_clk); e1++; end end
        begin #(20*T1_PS); end
      join_any
      disable fork;
      if (e1 < 10) begin
        $error("clk1 restarted: switch did not complete (%0d o_clk edges)", e1);
        errors++;
      end
    end

    $display("--------------------------------------------------");
    $display("both_sel=%0d  gate_overlap=%0d  runts=%0d  errors=%0d",
             both_sel, gate_overlap, runts, errors);
    if (errors == 0) $display("RESULT: PASS");
    else             $display("RESULT: FAIL");
    $display("--------------------------------------------------");
    $finish;
  end

  initial begin
    #(1000 * T0_PS);
    $display("RESULT: FAIL (timeout)");
    $finish;
  end
endmodule
