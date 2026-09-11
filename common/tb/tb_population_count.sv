// -----------------------------------------------------------------------------
// tb_population_count - self-checking testbench for population_count and
// population_count_naive.
//
//   #(WIDTH) (i_data, o_population_cnt)   -- purely combinational, no clock.
//
// Both modules are instantiated side by side and checked against two
// independent references each cycle: SystemVerilog's built-in $countones(),
// and each other. population_count only supports power-of-2 WIDTH (it has its
// own `ifdef SIM assertion enforcing that); population_count_naive supports
// any WIDTH.
//
// Stimulus: all-0, all-1, single-bit-set at every position, single-bit-clear
// at every position, both alternating patterns, then 5000 random vectors.
//
// Run from common/:
//   iverilog -g2012 -DSIM -o sim tb/tb_population_count.sv \
//            population_count.sv population_count_naive.sv && vvp sim
//   iverilog -g2012 -DSIM -Ptb_population_count.WIDTH=128 -o sim \
//            tb/tb_population_count.sv population_count.sv population_count_naive.sv && vvp sim
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_population_count;

  parameter int unsigned WIDTH = 32;
  localparam int unsigned CNT_W = $clog2(WIDTH) + 1;

  logic [WIDTH-1:0] i_data;
  logic [CNT_W-1:0] tree_cnt, naive_cnt;

  population_count #(
    .WIDTH (WIDTH)
  ) dut_tree (
    .i_data           (i_data),
    .o_population_cnt (tree_cnt)
  );

  population_count_naive #(
    .WIDTH (WIDTH)
  ) dut_naive (
    .i_data           (i_data),
    .o_population_cnt (naive_cnt)
  );

  int unsigned errors = 0, checks = 0;

  task automatic check();
    int unsigned exp;
    #1; // settle
    exp = $countones(i_data);
    checks++;
    if (tree_cnt !== CNT_W'(exp)) begin
      errors++;
      $error("tree:  i_data=%b (W=%0d) got=%0d exp=%0d", i_data, WIDTH, tree_cnt, exp);
    end
    if (naive_cnt !== CNT_W'(exp)) begin
      errors++;
      $error("naive: i_data=%b (W=%0d) got=%0d exp=%0d", i_data, WIDTH, naive_cnt, exp);
    end
    if (tree_cnt !== naive_cnt) begin
      errors++;
      $error("tree/naive mismatch: tree=%0d naive=%0d i_data=%b", tree_cnt, naive_cnt, i_data);
    end
  endtask

  initial begin
    i_data = '0; check();
    i_data = '1; check();

    for (int unsigned b = 0; b < WIDTH; b++) begin
      i_data = '0; i_data[b] = 1'b1; check();   // single bit set
    end
    for (int unsigned b = 0; b < WIDTH; b++) begin
      i_data = '1; i_data[b] = 1'b0; check();   // single bit clear
    end

    for (int unsigned k = 0; k < WIDTH; k++) i_data[k] = (k % 2);
    check();
    for (int unsigned k = 0; k < WIDTH; k++) i_data[k] = ((k + 1) % 2);
    check();

    for (int unsigned i = 0; i < 5000; i++) begin
      logic [WIDTH+31:0] rnd;
      for (int unsigned c = 0; c < (WIDTH + 31) / 32; c++) rnd[32*c +: 32] = $urandom;
      i_data = rnd[WIDTH-1:0];
      check();
    end

    $display("--------------------------------------------------");
    $display("WIDTH=%0d checks=%0d errors=%0d", WIDTH, checks, errors);
    if (errors == 0) $display("RESULT: PASS");
    else             $display("RESULT: FAIL");
    $display("--------------------------------------------------");
    $finish;
  end

endmodule
