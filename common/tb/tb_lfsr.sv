// -----------------------------------------------------------------------------
// tb_lfsr - self-checking testbench for the Fibonacci LFSR.
//
//   #(WIDTH) (i_clk, i_reset_n, i_seed, o_lfsr)
//
// Checks:
//   - synchronous seed load: o_lfsr == i_seed while i_reset_n is low
//   - next-state matches the reference {q[WIDTH-2:0], q[WIDTH-1]^q[WIDTH-2]}
//     every cycle, for several seeds
//   - the measured cycle length from a non-zero seed; for the widths whose
//     fixed tap pair is primitive ({2,3,4,6,7}) it must be maximal
//     (2**WIDTH - 1)
//   - the all-zeros seed is a lock-up (stays zero)
//
// Run from common/:
//   iverilog -g2012 -o sim tb/tb_lfsr.sv lfsr.sv && vvp sim
//   iverilog -g2012 -Ptb_lfsr.WIDTH=7 -o sim tb/tb_lfsr.sv lfsr.sv && vvp sim
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_lfsr;

  parameter int unsigned WIDTH = 4;

  logic             clk = 0;
  logic             rst_n;
  logic [WIDTH-1:0] seed;
  logic [WIDTH-1:0] q;

  always #5 clk = ~clk;

  lfsr #(.WIDTH(WIDTH)) dut (
    .i_clk     (clk),
    .i_reset_n (rst_n),
    .i_seed    (seed),
    .o_lfsr    (q)
  );

  int unsigned errors = 0;

  function automatic logic [WIDTH-1:0] nxt(input logic [WIDTH-1:0] s);
    return {s[WIDTH-2:0], s[WIDTH-1] ^ s[WIDTH-2]};
  endfunction

  task automatic load(input logic [WIDTH-1:0] s);
    seed  = s;
    rst_n = 1'b0;
    repeat (2) @(negedge clk);
    if (q !== s) begin
      errors++; $error("seed load: o_lfsr=%b expected %b", q, s);
    end
    rst_n = 1'b1;
  endtask

  // Follow the reference model for a number of cycles.
  task automatic track(input logic [WIDTH-1:0] s, input int unsigned cycles);
    logic [WIDTH-1:0] ref_s;
    load(s);
    ref_s = s;
    for (int unsigned i = 0; i < cycles; i++) begin
      @(negedge clk);
      ref_s = nxt(ref_s);
      if (q !== ref_s) begin
        errors++; $error("cycle %0d: o_lfsr=%b reference=%b", i, q, ref_s);
      end
    end
  endtask

  int unsigned period;
  logic [WIDTH-1:0] first;

  initial begin
    seed  = '0;
    rst_n = 1'b0;
    repeat (3) @(negedge clk);

    // Directed next-state tracking from a few seeds.
    track(WIDTH'(1), 200);
    track({WIDTH{1'b1}}, 200);
    track(WIDTH'('h5), 200);

    // Measure the cycle length. The fixed tap pair is primitive (maximal) only
    // for WIDTH in {2,3,4,6,7}.
    if (WIDTH <= 12) begin
      load(WIDTH'(1));
      first  = q;
      period = 0;
      for (int unsigned i = 0; i < (1 << WIDTH) + 2; i++) begin
        @(negedge clk);
        period = period + 1;
        if (q === first) break;
      end
      $display("WIDTH=%0d measured cycle length = %0d (maximal = %0d)",
               WIDTH, period, (1 << WIDTH) - 1);
      if ((WIDTH == 2 || WIDTH == 3 || WIDTH == 4 || WIDTH == 6 || WIDTH == 7)
          && (period != ((1 << WIDTH) - 1))) begin
        errors++;
        $error("cycle length %0d, expected maximal %0d", period, (1 << WIDTH) - 1);
      end
    end

    // All-zeros seed locks up.
    load('0);
    repeat (20) @(negedge clk);
    if (q !== '0) begin
      errors++; $error("all-zeros seed did not stay locked: o_lfsr=%b", q);
    end

    $display("--------------------------------------------------");
    $display("WIDTH=%0d errors=%0d", WIDTH, errors);
    if (errors == 0) $display("RESULT: PASS");
    else             $display("RESULT: FAIL");
    $display("--------------------------------------------------");
    $finish;
  end

  initial begin #2_000_000; $error("TIMEOUT"); $finish; end

endmodule
