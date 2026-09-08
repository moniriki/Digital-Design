// -----------------------------------------------------------------------------
// tb_gearbox_data_word_converter - self-checking testbench for the data-width
// gearbox.
//
//   #(SRC_DATA_WIDTH, DST_DATA_WIDTH) (i_clk, i_reset_n,
//       i_valid, i_data, i_data_size, o_ready,
//       o_valid, o_data, i_ready)
//
// Golden model: a byte queue. Each accepted input beat pushes its low
// i_data_size bytes (the unused high bytes of i_data are driven with garbage to
// prove they are ignored). Each accepted output beat pops DST_DATA_WIDTH/8
// bytes, little-endian, and must match. Both sides get random back-pressure and
// the source inserts random idle bubbles and zero-size beats. Also checks
// output valid/data stability while stalled.
//
// Exercised for upsizing (SRC < DST), downsizing (SRC > DST) and equal widths
// by overriding SRC_DATA_WIDTH / DST_DATA_WIDTH.
//
// Run from common/:
//   iverilog -g2012 -o sim tb/tb_gearbox_data_word_converter.sv \
//            gearbox_data_word_converter.sv && vvp sim
//   iverilog -g2012 -Ptb_gearbox_data_word_converter.SRC_DATA_WIDTH=128 \
//            -Ptb_gearbox_data_word_converter.DST_DATA_WIDTH=32 \
//            -o sim tb/tb_gearbox_data_word_converter.sv \
//            gearbox_data_word_converter.sv && vvp sim
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_gearbox_data_word_converter;

  parameter int unsigned SRC_DATA_WIDTH = 64;
  parameter int unsigned DST_DATA_WIDTH = 128;
  parameter int unsigned N_BEATS        = 3000;

  localparam int unsigned SRCB  = SRC_DATA_WIDTH / 8;
  localparam int unsigned DSTB  = DST_DATA_WIDTH / 8;
  localparam int unsigned SLOG2 = $clog2(SRCB);

  logic clk = 0;
  logic rst_n;
  always #5 clk = ~clk;

  logic                       i_valid, o_ready;
  logic [SRC_DATA_WIDTH-1:0]  i_data;
  logic [SLOG2:0]             i_data_size;
  logic                       o_valid, i_ready;
  logic [DST_DATA_WIDTH-1:0]  o_data;

  gearbox_data_word_converter #(
    .SRC_DATA_WIDTH (SRC_DATA_WIDTH),
    .DST_DATA_WIDTH (DST_DATA_WIDTH)
  ) dut (
    .i_clk(clk), .i_reset_n(rst_n),
    .i_valid(i_valid), .i_data(i_data), .i_data_size(i_data_size), .o_ready(o_ready),
    .o_valid(o_valid), .o_data(o_data), .i_ready(i_ready)
  );

  int unsigned errors = 0;
  int unsigned beats_in = 0, words_out = 0, bytes_in = 0, bytes_out = 0;

  byte unsigned model [$];
  byte unsigned eb;
  logic prev_ov = 0, prev_ir = 0;
  logic [DST_DATA_WIDTH-1:0] prev_od = '0;

  always @(posedge clk) begin
    if (rst_n) begin
      if (i_valid && o_ready) begin
        for (int k = 0; k < i_data_size; k++) model.push_back(i_data[8*k +: 8]);
        beats_in++; bytes_in += i_data_size;
      end
      if (o_valid && i_ready) begin
        if (model.size() < DSTB) begin
          errors++; $error("[%0t] output word but only %0d bytes modelled", $time, model.size());
        end else begin
          for (int k = 0; k < DSTB; k++) begin
            eb = model.pop_front();
            if (o_data[8*k +: 8] !== eb) begin
              errors++;
              $error("[%0t] word %0d byte %0d: got %02h exp %02h",
                     $time, words_out, k, o_data[8*k +: 8], eb);
            end
          end
          words_out++; bytes_out += DSTB;
        end
      end
      if (prev_ov && !prev_ir) begin
        if (!o_valid)           begin errors++; $error("[%0t] o_valid dropped while stalled", $time); end
        if (o_data !== prev_od) begin errors++; $error("[%0t] o_data moved while stalled", $time); end
      end
    end
    prev_ov <= o_valid; prev_ir <= i_ready; prev_od <= o_data;
  end

  // ---- source: random size (incl 0), garbage in unused lanes, random gaps ----
  initial begin : src
    logic [SRC_DATA_WIDTH-1:0] d;
    int unsigned n;
    i_valid = 1'b0; i_data = '0; i_data_size = '0; i_ready = 1'b0; rst_n = 1'b0;
    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    for (int unsigned i = 0; i < N_BEATS; i++) begin
      while ($urandom_range(0, 3) == 0) @(negedge clk);   // idle bubble
      n = $urandom_range(0, SRCB);
      for (int k = 0; k < SRCB; k++) d[8*k +: 8] = $urandom; // all lanes garbage
      @(negedge clk);
      i_valid     = 1'b1;
      i_data      = d;
      i_data_size = n[SLOG2:0];
      do @(negedge clk); while (!o_ready);
      i_valid     = 1'b0;
      i_data      = 'x;
      i_data_size = '0;
    end
    // drain and report
    repeat (SRCB * 4 + 40) @(negedge clk);
    if (model.size() >= DSTB) begin
      errors++; $error("undrained: %0d bytes still modelled", model.size());
    end
    $display("--------------------------------------------------");
    $display("SRC=%0d DST=%0d beats_in=%0d words_out=%0d bytes_in=%0d bytes_out=%0d errors=%0d",
             SRC_DATA_WIDTH, DST_DATA_WIDTH, beats_in, words_out, bytes_in, bytes_out, errors);
    if (errors == 0) $display("RESULT: PASS");
    else             $display("RESULT: FAIL");
    $display("--------------------------------------------------");
    $finish;
  end

  // ---- sink: random ready ----
  initial begin
    @(posedge rst_n);
    forever begin
      @(negedge clk);
      i_ready = ($urandom_range(0, 1) == 1);
    end
  end

  initial begin #40_000_000; $error("TIMEOUT"); $finish; end

endmodule
