// -----------------------------------------------------------------------------
// tb_skid_buffer - self-checking testbench for the valid/ready buffer stages.
//
// Select the DUT with SKID_MODULE (default skid_buf; override to
// spill_register, which names its width parameter DATA_WIDTH -- also pass
// -DSKID_IS_SPILL). Both present:
//   #(WIDTH | DATA_WIDTH) (i_clk, i_reset_n,
//                          i_valid, i_data, o_ready,
//                          o_valid, o_data, i_ready)
//
// The producer streams an incrementing counter and holds i_valid/i_data stable
// until accepted (valid/ready contract). The consumer asserts i_ready randomly.
// Checks every cycle:
//   - each accepted output word equals the next expected count: no loss, no
//     duplication, no reordering
//   - while o_valid && !i_ready, o_valid stays high and o_data is unchanged
//   - modelled occupancy stays within the buffer's capacity and never negative
//     (i.e. o_ready backpressures before overflow)
//
// Run from skid_buffers/:
//   iverilog -g2012 -o sim tb/tb_skid_buffer.sv skid_buf.sv && vvp sim
//   iverilog -g2012 -DSKID_MODULE=spill_register -DSKID_IS_SPILL -o sim \
//            tb/tb_skid_buffer.sv spill_register.sv && vvp sim
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

`ifndef SKID_MODULE
  `define SKID_MODULE skid_buf
`endif

module tb_skid_buffer;

  parameter int unsigned WIDTH   = 16;
  parameter int unsigned N_WORDS = 20000;
  parameter int unsigned CAP     = 2;   // skid_buf holds 2; spill_register 1

  logic             clk = 0;
  logic             rst_n;
  logic             i_valid, o_ready;
  logic [WIDTH-1:0] i_data;
  logic             o_valid, i_ready;
  logic [WIDTH-1:0] o_data;

  always #5 clk = ~clk;

`ifdef SKID_IS_SPILL
  `SKID_MODULE #(.DATA_WIDTH(WIDTH)) dut (
`else
  `SKID_MODULE #(.WIDTH(WIDTH)) dut (
`endif
    .i_clk (clk), .i_reset_n(rst_n),
    .i_valid(i_valid), .i_data(i_data), .o_ready(o_ready),
    .o_valid(o_valid), .o_data(o_data), .i_ready(i_ready)
  );

  int unsigned errors  = 0;
  int unsigned rx_count = 0;
  int unsigned tx_count = 0;
  logic [WIDTH-1:0] exp_rx = '0;
  int               occ    = 0;

  logic             prev_ov = 0, prev_ir = 0;
  logic [WIDTH-1:0] prev_od = '0;

  // ---- checker: reads pre-edge values ----
  always @(posedge clk) begin
    if (rst_n) begin
      if (i_valid && o_ready) begin occ++; tx_count++; end
      if (o_valid && i_ready) begin
        if (o_data !== exp_rx) begin
          errors++;
          $error("[%0t] stream error: got %0h expected %0h", $time, o_data, exp_rx);
        end
        exp_rx  <= exp_rx + 1'b1;
        occ--; rx_count++;
      end
      if (occ < 0 || occ > CAP) begin
        errors++; $error("[%0t] occupancy %0d outside 0..%0d", $time, occ, CAP);
      end
      if (prev_ov && !prev_ir) begin
        if (!o_valid)           begin errors++; $error("[%0t] o_valid dropped, no transfer", $time); end
        if (o_data !== prev_od) begin errors++; $error("[%0t] o_data moved while stalled", $time); end
      end
    end
    prev_ov <= o_valid; prev_ir <= i_ready; prev_od <= o_data;
  end

  // ---- producer: incrementing counter, valid held until accepted ----
  logic [WIDTH-1:0] tx_word = '0;
  initial begin
    i_valid = 1'b0; i_data = '0; i_ready = 1'b0; rst_n = 1'b0;
    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    forever begin
      @(negedge clk);
      if (i_valid && o_ready) tx_word = tx_word + 1'b1;   // accepted last cycle
      if (!i_valid || o_ready) begin                      // may change the offer
        i_valid <= ($urandom_range(0, 99) < 75);
        i_data  <= tx_word;
      end
    end
  end

  // ---- consumer: random ready ----
  initial begin
    @(posedge rst_n);
    forever begin
      @(negedge clk);
      i_ready <= ($urandom_range(0, 99) < 60);
    end
  end

  // ---- run control ----
  initial begin
    @(posedge rst_n);
    wait (rx_count >= N_WORDS);
    $display("--------------------------------------------------");
    $display("WIDTH=%0d tx=%0d rx=%0d errors=%0d", WIDTH, tx_count, rx_count, errors);
    if (errors == 0) $display("RESULT: PASS");
    else             $display("RESULT: FAIL");
    $display("--------------------------------------------------");
    $finish;
  end

  initial begin #20_000_000; $error("TIMEOUT"); $finish; end

endmodule
