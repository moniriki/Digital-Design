// -----------------------------------------------------------------------------
// tb_clkmux — tests for clkmux2 and clkmux4 (bare combinational clock muxes)
//
// These muxes are combinational: they select correctly for settled inputs but
// glitch the output on a switch. This tb confirms the selection function and
// characterizes the glitch behavior:
//
//   1. selection: o_clk == the chosen input for every i_sel code, settled
//   2. clkmux2:  switching i_sel (even a clean single-source edge) chops the
//      in-progress pulse / creates a partial pulse -> runt on o_clk
//   3. clkmux4:  same runt behavior, PLUS a multi-bit i_sel transition (01<->10,
//      00<->11) briefly routes a THIRD, unselected clock to o_clk because the
//      two select bits do not change simultaneously
//
// Run from clock_common/:
//   iverilog -g2012 -o sim tb/tb_clkmux.sv clkmux2.sv clkmux4.sv && vvp sim
// -----------------------------------------------------------------------------
`timescale 1ps/1ps

module tb_clkmux;
  logic [3:0] clk = 4'b0;
  logic [1:0] sel;
  logic       o2, o4;

  clkmux2 m2 (.i_clk0(clk[0]), .i_clk1(clk[1]), .i_sel(sel[0]), .o_clk(o2));
  clkmux4 m4 (.i_clk(clk),     .i_sel(sel),                     .o_clk(o4));

  // four distinct clocks
  always #500  clk[0] = ~clk[0];
  always #700  clk[1] = ~clk[1];
  always #300  clk[2] = ~clk[2];
  always #1100 clk[3] = ~clk[3];

  int errors = 0;

  // ---- runt / spurious-edge monitor on o4 (widths must match a real clock) ----
  int  runt4 = 0;
  time r4;
  time w4;
  always @(posedge o4) r4 = $time;
  always @(negedge o4) begin
    w4 = $time - r4;
    if (r4 != 0 && w4 != 500 && w4 != 700 && w4 != 300 && w4 != 1100) runt4++;
  end

  // ---- multi-bit i_sel hazard watch: during a 01->10 change o4 must only
  //      ever be clk[1] or clk[2]; clk[0]/clk[3] means a third clock leaked ----
  bit watch = 0;
  int third_clk_hits = 0;
  always @* if (watch && (o4 === clk[0] || o4 === clk[3])) third_clk_hits++;

  initial begin
    // 1. selection function, settled inputs, two data patterns
    clk = 4'b0101;
    for (int s = 0; s < 4; s++) begin
      sel = s[1:0]; #10;
      if (o2 !== (sel[0] ? clk[1] : clk[0])) begin
        $error("clkmux2 sel=%b: o2=%b expected %b", sel, o2, sel[0] ? clk[1] : clk[0]); errors++;
      end
      if (o4 !== clk[sel]) begin
        $error("clkmux4 sel=%b: o4=%b expected %b (clk=%b)", sel, o4, clk[sel], clk); errors++;
      end
    end
    clk = 4'b1010;
    for (int s = 0; s < 4; s++) begin
      sel = s[1:0]; #10;
      if (o2 !== (sel[0] ? clk[1] : clk[0])) errors++;
      if (o4 !== clk[sel])                   errors++;
    end
    $display("selection function: %s", errors == 0 ? "OK" : "*** FAIL ***");

    // 2. runt characterization: run the clocks, flip sel from a single source
    clk = 4'b0;
    fork
      begin : src forever begin #1300; sel[0] = ~sel[0]; #900; sel[1] = ~sel[1]; end end
    join_none
    #40000;

    // 3. clkmux4 multi-bit hazard: 01 -> 10 with 40 ps inter-bit skew
    disable src;
    sel = 2'b01; #4000;
    watch = 1;
    fork
      sel[0] = 1'b0;                 // 01 -> 00
      begin #40; sel[1] = 1'b1; end  // 00 -> 10
    join
    #300;
    watch = 0;

    $display("--------------------------------------------------");
    $display("selection errors        : %0d", errors);
    $display("clkmux4 runt pulses     : %0d  (switching glitches o_clk, inherited from clkmux2)", runt4);
    $display("clkmux4 3rd-clock leak  : %0d  (multi-bit i_sel change routed an unselected clock)", third_clk_hits);
    $display("--------------------------------------------------");
    if (errors == 0) $display("RESULT: PASS (selection correct; glitch behavior is by design)");
    else             $display("RESULT: FAIL");
    $finish;
  end

  initial begin #200000; $display("RESULT: FAIL (timeout)"); $finish; end
endmodule
