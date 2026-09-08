// -----------------------------------------------------------------------------
// tb_serdes - self-checking testbench for parallel_to_serial_converter and
// serial_to_parallel_converter, individually and as a round trip.
//
// Both present a valid/ready interface on each side. The TB drives a stream of
// random words with random back-pressure on both sides and checks against a
// bit/word reference model:
//   - parallel_to_serial: each accepted word produces DATA_WIDTH serial bits,
//     LSB first, in order
//   - serial_to_parallel: each DATA_WIDTH serial bits reassemble to the
//     original word, LSB first
//   - loopback (p2s -> s2p): words in == words out, in order
//   - output valid/data stable while stalled; count is exact (no loss/dup)
//
// Run from common/:
//   iverilog -g2012 -o sim tb/tb_serdes.sv \
//            parallel_to_serial_converter.sv serial_to_parallel_converter.sv && vvp sim
//   iverilog -g2012 -Ptb_serdes.DATA_WIDTH=8 -o sim tb/tb_serdes.sv \
//            parallel_to_serial_converter.sv serial_to_parallel_converter.sv && vvp sim
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_serdes;

  parameter int unsigned DATA_WIDTH = 4;
  parameter int unsigned N_WORDS    = 4000;

  logic clk = 0;
  logic rst_n;
  always #5 clk = ~clk;

  // ---- p2s ----
  logic                   p2s_i_valid, p2s_o_ready;
  logic [DATA_WIDTH-1:0]  p2s_i_data;
  logic                   ser_valid, ser_ready, ser_bit;

  parallel_to_serial_converter #(.DATA_WIDTH(DATA_WIDTH)) u_p2s (
    .i_clk(clk), .i_reset_n(rst_n),
    .i_valid(p2s_i_valid), .i_data(p2s_i_data), .o_ready(p2s_o_ready),
    .o_valid(ser_valid), .o_data(ser_bit), .i_ready(ser_ready)
  );

  // ---- s2p (fed by p2s) ----
  logic                  s2p_o_valid, s2p_i_ready;
  logic [DATA_WIDTH-1:0] s2p_o_data;

  serial_to_parallel_converter #(.DATA_WIDTH(DATA_WIDTH)) u_s2p (
    .i_clk(clk), .i_reset_n(rst_n),
    .i_valid(ser_valid), .i_data(ser_bit), .o_ready(ser_ready),
    .o_valid(s2p_o_valid), .o_data(s2p_o_data), .i_ready(s2p_i_ready)
  );

  int unsigned errors = 0;

  // reference: words pushed into p2s, expected back out of s2p, in order
  logic [DATA_WIDTH-1:0] word_q [$];
  // reference: serial bits currently expected on the p2s->s2p link
  logic bit_q [$];

  int unsigned words_in = 0, words_out = 0, bits_seen = 0;
  logic prev_sv = 0, prev_sr = 0, prev_bit = 0;
  logic prev_pv = 0;

  always @(posedge clk) begin
    if (rst_n) begin
      // p2s input accept
      if (p2s_i_valid && p2s_o_ready) begin
        word_q.push_back(p2s_i_data);
        for (int k = 0; k < DATA_WIDTH; k++) bit_q.push_back(p2s_i_data[k]);
        words_in++;
      end
      // serial link transfer
      if (ser_valid && ser_ready) begin
        if (bit_q.size() == 0) begin
          errors++; $error("[%0t] serial bit with empty reference", $time);
        end else begin
          logic eb;
          eb = bit_q.pop_front();
          if (ser_bit !== eb) begin
            errors++; $error("[%0t] serial bit %0d: got %b exp %b", $time, bits_seen, ser_bit, eb);
          end
          bits_seen++;
        end
      end
      // s2p output accept
      if (s2p_o_valid && s2p_i_ready) begin
        if (word_q.size() == 0) begin
          errors++; $error("[%0t] output word with empty reference", $time);
        end else begin
          logic [DATA_WIDTH-1:0] ew;
          ew = word_q.pop_front();
          if (s2p_o_data !== ew) begin
            errors++; $error("[%0t] loopback word %0d: got %0h exp %0h", $time, words_out, s2p_o_data, ew);
          end
          words_out++;
        end
      end
      // serial-link output stability while stalled
      if (prev_sv && !prev_sr) begin
        if (!ser_valid)         begin errors++; $error("[%0t] ser_valid dropped while stalled", $time); end
        if (ser_bit !== prev_bit) begin errors++; $error("[%0t] ser_data moved while stalled", $time); end
      end
    end
    prev_sv <= ser_valid; prev_sr <= ser_ready; prev_bit <= ser_bit;
  end

  // ---- stimulus ----
  logic [DATA_WIDTH-1:0] tx = '0;
  initial begin
    p2s_i_valid = 1'b0; p2s_i_data = '0; s2p_i_ready = 1'b0; rst_n = 1'b0;
    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    forever begin
      @(negedge clk);
      if (p2s_i_valid && p2s_o_ready) tx = tx + 1'b1;
      if (!p2s_i_valid || p2s_o_ready) begin
        p2s_i_valid <= ($urandom_range(0, 99) < 70);
        p2s_i_data  <= $urandom;
      end
    end
  end

  initial begin
    @(posedge rst_n);
    forever begin
      @(negedge clk);
      s2p_i_ready <= ($urandom_range(0, 99) < 55);
    end
  end

  initial begin
    @(posedge rst_n);
    wait (words_out >= N_WORDS);
    $display("--------------------------------------------------");
    $display("DATA_WIDTH=%0d words_in=%0d words_out=%0d bits=%0d errors=%0d",
             DATA_WIDTH, words_in, words_out, bits_seen, errors);
    if (errors == 0) $display("RESULT: PASS");
    else             $display("RESULT: FAIL");
    $display("--------------------------------------------------");
    $finish;
  end

  initial begin #20_000_000; $error("TIMEOUT"); $finish; end

endmodule
