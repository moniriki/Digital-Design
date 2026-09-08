// -----------------------------------------------------------------------------
// tb_time_slice_arb - self-checking testbench for the time-division arbiter.
//
//   #(WIDTH) (i_clk, i_reset_n, i_request, o_grant)
//
// The slot counter advances every cycle and wraps at WIDTH-1, so slot s is
// active in cycle s of each frame. The model tracks the expected slot; every
// cycle o_grant must be exactly {i_request[slot] in position slot, zero
// elsewhere}. A second phase drives all requests high for many frames and
// checks each requester is granted exactly once per WIDTH-cycle frame.
//
// Run from arbiters/:
//   iverilog -g2012 -o sim tb/tb_time_slice_arb.sv time_slice_arb.sv && vvp sim
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_time_slice_arb;

  parameter int unsigned WIDTH    = 5;
  parameter int unsigned N_FRAMES = 3000;

  logic             clk = 0;
  logic             rst_n;
  logic [WIDTH-1:0] i_request;
  logic [WIDTH-1:0] o_grant;

  always #5 clk = ~clk;

  time_slice_arb #(.WIDTH(WIDTH)) dut (
    .i_clk     (clk),
    .i_reset_n (rst_n),
    .i_request (i_request),
    .o_grant   (o_grant)
  );

  int unsigned errors = 0;
  int unsigned slot   = 0;

  task automatic check(input logic [WIDTH-1:0] req);
    logic [WIDTH-1:0] exp;
    exp = '0;
    exp[slot] = req[slot];
    if (o_grant !== exp) begin
      errors++;
      $error("[%0t] slot %0d: o_grant %b != expected %b (req %b)",
             $time, slot, o_grant, exp, req);
    end
    if ($countones(o_grant) > 1) begin
      errors++; $error("[%0t] o_grant not one-hot/zero: %b", $time, o_grant);
    end
  endtask

  int unsigned grants_in_frame [WIDTH];

  function automatic int unsigned onehot_index(input logic [WIDTH-1:0] v);
    int unsigned r;
    r = 0;
    for (int unsigned k = 0; k < WIDTH; k++) if (v[k]) r = k;
    return r;
  endfunction

  initial begin
    i_request = '0;
    rst_n     = 1'b0;
    repeat (4) @(negedge clk);
    rst_n = 1'b1;

    // Lock onto the current slot: with every input requesting, o_grant is
    // one-hot and its index is the active slot.
    @(negedge clk); i_request = '1; #1;
    slot = onehot_index(o_grant);
    @(posedge clk);
    slot = (slot + 1) % WIDTH;

    // Phase 1: random requests, slot-accurate model check.
    for (int unsigned i = 0; i < N_FRAMES * WIDTH; i++) begin
      @(negedge clk);
      i_request = $urandom;
      #1;
      check(i_request);
      @(posedge clk);
      slot = (slot + 1) % WIDTH;
    end

    // Phase 2: all requesting -> each requester granted exactly once per frame.
    for (int unsigned f = 0; f < 2000; f++) begin
      for (int unsigned k = 0; k < WIDTH; k++) grants_in_frame[k] = 0;
      for (int unsigned s = 0; s < WIDTH; s++) begin
        @(negedge clk);
        i_request = '1;
        #1;
        check(i_request);
        for (int unsigned k = 0; k < WIDTH; k++) if (o_grant[k]) grants_in_frame[k]++;
        @(posedge clk);
        slot = (slot + 1) % WIDTH;
      end
      for (int unsigned k = 0; k < WIDTH; k++) begin
        if (grants_in_frame[k] != 1) begin
          errors++;
          $error("[%0t] frame %0d: requester %0d granted %0d times (expected 1)",
                 $time, f, k, grants_in_frame[k]);
        end
      end
    end

    $display("--------------------------------------------------");
    $display("WIDTH=%0d frames=%0d errors=%0d", WIDTH, N_FRAMES, errors);
    if (errors == 0) $display("RESULT: PASS");
    else             $display("RESULT: FAIL");
    $display("--------------------------------------------------");
    $finish;
  end

  initial begin #10_000_000; $error("TIMEOUT"); $finish; end

endmodule
