// -----------------------------------------------------------------------------
// tb_sync_fifo — self-checking testbench for a synchronous FIFO
//
// Drives any FIFO that presents this valid/ready interface:
//   #(WIDTH, DEPTH, data_t) (i_clk, i_reset_n,
//     i_wr_valid, o_wr_ready, i_wr_data,
//     o_rd_valid, i_rd_ready, o_rd_data, o_full, o_empty)
// The module under test is selected by the FIFO_MODULE macro (default
// sync_fifo); override it to point at any compatible implementation.
//
// A behavioral queue is the golden reference model, compared against the DUT
// every cycle. Stimulus runs in phases: a balanced randomized phase, a
// write-heavy phase (hammers the full corner), a read-heavy phase (hammers
// the empty corner), a directed fill / hold-full / drain / hold-empty phase,
// a mid-simulation reset with data in flight, another randomized phase, and a
// final drain.
//
// Checks:
//   - o_full / o_empty against true occupancy, every cycle
//   - o_wr_ready == !o_full, o_rd_valid == !o_empty
//   - FWFT read data: whenever o_rd_valid, o_rd_data == queue head
//   - read-port stability: while o_rd_valid && !i_rd_ready, o_rd_valid stays
//     high and o_rd_data does not change (checked across every cycle except
//     reset boundaries)
//   - read data / ordering on every accepted transfer (golden queue compare)
//   - no overflow (write while full) or underflow (read while empty)
//   - flags hold while a full / empty condition is held with no opposing xfer
//   - empty & !full immediately after reset (initial and mid-sim)
//
// Parameters (override with -P<tb>.NAME=value):
//   WIDTH, DEPTH, N_CYCLES, WR_BIAS, RD_BIAS
//     WR_BIAS/RD_BIAS are the percent of cycles i_wr_valid / i_rd_ready are
//     asserted during the balanced phase (0..100).
//
// Compile defines:
//   +define+FIFO_MODULE=<name>  module under test (default sync_fifo)
//   +define+SIM                 enable the DUT's elaboration guard assertion
//   +define+USE_STRUCT          drive a packed-struct type through data_t
//
// Example (Icarus Verilog), run from the fifos/ directory:
//   iverilog -g2012 -DSIM -o sim tb/tb_sync_fifo.sv sync_fifo.sv && vvp sim
//   iverilog -g2012 -DSIM -Ptb_sync_fifo.DEPTH=16 -o sim tb/tb_sync_fifo.sv sync_fifo.sv && vvp sim
//   iverilog -g2012 -DSIM -DUSE_STRUCT -o sim tb/tb_sync_fifo.sv sync_fifo.sv && vvp sim
//   iverilog -g2012 -DSIM -DFIFO_MODULE=sync_fifo_variable_depth -Ptb_sync_fifo.DEPTH=13 \
//            -o sim tb/tb_sync_fifo.sv sync_fifo_variable_depth.sv && vvp sim
//
// Pass criterion: "RESULT: PASS" with errors == 0 and the model fully drained.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

`ifndef FIFO_MODULE
  `define FIFO_MODULE sync_fifo
`endif

module tb_sync_fifo;

  parameter int unsigned WIDTH    = 8;
  parameter int unsigned DEPTH    = 8;
  parameter int unsigned N_CYCLES = 20000;
  parameter int unsigned WR_BIAS  = 50;
  parameter int unsigned RD_BIAS  = 50;

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

  typedef enum int { P_RESET, P_RAND, P_FORCE, P_DRAIN } phase_e;
  phase_e      phase   = P_RESET;
  int unsigned wb      = 50;      // current write bias  (P_RAND)
  int unsigned rb      = 50;      // current read  bias  (P_RAND)
  logic        f_wr    = 0;       // forced i_wr_valid   (P_FORCE)
  logic        f_rd    = 0;       // forced i_rd_ready   (P_FORCE)
  logic        stab_en = 0;       // gate protocol-stability checks

  int unsigned errors   = 0;
  int unsigned n_pushed = 0;
  int unsigned n_popped = 0;

  `FIFO_MODULE #(.WIDTH(WIDTH), .DEPTH(DEPTH), .data_t(DT)) dut (
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

  // Golden reference model. Bit-vectors so the queue is valid for any data_t.
  logic [DW-1:0] model_q [$];

  function automatic DT rand_dt();
    logic [95:0] v = {$urandom, $urandom, $urandom};
    return DT'(v[DW-1:0]);
  endfunction

  // ---------------------------------------------------------------------------
  // Stimulus: inputs driven on negedge so they are stable across each posedge.
  // ---------------------------------------------------------------------------
  always @(negedge clk) begin
    if (!rst_n) begin
      i_wr_valid <= 1'b0;
      i_rd_ready <= 1'b0;
      i_wr_data  <= '0;
    end else begin
      case (phase)
        P_RESET: begin
          i_wr_valid <= 1'b0;
          i_rd_ready <= 1'b0;
          i_wr_data  <= '0;
        end
        P_FORCE: begin
          i_wr_valid <= f_wr;
          i_rd_ready <= f_rd;
          i_wr_data  <= rand_dt();
        end
        P_DRAIN: begin
          i_wr_valid <= 1'b0;
          i_rd_ready <= 1'b1;
        end
        default: begin  // P_RAND
          i_wr_valid <= ($urandom_range(0, 99) < wb);
          i_rd_ready <= ($urandom_range(0, 99) < rb);
          i_wr_data  <= rand_dt();
        end
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // Continuous checks + reference model. Blocking reads at the posedge observe
  // pre-NBA values: exactly the producer/consumer view of the ending cycle.
  // ---------------------------------------------------------------------------
  task automatic continuous_checks();
    if (o_empty !== (model_q.size() == 0)) begin
      $error("[%0t] o_empty=%0b expected=%0b (occupancy %0d)",
             $time, o_empty, (model_q.size() == 0), model_q.size());
      errors++;
    end
    if (o_full !== (model_q.size() == DEPTH)) begin
      $error("[%0t] o_full=%0b expected=%0b (occupancy %0d)",
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
    // FWFT: while data is available the head must be presented on o_rd_data,
    // regardless of i_rd_ready.
    if (o_rd_valid && model_q.size() > 0) begin
      if (DW'(o_rd_data) !== model_q[0]) begin
        $error("[%0t] o_rd_data=0x%0h but queue head=0x%0h",
               $time, o_rd_data, model_q[0]);
        errors++;
      end
    end
  endtask

  // Read-port protocol stability across a single cycle (skipped over resets).
  logic          rv_q = 0;
  logic          rr_q = 0;
  logic [DW-1:0] rd_q = '0;

  always @(posedge clk) begin
    if (stab_en && rst_n) begin
      if (rv_q && !rr_q) begin
        if (!o_rd_valid) begin
          $error("[%0t] o_rd_valid dropped while stalled (no accepted transfer)", $time);
          errors++;
        end
        if (DW'(o_rd_data) !== rd_q) begin
          $error("[%0t] o_rd_data changed while stalled: 0x%0h -> 0x%0h",
                 $time, rd_q, o_rd_data);
          errors++;
        end
      end
    end
    rv_q <= o_rd_valid;
    rr_q <= i_rd_ready;
    rd_q <= DW'(o_rd_data);
  end

  always @(posedge clk) begin
    if (rst_n) begin
      logic [DW-1:0] exp;
      continuous_checks();

      // A read transfer completes on this edge; the consumer captures o_rd_data.
      if (o_rd_valid && i_rd_ready) begin
        if (model_q.size() == 0) begin
          $error("[%0t] read transfer but model empty", $time);
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
          $error("[%0t] write transfer but model full", $time);
          errors++;
        end else begin
          model_q.push_back(DW'(i_wr_data));
          n_pushed++;
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Phase helpers
  // ---------------------------------------------------------------------------
  task automatic apply_reset(int unsigned cyc);
    phase   = P_RESET;
    stab_en = 1'b0;
    rst_n   = 1'b0;
    repeat (cyc) @(negedge clk);
    rst_n = 1'b1;
    model_q.delete();
    @(negedge clk);
    rv_q = 1'b0;
    rr_q = 1'b0;
    @(posedge clk);
    if (!(o_empty && !o_full && o_rd_valid == 1'b0 && o_wr_ready == 1'b1)) begin
      $error("[%0t] unexpected flags after reset: empty=%0b full=%0b rvalid=%0b wready=%0b",
             $time, o_empty, o_full, o_rd_valid, o_wr_ready);
      errors++;
    end
    @(negedge clk);
    stab_en = 1'b1;
  endtask

  task automatic run_rand(int unsigned n, int unsigned w, int unsigned r);
    wb    = w;
    rb    = r;
    phase = P_RAND;
    repeat (n) @(posedge clk);
  endtask

  // Fill to full, hold full with no reads, drain to empty, hold empty.
  task automatic fill_hold_drain();
    phase = P_FORCE;
    f_wr  = 1'b1;
    f_rd  = 1'b0;
    @(negedge clk);
    while (!o_full) @(negedge clk);
    repeat (6) begin
      @(negedge clk);
      if (!o_full) begin
        $error("[%0t] o_full deasserted while held full with no read", $time);
        errors++;
      end
    end
    f_wr = 1'b0;
    f_rd = 1'b1;
    @(negedge clk);
    while (!o_empty) @(negedge clk);
    repeat (6) begin
      @(negedge clk);
      if (!o_empty) begin
        $error("[%0t] o_empty deasserted while held empty with no write", $time);
        errors++;
      end
    end
    phase = P_RAND;
  endtask

  task automatic drain_all();
    phase = P_DRAIN;
    repeat (DEPTH + 20) @(posedge clk);
  endtask

  // ---------------------------------------------------------------------------
  // Test sequence
  // ---------------------------------------------------------------------------
  initial begin
    i_wr_valid = 1'b0;
    i_rd_ready = 1'b0;
    i_wr_data  = '0;

    apply_reset(4);
    run_rand(N_CYCLES,     WR_BIAS, RD_BIAS);  // balanced
    run_rand(N_CYCLES / 2, 90,      15);       // write-heavy: hammers full
    run_rand(N_CYCLES / 2, 15,      90);       // read-heavy:  hammers empty
    fill_hold_drain();                         // directed corners

    run_rand(300, 85, 30);                     // build occupancy, data in flight
    apply_reset(3);                            // mid-sim reset
    run_rand(N_CYCLES / 2, 60, 55);

    drain_all();

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
    #(20 * (3 * N_CYCLES + 4000));
    $display("RESULT: FAIL (timeout)");
    $finish;
  end

endmodule
