// -----------------------------------------------------------------------------
// tb_sync_fifo — self-checking testbench for sync_fifo
//
// A behavioral queue serves as the golden reference model and is compared
// against the DUT cycle by cycle under directed + randomized valid/ready
// stimulus, followed by a drain phase. Checks cover:
//   - read data integrity and ordering (golden queue compare)
//   - o_full / o_empty against true occupancy
//   - o_wr_ready == !o_full, o_rd_valid == !o_empty
//   - no overflow (write while full) or underflow (read while empty)
//   - back-to-back and simultaneous read/write
//   - the full range of occupancy, including empty and full
//
// Parameters (override with -P<tb>.NAME=value):
//   WIDTH, DEPTH, N_CYCLES
//
// Compile defines:
//   +define+SIM        enable the DUT's elaboration guard assertion
//   +define+USE_STRUCT drive a packed-struct type through the `data_t`
//                      parameter instead of a plain vector
//
// Example (Icarus Verilog):
//   iverilog -g2012 -DSIM -o sim tb/tb_sync_fifo.sv sync_fifo.sv && vvp sim
//   iverilog -g2012 -DSIM -Ptb_sync_fifo.DEPTH=16 -o sim tb/tb_sync_fifo.sv sync_fifo.sv && vvp sim
//   iverilog -g2012 -DSIM -DUSE_STRUCT -o sim tb/tb_sync_fifo.sv sync_fifo.sv && vvp sim
//
// Pass criterion: "RESULT: PASS" with errors == 0 and the model fully drained.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_sync_fifo;

  parameter int unsigned WIDTH    = 8;
  parameter int unsigned DEPTH    = 8;
  parameter int unsigned N_CYCLES = 20000;

`ifdef USE_STRUCT
  typedef struct packed {
    logic [7:0]  hdr;
    logic [23:0] payload;
    logic        parity;
  } DT;
`else
  typedef logic [WIDTH-1:0] DT;
`endif

  localparam int unsigned DW = $bits(DT);

  logic clk = 0;
  logic rst_n;

  logic i_wr_valid, o_wr_ready, o_rd_valid, i_rd_ready, o_full, o_empty;
  DT    i_wr_data, o_rd_data;

  bit          draining = 0;
  int unsigned errors   = 0;
  int unsigned n_pushed = 0;
  int unsigned n_popped = 0;

  sync_fifo #(.WIDTH(WIDTH), .DEPTH(DEPTH), .data_t(DT)) dut (
    .i_clk      (clk),
    .i_reset_n  (rst_n),
    .i_wr_valid (i_wr_valid),
    .o_wr_ready (o_wr_ready),
    .i_wr_data  (i_wr_data),
    .o_rd_valid (o_rd_valid),
    .i_rd_ready (i_rd_ready),
    .o_rd_data  (o_rd_data),
    .o_full     (o_full),
    .o_empty    (o_empty)
  );

  always #5 clk = ~clk;

  // Golden reference model. Stored as bit-vectors so the queue is valid
  // regardless of data_t's kind (vector or packed struct).
  logic [DW-1:0] model_q [$];

  function automatic DT rand_dt();
    logic [95:0] v = {$urandom, $urandom, $urandom};
    return DT'(v[DW-1:0]);
  endfunction

  // Drive inputs on the negedge so they are stable across each posedge.
  always @(negedge clk) begin
    if (!rst_n) begin
      i_wr_valid <= 1'b0;
      i_rd_ready <= 1'b0;
      i_wr_data  <= '0;
    end else if (draining) begin
      i_wr_valid <= 1'b0;
      i_rd_ready <= 1'b1;
    end else begin
      i_wr_valid <= $urandom_range(0, 1);
      i_rd_ready <= $urandom_range(0, 1);
      i_wr_data  <= rand_dt();
    end
  end

  task automatic check_flags();
    if (o_empty !== (model_q.size() == 0)) begin
      $error("[%0t] o_empty=%0b expected=%0b (model size %0d)",
             $time, o_empty, (model_q.size() == 0), model_q.size());
      errors++;
    end
    if (o_full !== (model_q.size() == DEPTH)) begin
      $error("[%0t] o_full=%0b expected=%0b (model size %0d)",
             $time, o_full, (model_q.size() == DEPTH), model_q.size());
      errors++;
    end
    if (o_wr_ready !== !o_full) begin
      $error("[%0t] o_wr_ready=%0b but o_full=%0b", $time, o_wr_ready, o_full);
      errors++;
    end
    if (o_rd_valid !== !o_empty) begin
      $error("[%0t] o_rd_valid=%0b but o_empty=%0b", $time, o_rd_valid, o_empty);
      errors++;
    end
  endtask

  // Blocking reads at the posedge observe pre-NBA values, i.e. exactly what
  // the producer and consumer see during the cycle that ends at this edge.
  always @(posedge clk) begin
    if (rst_n) begin
      check_flags();

      // A read transfer completes on this edge; the consumer captures o_rd_data.
      if (o_rd_valid && i_rd_ready) begin
        logic [DW-1:0] exp;
        if (model_q.size() == 0) begin
          $error("[%0t] read fired but model empty", $time);
          errors++;
        end else begin
          exp = model_q.pop_front();
          if (DW'(o_rd_data) !== exp) begin
            $error("[%0t] DATA MISMATCH: o_rd_data=0x%0h expected=0x%0h",
                   $time, o_rd_data, exp);
            errors++;
          end
          n_popped++;
        end
      end

      // A write transfer completes on this edge.
      if (i_wr_valid && o_wr_ready) begin
        if (model_q.size() >= DEPTH) begin
          $error("[%0t] write fired but model full", $time);
          errors++;
        end else begin
          model_q.push_back(DW'(i_wr_data));
          n_pushed++;
        end
      end
    end
  end

  initial begin
    rst_n = 1'b0; i_wr_valid = 1'b0; i_rd_ready = 1'b0; i_wr_data = '0;
    repeat (4) @(negedge clk);
    rst_n = 1'b1;

    repeat (N_CYCLES) @(posedge clk);

    // Drain: stop writing, keep reading until the DUT reports empty.
    draining = 1'b1;
    repeat (DEPTH + 20) @(posedge clk);

    $display("--------------------------------------------------");
    $display("data_t width=%0d  pushed=%0d popped=%0d remaining=%0d errors=%0d",
             DW, n_pushed, n_popped, model_q.size(), errors);
    if (errors == 0 && model_q.size() == 0)
      $display("RESULT: PASS");
    else
      $display("RESULT: FAIL");
    $display("--------------------------------------------------");
    $finish;
  end

  initial begin
    #(20 * (N_CYCLES + 400));
    $display("RESULT: FAIL (timeout)");
    $finish;
  end

endmodule
