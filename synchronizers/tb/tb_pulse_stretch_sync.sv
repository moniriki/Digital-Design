// -----------------------------------------------------------------------------
// tb_pulse_stretch_sync - self-checking testbench for pulse_stretch_sync.
//
//   #(SRC_FREQ, DST_FREQ) (i_src_clk, i_src_reset_n, i_pulse,
//                          i_dst_clk, i_dst_reset_n, o_pulse)
//
// Part 1 - general ratio check (parameterized): two unrelated clocks, the
// destination period derived from SRC_CLK_PS and the SRC_FREQ:DST_FREQ ratio
// then skewed so the clocks are genuinely asynchronous. The source emits
// single-cycle pulses spaced well beyond the module's minimum
// (~6*CDC_RATIO source cycles).
//
// Part 2 - boundary regression (fixed, not parameterized): CDC_RATIO floors at
// 2 whenever SRC_FREQ < DST_FREQ, specifically so a source only marginally
// slower than the destination (e.g. 19:20) still gets stretched -- an
// unstretched ~1x-period pulse there is exactly as unsafe as the equal-frequency
// case. This only shows up at specific source/destination phase alignments, so
// Part 2 instantiates several copies of the DUT at that ratio with different
// source-clock phases in the same run, rather than relying on one arbitrary
// skew to happen to expose it.
//
// Checks (both parts):
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

  int unsigned errors = 0;

  // ===========================================================================
  // Part 1 - general ratio check
  // ===========================================================================

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

  int unsigned n_in = 0, n_out = 0;
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
  bit part1_done = 1'b0;

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

    $display("Part 1: SRC_FREQ=%0d DST_FREQ=%0d CDC_RATIO=%0d src=%0dps dst=%0dps in=%0d out=%0d",
             SRC_FREQ, DST_FREQ, dut.CDC_RATIO, SRC_CLK_PS, DST_CLK_PS, n_in, n_out);
    part1_done = 1'b1;
  end

  // ===========================================================================
  // Part 2 - boundary regression: SRC_FREQ just below DST_FREQ, several source
  // clock phases in one run. A source this close to the destination frequency
  // relies on CDC_RATIO flooring at 2 (not 1) even though SRC_FREQ < DST_FREQ.
  // ===========================================================================

  localparam int unsigned BND_SRC_FREQ = 999;
  localparam int unsigned BND_DST_FREQ = 1000;
  localparam int unsigned BND_N_PHASES = 6;
  localparam int unsigned BND_N_PULSES = 300;

  bit [BND_N_PHASES-1:0] part2_done;

  genvar gp;
  generate
    for (gp = 0; gp < BND_N_PHASES; gp = gp + 1) begin : g_bnd
      localparam int unsigned BSRC_PS = 2000 + gp * 41;   // spread the phase alignment
      localparam int unsigned BDST_PS = ((BSRC_PS * BND_SRC_FREQ) / BND_DST_FREQ) + 23;

      logic bsrc_clk = 0, bdst_clk = 0;
      logic bsrc_rst_n, bdst_rst_n;
      logic bi_pulse, bo_pulse;

      always #(BSRC_PS/2.0/1000.0) bsrc_clk = ~bsrc_clk;
      always #(BDST_PS/2.0/1000.0) bdst_clk = ~bdst_clk;

      pulse_stretch_sync #(
        .SRC_FREQ (BND_SRC_FREQ),
        .DST_FREQ (BND_DST_FREQ)
      ) bdut (
        .i_src_clk     (bsrc_clk),
        .i_src_reset_n (bsrc_rst_n),
        .i_pulse       (bi_pulse),
        .i_dst_clk     (bdst_clk),
        .i_dst_reset_n (bdst_rst_n),
        .o_pulse       (bo_pulse)
      );

      int unsigned bn_in = 0, bn_out = 0;
      logic bo_pulse_d = 1'b0;

      always @(posedge bdst_clk) begin
        if (bdst_rst_n) begin
          if (bo_pulse) begin
            bn_out++;
            if (bo_pulse_d) begin
              errors++;
              $error("[phase %0d][%0t] boundary o_pulse two cycles in a row", gp, $time);
            end
          end
        end
        bo_pulse_d <= bo_pulse;
      end

      task automatic send_bpulse();
        @(negedge bsrc_clk); bi_pulse = 1'b1;
        @(negedge bsrc_clk); bi_pulse = 1'b0;
        bn_in++;
      endtask

      initial begin
        bi_pulse   = 1'b0;
        bsrc_rst_n = 1'b0;
        bdst_rst_n = 1'b0;
        repeat (6) @(negedge bsrc_clk);
        repeat (6) @(negedge bdst_clk);
        bsrc_rst_n = 1'b1;
        bdst_rst_n = 1'b1;
        repeat (10) @(negedge bsrc_clk);

        for (int unsigned k = 0; k < BND_N_PULSES; k++) begin
          send_bpulse();
          repeat (8 * bdut.CDC_RATIO) @(negedge bsrc_clk);
        end
        repeat (200) @(negedge bdst_clk);

        if (bn_out != bn_in) begin
          errors++;
          $error("phase %0d (src=%0dps dst=%0dps): boundary count mismatch in=%0d out=%0d",
                 gp, BSRC_PS, BDST_PS, bn_in, bn_out);
        end
        part2_done[gp] = 1'b1;
      end
    end
  endgenerate

  // ===========================================================================
  // Join both parts, report
  // ===========================================================================

  initial begin
    wait (part1_done && (&part2_done));
    $display("Part 2: SRC_FREQ=%0d DST_FREQ=%0d CDC_RATIO=%0d across %0d source-clock phases",
             BND_SRC_FREQ, BND_DST_FREQ, g_bnd[0].bdut.CDC_RATIO, BND_N_PHASES);
    $display("--------------------------------------------------");
    $display("errors=%0d", errors);
    if (errors == 0) $display("RESULT: PASS");
    else             $display("RESULT: FAIL");
    $display("--------------------------------------------------");
    $finish;
  end

  initial begin #500_000_000; $error("TIMEOUT"); $finish; end

endmodule
