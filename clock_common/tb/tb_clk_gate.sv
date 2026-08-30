// -----------------------------------------------------------------------------
// tb_clk_gate — self-checking testbench for the clk_gate module
//
// Verifies the latch-then-AND clock gate is glitch-free:
//   - o_clk is a defined 0 while i_en is held low
//   - o_clk mirrors i_clk (full-width pulses) while i_en is held high
//   - every o_clk edge coincides with an i_clk edge (no spurious edges)
//   - every o_clk high pulse is exactly one i_clk high-phase wide (no runts)
//   - toggling i_en at arbitrary sub-cycle phases never produces a glitch or a
//     partial pulse — enable/disable only ever take effect on a clean boundary
//
//   -DFOUNDRY_LIBCELL          test the libcell path (a behavioral ICG stand-in
//                              is provided below; swap in the real cell model)
//
// Run from clock_common/:
//   iverilog -g2012 -o sim tb/tb_clk_gate.sv clk_gate.sv && vvp sim
//   iverilog -g2012 -DFOUNDRY_LIBCELL -o sim tb/tb_clk_gate.sv clk_gate.sv && vvp sim
//
// Pass criterion: "RESULT: PASS" with errors == 0.
// -----------------------------------------------------------------------------
`timescale 1ps/1ps

`ifdef FOUNDRY_LIBCELL
// Behavioral stand-in for the foundry integrated clock-gating cell.
// Replace with the vendor's simulation model for real runs.
module libcell_clkgate (input logic i_CK, input logic i_E, output logic o_CK);
  logic en_l;
  always_latch if (~i_CK) en_l = i_E;
  assign o_CK = i_CK & en_l;
endmodule
`endif

module tb_clk_gate;
  parameter int unsigned T_PS = 1000;

  logic i_clk = 0, i_en, o_clk;
  clk_gate dut (.i_clk(i_clk), .i_en(i_en), .o_clk(o_clk));

  always #(T_PS/2) i_clk = ~i_clk;

  int unsigned errors = 0;

  // ---- continuous glitch monitors ----
  time last_clk_edge = 0;
  always @(i_clk) last_clk_edge = $time;

  always @(o_clk) begin
    if ($time != 0 && $time != last_clk_edge) begin
      $error("[%0t] o_clk edge not coincident with an i_clk edge (last %0t)", $time, last_clk_edge);
      errors++;
    end
  end

  time o_rise = 0;
  always @(posedge o_clk) o_rise = $time;
  always @(negedge o_clk) begin
    if (o_rise != 0 && ($time - o_rise) != T_PS/2) begin
      $error("[%0t] o_clk high pulse = %0d ps, expected %0d (runt/stretched)", $time, $time - o_rise, T_PS/2);
      errors++;
    end
  end

  // ---- edge counters for the steady checks ----
  int clk_pulses = 0, o_pulses = 0;
  always @(posedge i_clk) clk_pulses++;
  always @(posedge o_clk) o_pulses++;

  initial begin
    i_en = 1'b0;

    // 1. held disabled -> o_clk quiet and 0
    repeat (10) @(posedge i_clk);
    if (o_clk !== 1'b0) begin $error("o_clk = %b while disabled", o_clk); errors++; end
    clk_pulses = 0; o_pulses = 0;
    repeat (20) @(posedge i_clk);
    if (o_pulses != 0) begin $error("disabled: o_clk pulsed %0d times", o_pulses); errors++; end

    // 2. held enabled -> o_clk mirrors i_clk
    @(negedge i_clk) i_en = 1'b1;
    clk_pulses = 0; o_pulses = 0;
    repeat (50) @(posedge i_clk);
    if (o_pulses < 49) begin
      $error("enabled: o_clk pulsed %0d times vs i_clk %0d", o_pulses, clk_pulses);
      errors++;
    end

    // 3. held disabled again
    @(negedge i_clk) i_en = 1'b0;
    repeat (4) @(posedge i_clk);
    clk_pulses = 0; o_pulses = 0;
    repeat (20) @(posedge i_clk);
    if (o_pulses != 0 || o_clk !== 1'b0) begin
      $error("re-disabled: o_pulses=%0d o_clk=%b", o_pulses, o_clk);
      errors++;
    end

    // 4. glitch stress: flip i_en at every sub-cycle phase offset. The continuous
    //    monitors above will catch any spurious edge or partial pulse.
    for (int k = 0; k < 64; k++) begin
      #((k * 37) % T_PS + 3);
      i_en = ~i_en;
    end
    i_en = 1'b0;
    repeat (20) @(posedge i_clk);

    $display("--------------------------------------------------");
    $display("errors=%0d", errors);
    if (errors == 0) $display("RESULT: PASS");
    else             $display("RESULT: FAIL");
    $display("--------------------------------------------------");
    $finish;
  end

  initial begin
    #(500 * T_PS);
    $display("RESULT: FAIL (timeout)");
    $finish;
  end
endmodule
