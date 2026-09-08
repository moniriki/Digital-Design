// -----------------------------------------------------------------------------
// tb_round_robin_arb - self-checking testbench for the round-robin arbiters.
//
// Works for either implementation; select with the ARB_MODULE macro (default
// round_robin_arb, override to round_robin_arb_ptr). Both present:
//   #(WIDTH) (i_clk, i_reset_n, i_request, o_grant)   -- combinational grant.
//
// Golden model: a rotating pointer. For a request vector the winner is the
// first requester at or after (last_winner + 1) mod WIDTH; the pointer then
// moves past the winner. Every cycle the TB checks o_grant against the model
// and checks the structural contract (one-hot, grant subset of request, a
// grant whenever anything requests). A second phase holds a fixed subset of
// inputs high forever and fails if any of them waits more than WIDTH grants.
//
// Run from arbiters/:
//   iverilog -g2012 -o sim tb/tb_round_robin_arb.sv round_robin_arb.sv && vvp sim
//   iverilog -g2012 -DARB_MODULE=round_robin_arb_ptr -o sim \
//            tb/tb_round_robin_arb.sv round_robin_arb_ptr.sv && vvp sim
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

`ifndef ARB_MODULE
  `define ARB_MODULE round_robin_arb
`endif

module tb_round_robin_arb;

  parameter int unsigned WIDTH    = 6;
  parameter int unsigned N_CYCLES = 20000;

  logic             clk = 0;
  logic             rst_n;
  logic [WIDTH-1:0] i_request;
  logic [WIDTH-1:0] o_grant;

  always #5 clk = ~clk;

  `ARB_MODULE #(.WIDTH(WIDTH)) dut (
    .i_clk     (clk),
    .i_reset_n (rst_n),
    .i_request (i_request),
    .o_grant   (o_grant)
  );

  int unsigned errors = 0;
  int unsigned ptr    = 0;

  function automatic logic [WIDTH-1:0] model_grant(input logic [WIDTH-1:0] req,
                                                   input int unsigned      start);
    logic [WIDTH-1:0] g;
    int unsigned      idx;
    g = '0;
    for (int unsigned k = 0; k < WIDTH; k++) begin
      idx = (start + k) % WIDTH;
      if (req[idx] && g == '0) g = (WIDTH'(1) << idx);
    end
    return g;
  endfunction

  function automatic int unsigned onehot_index(input logic [WIDTH-1:0] v);
    int unsigned r;
    r = 0;
    for (int unsigned k = 0; k < WIDTH; k++) if (v[k]) r = k;
    return r;
  endfunction

  task automatic check(input logic [WIDTH-1:0] req);
    logic [WIDTH-1:0] exp;
    exp = model_grant(req, ptr);

    if ($countones(o_grant) > 1) begin
      errors++; $error("[%0t] o_grant not one-hot: %b", $time, o_grant);
    end
    if ((o_grant & ~req) != '0) begin
      errors++; $error("[%0t] granted a non-requester: grant %b req %b", $time, o_grant, req);
    end
    if ((|req) && (o_grant == '0)) begin
      errors++; $error("[%0t] request %b pending but no grant", $time, req);
    end
    if (o_grant !== exp) begin
      errors++; $error("[%0t] grant %b != model %b (req %b ptr %0d)", $time, o_grant, exp, req, ptr);
    end
    if (o_grant != '0) ptr = (onehot_index(o_grant) + 1) % WIDTH;
  endtask

  int unsigned last_seen [WIDTH];
  int unsigned cyc = 0;
  logic [WIDTH-1:0] held;

  initial begin
    i_request = '0;
    rst_n     = 1'b0;
    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    ptr   = 0;
    for (int unsigned k = 0; k < WIDTH; k++) last_seen[k] = 0;

    // Phase 1: uniform random requests. Drive on negedge, sample the
    // combinational grant before the posedge advances the rotation state.
    for (int unsigned i = 0; i < N_CYCLES; i++) begin
      @(negedge clk);
      i_request = $urandom;
      #1;
      check(i_request);
      @(posedge clk);
    end

    // Phase 2: a fixed subset held high forever -> must rotate, no starvation.
    held = '0;
    held[0] = 1'b1; held[2] = 1'b1; held[3] = 1'b1; held[WIDTH-1] = 1'b1;
    for (int unsigned i = 0; i < 4000; i++) begin
      @(negedge clk);
      i_request = held;
      #1;
      check(i_request);
      cyc++;
      for (int unsigned k = 0; k < WIDTH; k++) begin
        if (o_grant[k]) begin
          last_seen[k] = cyc;
        end else if (held[k] && (cyc - last_seen[k]) > WIDTH) begin
          errors++;
          $error("[%0t] input %0d starved: %0d cycles since last grant",
                 $time, k, cyc - last_seen[k]);
        end
      end
      @(posedge clk);
    end

    $display("--------------------------------------------------");
    $display("WIDTH=%0d cycles=%0d errors=%0d", WIDTH, N_CYCLES, errors);
    if (errors == 0) $display("RESULT: PASS");
    else             $display("RESULT: FAIL");
    $display("--------------------------------------------------");
    $finish;
  end

  initial begin #5_000_000; $error("TIMEOUT"); $finish; end

endmodule
