// -----------------------------------------------------------------------------
// tb_weighted_priority_arb - self-checking testbench for the weighted-priority
// arbiter.
//
//   #(WIDTH, WEIGHT_WIDTH) (i_clk, i_reset_n, i_request, i_request_weight,
//                            o_grant, o_grant_valid)
//
// Grant is registered one cycle behind the sampled i_request / i_request_weight.
// Golden model: among the requestors asserting i_request, the one with the
// highest i_request_weight wins; ties are broken by the lowest index. o_grant
// is one-hot for the winner and o_grant_valid tracks whether any requestor was
// asserted. When no requestor is asserted, o_grant's bit pattern is a
// don't-care and is intentionally not checked (only o_grant_valid==0 is
// required).
//
// Stimulus: directed cases (single requestor, distinct weights at every
// index, tied weights, a max-weight requestor that isn't asserted, all-idle
// with nonzero residual weights, reset), then randomized trials.
//
// Run from arbiters/:
//   iverilog -g2012 -o sim tb/tb_weighted_priority_arb.sv weighted_priority_arb.sv ../common/min_max_tree.sv && vvp sim
//   iverilog -g2012 -Ptb_weighted_priority_arb.WIDTH=1 -o sim tb/tb_weighted_priority_arb.sv weighted_priority_arb.sv ../common/min_max_tree.sv && vvp sim
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_weighted_priority_arb;

  parameter int unsigned WIDTH        = 4;
  parameter int unsigned WEIGHT_WIDTH = 4;
  parameter int unsigned N_CYCLES     = 20000;

  logic                    clk = 0;
  logic                    rst_n;
  logic [WIDTH-1:0]        i_request;
  logic [WEIGHT_WIDTH-1:0] i_request_weight [WIDTH-1:0];
  logic [WIDTH-1:0]        o_grant;
  logic                    o_grant_valid;

  always #5 clk = ~clk;

  weighted_priority_arb #(
    .WIDTH        (WIDTH),
    .WEIGHT_WIDTH (WEIGHT_WIDTH)
  ) dut (
    .i_clk            (clk),
    .i_reset_n        (rst_n),
    .i_request        (i_request),
    .i_request_weight (i_request_weight),
    .o_grant          (o_grant),
    .o_grant_valid    (o_grant_valid)
  );

  int unsigned      errors  = 0;
  logic [WIDTH-1:0] m_grant = '0; // modelled registered grant
  logic             m_valid = 1'b0;

  // Reads i_request_weight directly (module scope) rather than as a
  // subroutine port -- Icarus does not support unpacked-array ports.
  task automatic compute_model(input logic [WIDTH-1:0] req);
    int                       best_idx;
    logic [WEIGHT_WIDTH-1:0]  best_w;
    best_idx = -1;
    best_w   = '0;
    for (int i = 0; i < WIDTH; i++) begin
      if (req[i] && (best_idx == -1 || i_request_weight[i] > best_w)) begin
        best_idx = i;
        best_w   = i_request_weight[i];
      end
    end
    if (best_idx == -1) begin
      m_grant = '0;
      m_valid = 1'b0;
    end else begin
      m_grant = (WIDTH'(1)) << best_idx;
      m_valid = 1'b1;
    end
  endtask

  task automatic check();
    if (m_valid && (o_grant !== m_grant)) begin
      errors++; $error("[%0t] o_grant %b != model %b", $time, o_grant, m_grant);
    end
    if (o_grant_valid !== m_valid) begin
      errors++; $error("[%0t] o_grant_valid %b != model %b", $time, o_grant_valid, m_valid);
    end
    if ($countones(o_grant) > 1) begin
      errors++; $error("[%0t] o_grant not one-hot/zero: %b", $time, o_grant);
    end
  endtask

  logic [WIDTH-1:0] req;

  initial begin
    i_request = '0;
    for (int i = 0; i < WIDTH; i++) i_request_weight[i] = '0;
    rst_n = 1'b0;
    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    m_grant = '0; m_valid = 1'b0;
    @(negedge clk); check(); // must be clear immediately out of reset

    // Generic single-requestor toggle (works at any WIDTH >= 1).
    i_request = '0; i_request[0] = 1'b1; i_request_weight[0] = WEIGHT_WIDTH'(3);
    compute_model(i_request);
    @(posedge clk); @(negedge clk); check();

    i_request[0] = 1'b0;
    compute_model(i_request);
    @(posedge clk); @(negedge clk); check();

    // Directed cases that assume 4 distinct indices.
    if (WIDTH >= 4) begin
      // single requestor at the top index
      i_request = '0; i_request[WIDTH-1] = 1'b1; i_request_weight[WIDTH-1] = 4'd9;
      compute_model(i_request);
      @(posedge clk); @(negedge clk); check();

      // distinct weights, idx1 highest
      i_request = '1;
      i_request_weight[0] = 4'd3; i_request_weight[1] = 4'd7;
      i_request_weight[2] = 4'd2; i_request_weight[3] = 4'd1;
      compute_model(i_request);
      @(posedge clk); @(negedge clk); check();

      // distinct weights, idx2 highest
      i_request_weight[0] = 4'd1; i_request_weight[1] = 4'd2;
      i_request_weight[2] = 4'd15; i_request_weight[3] = 4'd0;
      compute_model(i_request);
      @(posedge clk); @(negedge clk); check();

      // distinct weights, idx0 highest
      i_request_weight[0] = 4'd15; i_request_weight[1] = 4'd2;
      i_request_weight[2] = 4'd3; i_request_weight[3] = 4'd0;
      compute_model(i_request);
      @(posedge clk); @(negedge clk); check();

      // all tied -> lowest index (idx0) wins
      i_request_weight[0] = 4'd5; i_request_weight[1] = 4'd5;
      i_request_weight[2] = 4'd5; i_request_weight[3] = 4'd5;
      compute_model(i_request);
      @(posedge clk); @(negedge clk); check();

      // tied among a subset -> lowest active index wins
      i_request = 4'b1110; // idx0 not requesting
      i_request_weight[1] = 4'd5; i_request_weight[2] = 4'd5; i_request_weight[3] = 4'd5;
      compute_model(i_request);
      @(posedge clk); @(negedge clk); check();

      // max-weight requestor not asserted must be ignored
      i_request = 4'b1101; // idx1 not requesting
      i_request_weight[0] = 4'd1; i_request_weight[1] = 4'd15;
      i_request_weight[2] = 4'd1; i_request_weight[3] = 4'd1;
      compute_model(i_request);
      @(posedge clk); @(negedge clk); check();

      // back-to-back changing requests, including repeated idle
      i_request_weight[0] = 4'd1; i_request_weight[1] = 4'd2;
      i_request_weight[2] = 4'd3; i_request_weight[3] = 4'd4;
      i_request = 4'b1010; compute_model(i_request); @(posedge clk); @(negedge clk); check();
      i_request = 4'b0000; compute_model(i_request); @(posedge clk); @(negedge clk); check();
      i_request = 4'b0101; compute_model(i_request); @(posedge clk); @(negedge clk); check();
      i_request = 4'b1111; compute_model(i_request); @(posedge clk); @(negedge clk); check();
      i_request = 4'b0000; compute_model(i_request); @(posedge clk); @(negedge clk); check();
    end

    // All idle with nonzero residual weights -> must not leak a grant.
    i_request = '0;
    for (int i = 0; i < WIDTH; i++) i_request_weight[i] = WEIGHT_WIDTH'(8);
    compute_model(i_request);
    @(posedge clk); @(negedge clk); check();

    // Randomized phase.
    for (int unsigned t = 0; t < N_CYCLES; t++) begin
      @(negedge clk); check();
      req = $urandom;
      for (int i = 0; i < WIDTH; i++)
        i_request_weight[i] = WEIGHT_WIDTH'($urandom_range(0, (1 << WEIGHT_WIDTH) - 1));
      i_request = req;
      compute_model(req);
      @(posedge clk);
    end
    @(negedge clk); check();

    $display("--------------------------------------------------");
    $display("WIDTH=%0d WEIGHT_WIDTH=%0d cycles=%0d errors=%0d",
              WIDTH, WEIGHT_WIDTH, N_CYCLES, errors);
    if (errors == 0) $display("RESULT: PASS");
    else             $display("RESULT: FAIL");
    $display("--------------------------------------------------");
    $finish;
  end

  initial begin #10_000_000; $error("TIMEOUT"); $finish; end

endmodule
