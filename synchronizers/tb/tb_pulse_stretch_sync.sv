// -----------------------------------------------------------------------------
// tb_pulse_stretch_sync - self-checking testbench for pulse_stretch_sync.
//
//   #(SRC_FREQ, DST_FREQ) (i_src_clk, i_src_reset_n, i_pulse,
//                          i_dst_clk, i_dst_reset_n, o_pulse)
//
// Two unrelated clocks. The source period is SRC_CLK_PS; the destination period
// is derived from it and the SRC_FREQ:DST_FREQ ratio, then skewed a little so
// the clocks are genuinely asynchronous. The source emits single-cycle pulses
// spaced well beyond the module's minimum (~6*CDC_RATIO source cycles).
//
// Checks:
//   - count conservation: exactly one o_pulse per i_pulse (no loss, no
//     duplication) once drained
//   - o_pulse is a one-cycle strobe (never asserted two cycles running)
//
// Metastability MTBF is not simulated (Icarus has no metastability model); this
// verifies functional behaviour for spacings that respect the clock ratio.
//
// Run from synchronizers/:
//   iverilog -g2012 -o sim tb/tb_pulse_stretch_sync.sv pulse_stretch_sync.sv && vvp sim
//   iverilog -g2012 -Ptb_pulse_stretch_sync.SRC_FREQ=8 -Ptb_pulse_stretch_sync.DST_FREQ=3 \
//            -o sim tb/tb_pulse_stretch_sync.sv pulse_stretch_sync.sv && vvp sim
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_pulse_stretch_sync;

  parameter int unsigned SRC_FREQ   = 4;
  parameter int unsigned DST_FREQ   = 1;
  parameter int unsigned SRC_CLK_PS = 2000;
  parameter int unsigned N_PULSES   = 2000;

  // Destination period from the ratio, then +0.3% so the clocks are unrelated.
  localparam int unsigned DST_CLK_PS = ((SRC_CLK_PS * SRC_FREQ) / DST_FREQ) + 23;

  logic src_clk = 0, dst_clk = 0;
  logic src_rst_n, dst_rst_n;
  logic i_pulse, o_pulse;

  always #(SRC_CLK_PS/2.0/1000.0) src_clk = ~src_clk;
  always #(DST_CLK_PS/2.0/1000.0) dst_clk = ~dst_clk;

  pulse_stretch_sync #(
    .SRC_FREQ (SRC_FREQ),
    .DST_FREQ (DST_FREQ)
  ) dut (
    .i_src_clk     (src_clk),
    .i_src_reset_n (src_rst_n),
    .i_pulse       (i_pulse),
    .i_dst_clk     (dst_clk),
    .i_dst_reset_n (dst_rst_n),
    .o_pulse       (o_pulse)
  );

  int unsigned errors = 0, n_in = 0, n_out = 0;
  logic o_pulse_d = 1'b0;

  always @(posedge dst_clk) begin
    if (dst_rst_n) begin
      if (o_pulse) begin
        n_out++;
        if (o_pulse_d) begin
          errors++; $error("[%0t] o_pulse asserted two cycles in a row", $time);
        end
      end
    end
    o_pulse_d <= o_pulse;
  end

  // one source pulse, one source cycle wide
  task automatic send_pulse();
    @(negedge src_clk); i_pulse = 1'b1;
    @(negedge src_clk); i_pulse = 1'b0;
    n_in++;
  endtask

  int unsigned spacing;

  initial begin
    i_pulse   = 1'b0;
    src_rst_n = 1'b0;
    dst_rst_n = 1'b0;
    repeat (6) @(negedge src_clk);
    repeat (6) @(negedge dst_clk);
    src_rst_n = 1'b1;
    dst_rst_n = 1'b1;
    repeat (10) @(negedge src_clk);

    // Comfortably beyond the documented minimum spacing.
    spacing = 8 * dut.CDC_RATIO;
    for (int unsigned i = 0; i < N_PULSES; i++) begin
      send_pulse();
      repeat (spacing + ($urandom % spacing)) @(negedge src_clk);
    end
    repeat (200) @(negedge dst_clk);   // drain

    if (n_out != n_in) begin
      errors++; $error("count mismatch: in=%0d out=%0d", n_in, n_out);
    end

    $display("--------------------------------------------------");
    $display("SRC_FREQ=%0d DST_FREQ=%0d CDC_RATIO=%0d  src=%0dps dst=%0dps",
             SRC_FREQ, DST_FREQ, dut.CDC_RATIO, SRC_CLK_PS, DST_CLK_PS);
    $display("in=%0d out=%0d errors=%0d", n_in, n_out, errors);
    if (errors == 0) $display("RESULT: PASS");
    else             $display("RESULT: FAIL");
    $display("--------------------------------------------------");
    $finish;
  end

  initial begin #500_000_000; $error("TIMEOUT"); $finish; end

endmodule
