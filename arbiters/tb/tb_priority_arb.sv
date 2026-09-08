// -----------------------------------------------------------------------------
// tb_priority_arb - self-checking testbench for the fixed-priority arbiter.
//
//   #(WIDTH) (i_clk, i_reset_n, i_request, o_grant, o_grant_valid, i_grant_ready)
//
// The grant is registered and held until the consumer asserts i_grant_ready,
// then the arbiter advances to the next-lowest pending requester (excluding the
// one just served) or drops o_grant_valid. Golden model mirrors that state
// machine cycle for cycle. Checks each cycle: o_grant / o_grant_valid match the
// model, o_grant is one-hot or zero, o_grant_valid == |o_grant. A directed
// phase confirms the lowest index always wins and that a held grant is stable
// until it is taken.
//
// Run from arbiters/:
//   iverilog -g2012 -o sim tb/tb_priority_arb.sv priority_arb.sv && vvp sim
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_priority_arb;

  parameter int unsigned WIDTH    = 6;
  parameter int unsigned N_CYCLES = 30000;

  logic             clk = 0;
  logic             rst_n;
  logic [WIDTH-1:0] i_request;
  logic [WIDTH-1:0] o_grant;
  logic             o_grant_valid;
  logic             i_grant_ready;

  always #5 clk = ~clk;

  priority_arb #(.WIDTH(WIDTH)) dut (
    .i_clk         (clk),
    .i_reset_n     (rst_n),
    .i_request     (i_request),
    .o_grant       (o_grant),
    .o_grant_valid (o_grant_valid),
    .i_grant_ready (i_grant_ready)
  );

  int unsigned      errors = 0;
  logic [WIDTH-1:0] m_grant  = '0;   // modelled registered grant
  logic             m_valid  = 1'b0;

  function automatic logic [WIDTH-1:0] lowest_set(input logic [WIDTH-1:0] v);
    return v & (~v + 1'b1);
  endfunction

  function automatic logic [WIDTH-1:0] next_grant(input logic [WIDTH-1:0] req,
                                                  input logic             rdy);
    if (~m_valid)          return lowest_set(req);
    else if (m_valid && rdy) return lowest_set(req & ~m_grant);
    else                    return m_grant;
  endfunction

  task automatic check();
    if (o_grant !== m_grant) begin
      errors++; $error("[%0t] o_grant %b != model %b", $time, o_grant, m_grant);
    end
    if (o_grant_valid !== m_valid) begin
      errors++; $error("[%0t] o_grant_valid %b != model %b", $time, o_grant_valid, m_valid);
    end
    if ($countones(o_grant) > 1) begin
      errors++; $error("[%0t] o_grant not one-hot/zero: %b", $time, o_grant);
    end
    if (o_grant_valid !== (|o_grant)) begin
      errors++; $error("[%0t] o_grant_valid=%b but o_grant=%b", $time, o_grant_valid, o_grant);
    end
  endtask

  logic [WIDTH-1:0] req;
  logic             rdy;
  logic [WIDTH-1:0] g_prev;

  initial begin
    i_request     = '0;
    i_grant_ready = 1'b0;
    rst_n         = 1'b0;
    repeat (4) @(negedge clk);
    rst_n = 1'b1;

    // Randomized phase.
    for (int unsigned i = 0; i < N_CYCLES; i++) begin
      @(negedge clk);
      check();
      req = $urandom;
      rdy = $urandom & 1'b1;
      i_request     = req;
      i_grant_ready = rdy;
      g_prev        = o_grant;
      @(posedge clk);
      m_grant = next_grant(req, rdy);
      m_valid = |m_grant;
      // A held, not-yet-taken grant must not change.
      if (o_grant_valid && !rdy && (o_grant != '0) && (o_grant !== g_prev)
          && (g_prev != '0)) begin
        errors++; $error("[%0t] held grant changed while not ready: %b -> %b",
                         $time, g_prev, o_grant);
      end
    end

    // Drain any grant left from the random phase.
    i_request = '0; i_grant_ready = 1'b1;
    repeat (4) @(posedge clk);
    @(negedge clk);
    m_grant = '0; m_valid = 1'b0;
    check();

    // Directed: lowest index wins, grant holds until taken. Needs >= 2 inputs
    // at distinct indices; use index 1 and the top index.
    if (WIDTH >= 3) begin
      i_request = '0; i_request[1] = 1'b1; i_request[WIDTH-1] = 1'b1; i_grant_ready = 1'b0;
      @(posedge clk); m_grant = lowest_set(i_request); m_valid = 1'b1;
      repeat (5) begin
        @(negedge clk); check();
        if (o_grant !== (WIDTH'(1) << 1)) begin
          errors++; $error("[%0t] expected grant to index 1, got %b", $time, o_grant);
        end
        @(posedge clk);
      end
      i_grant_ready = 1'b1;
      @(posedge clk); m_grant = lowest_set(i_request & ~m_grant); m_valid = |m_grant;
      @(negedge clk); check();
    end

    $display("--------------------------------------------------");
    $display("WIDTH=%0d cycles=%0d errors=%0d", WIDTH, N_CYCLES, errors);
    if (errors == 0) $display("RESULT: PASS");
    else             $display("RESULT: FAIL");
    $display("--------------------------------------------------");
    $finish;
  end

  initial begin #10_000_000; $error("TIMEOUT"); $finish; end

endmodule
