// -----------------------------------------------------------------------------
// tb_min_max_tree - self-checking testbench for min_max_tree.
//
//   #(NUM_DATA, DATA_WIDTH, MIN_FUNCTION) (i_data, o_min_max)
//
// Purely combinational, no clock. min_max_tree only supports power-of-2
// NUM_DATA (it has its own `ifdef SIM assertion enforcing that).
//
// Golden model: a linear scan over i_data[] finding the unsigned min (or max,
// per MIN_FUNCTION) directly, independent of the tree structure.
//
// Stimulus per run: directed (all values equal, winner at position 0, winner
// at the last position, a single 0 planted among large values at each end),
// then 500 random trials.
//
// Run from common/:
//   iverilog -g2012 -DSIM -o sim tb/tb_min_max_tree.sv min_max_tree.sv && vvp sim
//   iverilog -g2012 -DSIM -Ptb_min_max_tree.NUM_DATA=64 -Ptb_min_max_tree.DATA_WIDTH=8 \
//            -Ptb_min_max_tree.MIN_FUNCTION=0 -o sim tb/tb_min_max_tree.sv min_max_tree.sv && vvp sim
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_min_max_tree;

  parameter int unsigned NUM_DATA     = 32;
  parameter int unsigned DATA_WIDTH   = 32;
  parameter bit          MIN_FUNCTION = 1; // 1 -> minimum; 0 -> maximum

  logic [DATA_WIDTH-1:0] i_data [0:NUM_DATA-1];
  logic [DATA_WIDTH-1:0] o_min_max;

  min_max_tree #(
    .NUM_DATA     (NUM_DATA),
    .DATA_WIDTH   (DATA_WIDTH),
    .MIN_FUNCTION (MIN_FUNCTION)
  ) dut (
    .i_data    (i_data),
    .o_min_max (o_min_max)
  );

  int unsigned errors = 0, checks = 0;

  task automatic check();
    logic [DATA_WIDTH-1:0] exp;
    #1; // settle
    exp = i_data[0];
    for (int k = 1; k < NUM_DATA; k++) begin
      if (MIN_FUNCTION) begin if (i_data[k] < exp) exp = i_data[k]; end
      else               begin if (i_data[k] > exp) exp = i_data[k]; end
    end
    checks++;
    if (o_min_max !== exp) begin
      errors++;
      $error("i_data[0]=%0d got=%0d exp=%0d", i_data[0], o_min_max, exp);
    end
  endtask

  initial begin
    // Directed
    for (int k = 0; k < NUM_DATA; k++) i_data[k] = 42;
    check(); // all equal

    for (int k = 0; k < NUM_DATA; k++) i_data[k] = k + 100;
    check(); // winner at position 0

    for (int k = 0; k < NUM_DATA; k++) i_data[k] = NUM_DATA - k + 100;
    check(); // winner at the last position

    i_data[0] = 0;
    for (int k = 1; k < NUM_DATA; k++) i_data[k] = 1000 + k;
    check(); // a single 0 at position 0

    i_data[NUM_DATA-1] = 0;
    for (int k = 0; k < NUM_DATA-1; k++) i_data[k] = 1000 + k;
    check(); // a single 0 at the last position

    // Randomized
    for (int t = 0; t < 500; t++) begin
      for (int k = 0; k < NUM_DATA; k++) i_data[k] = $urandom;
      check();
    end

    $display("--------------------------------------------------");
    $display("NUM_DATA=%0d DATA_WIDTH=%0d MIN_FUNCTION=%0d checks=%0d errors=%0d",
             NUM_DATA, DATA_WIDTH, MIN_FUNCTION, checks, errors);
    if (errors == 0) $display("RESULT: PASS");
    else             $display("RESULT: FAIL");
    $display("--------------------------------------------------");
    $finish;
  end

endmodule
