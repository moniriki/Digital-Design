// -----------------------------------------------------------------------------
// tb_bin_tree_arb - self-checking testbench for the 4-input binary-tree
// round-robin arbiter (bin_tree_arb_4).
//
//   (i_clk, i_reset_n, i_request[3:0], o_grant[3:0])   -- combinational grant.
//
// Fairness in this arbiter is per node, so there is no single-pointer golden
// model. The TB checks the structural contract every cycle (one-hot or zero,
// grant subset of request, a grant whenever anything requests) and, with all
// four inputs held high, checks that no requester waits more than a bounded
// number of grants (round-robin within each pair, round-robin between pairs, so
// the bound is 4).
//
// Run from arbiters/:
//   iverilog -g2012 -o sim tb/tb_bin_tree_arb.sv bin_tree_arb.sv && vvp sim
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_bin_tree_arb;

  localparam int unsigned WIDTH    = 4;
  parameter  int unsigned N_CYCLES = 20000;

  logic             clk = 0;
  logic             rst_n;
  logic [WIDTH-1:0] i_request;
  logic [WIDTH-1:0] o_grant;

  always #5 clk = ~clk;

  bin_tree_arb_4 dut (
    .i_clk     (clk),
    .i_reset_n (rst_n),
    .i_request (i_request),
    .o_grant   (o_grant)
  );

  int unsigned errors = 0;

  task automatic check(input logic [WIDTH-1:0] req);
    if ($countones(o_grant) > 1) begin
      errors++; $error("[%0t] o_grant not one-hot/zero: %b", $time, o_grant);
    end
    if ((o_grant & ~req) != '0) begin
      errors++; $error("[%0t] granted a non-requester: grant %b req %b", $time, o_grant, req);
    end
    if ((|req) && (o_grant == '0)) begin
      errors++; $error("[%0t] request %b pending but no grant", $time, req);
    end
  endtask

  int unsigned last_seen [WIDTH];
  int unsigned cyc = 0;
  int unsigned gap_bound = 4;

  initial begin
    i_request = '0;
    rst_n     = 1'b0;
    for (int unsigned k = 0; k < WIDTH; k++) last_seen[k] = 0;
    repeat (4) @(negedge clk);
    rst_n = 1'b1;

    // Phase 1: random requests, structural contract.
    for (int unsigned i = 0; i < N_CYCLES; i++) begin
      @(negedge clk);
      i_request = $urandom;
      #1;
      check(i_request);
      @(posedge clk);
    end

    // Phase 2: all four held -> bounded wait for every input.
    for (int unsigned i = 0; i < 4000; i++) begin
      @(negedge clk);
      i_request = '1;
      #1;
      check(i_request);
      cyc++;
      for (int unsigned k = 0; k < WIDTH; k++) begin
        if (o_grant[k]) last_seen[k] = cyc;
        else if ((cyc - last_seen[k]) > gap_bound) begin
          errors++;
          $error("[%0t] input %0d waited %0d grants (bound %0d)",
                 $time, k, cyc - last_seen[k], gap_bound);
        end
      end
      @(posedge clk);
    end

    $display("--------------------------------------------------");
    $display("cycles=%0d errors=%0d", N_CYCLES, errors);
    if (errors == 0) $display("RESULT: PASS");
    else             $display("RESULT: FAIL");
    $display("--------------------------------------------------");
    $finish;
  end

  initial begin #5_000_000; $error("TIMEOUT"); $finish; end

endmodule
