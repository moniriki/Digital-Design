// -----------------------------------------------------------------------------
// tb_nxn_matrix_lru_arb - self-checking testbench for the matrix LRU arbiter.
//
//   #(WIDTH) (i_clk, i_reset_n, i_request, o_grant)   -- combinational grant.
//
// Golden model: an ordered priority list, front = highest priority. The winner
// is the first requester in list order; after a grant the winner moves to the
// back (least recently used -> lowest priority). Reset order is 0,1,2,...
// (index 0 highest), matching the DUT's matrix[i][j] = (i < j) seed.
//
// Every cycle: o_grant must equal the model, be one-hot, be a subset of
// i_request, and be non-zero whenever anything requests. A held-subset phase
// then checks that the maximum wait for any continuous requester never exceeds
// WIDTH grants (LRU is strictly fair).
//
// Run from arbiters/:
//   iverilog -g2012 -o sim tb/tb_nxn_matrix_lru_arb.sv nxn_matrix_lru_arb.sv && vvp sim
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_nxn_matrix_lru_arb;

  parameter int unsigned WIDTH    = 5;
  parameter int unsigned N_CYCLES = 20000;

  logic             clk = 0;
  logic             rst_n;
  logic [WIDTH-1:0] i_request;
  logic [WIDTH-1:0] o_grant;

  always #5 clk = ~clk;

  nxn_matrix_lru_arb #(.WIDTH(WIDTH)) dut (
    .i_clk     (clk),
    .i_reset_n (rst_n),
    .i_request (i_request),
    .o_grant   (o_grant)
  );

  int unsigned errors = 0;
  int unsigned order [WIDTH];   // order[0] = highest priority

  function automatic logic [WIDTH-1:0] model_grant(input logic [WIDTH-1:0] req);
    logic [WIDTH-1:0] g;
    g = '0;
    for (int unsigned p = 0; p < WIDTH; p++) begin
      if (req[order[p]] && g == '0) g = (WIDTH'(1) << order[p]);
    end
    return g;
  endfunction

  task automatic model_update(input logic [WIDTH-1:0] g);
    int unsigned w, pos;
    if (g == '0) return;
    for (int unsigned k = 0; k < WIDTH; k++) if (g[k]) w = k;
    for (int unsigned p = 0; p < WIDTH; p++) if (order[p] == w) pos = p;
    for (int unsigned p = pos; p < WIDTH-1; p++) order[p] = order[p+1];
    order[WIDTH-1] = w;
  endtask

  task automatic check(input logic [WIDTH-1:0] req);
    logic [WIDTH-1:0] exp;
    exp = model_grant(req);
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
      errors++; $error("[%0t] grant %b != model %b (req %b)", $time, o_grant, exp, req);
    end
  endtask

  int unsigned last_seen [WIDTH];
  int unsigned cyc = 0;
  logic [WIDTH-1:0] held;

  initial begin
    i_request = '0;
    rst_n     = 1'b0;
    for (int unsigned k = 0; k < WIDTH; k++) begin
      order[k]     = k;
      last_seen[k] = 0;
    end
    repeat (4) @(negedge clk);
    rst_n = 1'b1;

    for (int unsigned i = 0; i < N_CYCLES; i++) begin
      @(negedge clk);
      i_request = $urandom;
      #1;
      check(i_request);
      model_update(o_grant);
      @(posedge clk);
    end

    held = '0;
    held[1] = 1'b1; held[2] = 1'b1; held[WIDTH-1] = 1'b1;
    for (int unsigned i = 0; i < 4000; i++) begin
      @(negedge clk);
      i_request = held;
      #1;
      check(i_request);
      model_update(o_grant);
      cyc++;
      for (int unsigned k = 0; k < WIDTH; k++) begin
        if (o_grant[k]) last_seen[k] = cyc;
        else if (held[k] && (cyc - last_seen[k]) > WIDTH) begin
          errors++;
          $error("[%0t] input %0d starved: %0d cycles waiting", $time, k, cyc - last_seen[k]);
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
