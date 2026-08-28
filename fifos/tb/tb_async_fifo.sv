// -----------------------------------------------------------------------------
// tb_async_fifo — self-checking CDC testbench for async_fifo
//
// Independent write / read clocks (periods set by WR_CLK_PS / RD_CLK_PS, with a
// small odd phase offset on the read clock so the two clock edges never land on
// the same simulation timestep — this makes the shared golden queue race-free
// without a mailbox).
//
// A plain FIFO queue is the golden model: the write monitor pushes every
// accepted write, the read monitor pops on every accepted read and compares.
//
// Checks:
//   - data integrity and ordering across the clock-domain crossing
//   - no overflow: outstanding (written - read) never exceeds DEPTH
//     (i.e. o_full / o_wr_ready is never optimistic)
//   - no underflow: a read never fires with the model empty
//     (i.e. o_rd_valid / o_empty is never optimistic)
//   - o_wr_ready == !o_full, o_rd_valid == !o_empty, flags never X after reset
//   - write/read Gray pointers change by at most one bit per source clock
//     (validates the Gray encoding feeding the synchronizers)
//   - after draining, the model is empty and writes == reads
//
// Parameters (override with -P<tb>.NAME=value):
//   WIDTH, DEPTH, N_WRITES, WR_CLK_PS, RD_CLK_PS, WR_BIAS, RD_BIAS
//
// Example (Icarus Verilog), run from the fifos/ directory:
//   iverilog -g2012 -o sim tb/tb_async_fifo.sv async_fifo.sv ../synchronizers/sync3.sv && vvp sim
//   iverilog -g2012 -Ptb_async_fifo.WR_CLK_PS=4000 -Ptb_async_fifo.RD_CLK_PS=20000 \
//            -o sim tb/tb_async_fifo.sv async_fifo.sv ../synchronizers/sync3.sv && vvp sim
//
// Pass criterion: "RESULT: PASS" with errors == 0 and the model fully drained.
// -----------------------------------------------------------------------------
`timescale 1ps/1ps

module tb_async_fifo;

  parameter int unsigned WIDTH     = 16;
  parameter int unsigned DEPTH     = 8;
  parameter int unsigned N_WRITES  = 20000;
  parameter int unsigned WR_CLK_PS = 7000;    // must be a multiple of 4
  parameter int unsigned RD_CLK_PS = 11000;   // must be a multiple of 4
  parameter int unsigned RD_PHASE  = 13;      // odd -> read edges never meet write edges
  parameter int unsigned WR_BIAS   = 60;      // % of write cycles i_wr_valid asserted
  parameter int unsigned RD_BIAS   = 55;      // % of read  cycles i_rd_ready asserted

  localparam int unsigned CNT_W = $clog2(DEPTH);

  logic wr_clk = 0, rd_clk = 0;
  logic wr_rst_n, rd_rst_n;

  logic             i_wr_valid, o_wr_ready;
  logic [WIDTH-1:0] i_wr_data;
  logic             o_rd_valid, i_rd_ready;
  logic [WIDTH-1:0] o_rd_data;
  logic             o_full, o_empty;

  int unsigned cur_wb   = 60;   // current write bias, set by the sequencer
  int unsigned cur_rb   = 55;   // current read  bias, set by the sequencer
  int unsigned n_wr     = 0;
  int unsigned n_rd     = 0;
  int unsigned errors   = 0;
  int unsigned max_occ  = 0;

  async_fifo #(.WIDTH(WIDTH), .DEPTH(DEPTH)) dut (
    .i_wr_clk     (wr_clk),
    .i_wr_reset_n (wr_rst_n),
    .i_wr_valid   (i_wr_valid),
    .o_wr_ready   (o_wr_ready),
    .i_wr_data    (i_wr_data),
    .i_rd_clk     (rd_clk),
    .i_rd_reset_n (rd_rst_n),
    .o_rd_valid   (o_rd_valid),
    .i_rd_ready   (i_rd_ready),
    .o_rd_data    (o_rd_data),
    .o_full       (o_full),
    .o_empty      (o_empty)
  );

  // Clocks. Write edges on even ps, read edges on odd ps -> never coincident.
  always #(WR_CLK_PS/2) wr_clk = ~wr_clk;
  initial begin
    #(RD_PHASE);
    forever #(RD_CLK_PS/2) rd_clk = ~rd_clk;
  end

  // Golden model queue (race-free: producer and consumer never run in the same
  // timestep because the clock edges never coincide).
  logic [WIDTH-1:0] model [$];

  // ---------------------------------------------------------------------------
  // Reset (both domains together)
  // ---------------------------------------------------------------------------
  initial begin
    wr_rst_n   = 0;
    rd_rst_n   = 0;
    i_wr_valid = 0;
    i_wr_data  = '0;
    i_rd_ready = 0;
    repeat (5) @(posedge wr_clk);
    repeat (5) @(posedge rd_clk);
    @(negedge wr_clk) wr_rst_n = 1;
    @(negedge rd_clk) rd_rst_n = 1;
  end

  // ---------------------------------------------------------------------------
  // Write domain: stimulus + monitor
  // ---------------------------------------------------------------------------
  always @(posedge wr_clk) begin
    if (!wr_rst_n) begin
      i_wr_valid <= 1'b0;
    end else begin
      i_wr_valid <= ($urandom_range(0, 99) < cur_wb);
      i_wr_data  <= WIDTH'($urandom);
    end
  end

  always @(posedge wr_clk) begin
    if (wr_rst_n) begin
      if (o_full === 1'bx || o_wr_ready === 1'bx) begin
        $error("[%0t] wr-side flag is X (full=%b wr_ready=%b)", $time, o_full, o_wr_ready);
        errors++;
      end
      if (o_wr_ready !== !o_full) begin
        $error("[%0t] o_wr_ready=%b but o_full=%b", $time, o_wr_ready, o_full);
        errors++;
      end
      if (i_wr_valid && o_wr_ready) begin
        model.push_back(i_wr_data);
        n_wr++;
        if (model.size() > max_occ) max_occ = model.size();
        if (model.size() > DEPTH) begin
          $error("[%0t] OVERFLOW: outstanding=%0d > DEPTH=%0d (o_full was optimistic)",
                 $time, model.size(), DEPTH);
          errors++;
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Read domain: stimulus + monitor
  // ---------------------------------------------------------------------------
  always @(posedge rd_clk) begin
    if (!rd_rst_n) i_rd_ready <= 1'b0;
    else           i_rd_ready <= ($urandom_range(0, 99) < cur_rb);
  end

  always @(posedge rd_clk) begin
    if (rd_rst_n) begin
      logic [WIDTH-1:0] exp;
      if (o_empty === 1'bx || o_rd_valid === 1'bx) begin
        $error("[%0t] rd-side flag is X (empty=%b rd_valid=%b)", $time, o_empty, o_rd_valid);
        errors++;
      end
      if (o_rd_valid !== !o_empty) begin
        $error("[%0t] o_rd_valid=%b but o_empty=%b", $time, o_rd_valid, o_empty);
        errors++;
      end
      if (o_rd_valid && i_rd_ready) begin
        if (model.size() == 0) begin
          $error("[%0t] UNDERFLOW: read fired but model empty (o_empty was optimistic)", $time);
          errors++;
        end else begin
          exp = model.pop_front();
          if (o_rd_data !== exp) begin
            $error("[%0t] DATA MISMATCH: o_rd_data=0x%0h expected=0x%0h", $time, o_rd_data, exp);
            errors++;
          end
          n_rd++;
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Gray-pointer sanity: at most one bit changes per source clock.
  // (Hamming distance <= 1  <=>  xor is zero or a single power of two.
  //  Avoids $countones, which Icarus computes incorrectly for 4-state values.)
  // ---------------------------------------------------------------------------
  function automatic bit hdist_le1(input logic [CNT_W:0] a, input logic [CNT_W:0] b);
    logic [CNT_W:0] x = a ^ b;
    if ((^x) === 1'bx) return 1'b1;           // ignore X (reset / uninitialised)
    return (x == '0) || ((x & (x - 1)) == '0);
  endfunction

  logic [CNT_W:0] wg_q;
  bit             wg_has = 0;
  always @(posedge wr_clk) begin
    if (wr_rst_n) begin
      if (wg_has && !hdist_le1(dut.wr_side_wr_ptr_g, wg_q)) begin
        $error("[%0t] write Gray pointer changed >1 bit: 0x%0h -> 0x%0h",
               $time, wg_q, dut.wr_side_wr_ptr_g);
        errors++;
      end
      wg_q   <= dut.wr_side_wr_ptr_g;
      wg_has <= 1'b1;
    end
  end

  logic [CNT_W:0] rg_q;
  bit             rg_has = 0;
  always @(posedge rd_clk) begin
    if (rd_rst_n) begin
      if (rg_has && !hdist_le1(dut.rd_side_rd_ptr_g, rg_q)) begin
        $error("[%0t] read Gray pointer changed >1 bit: 0x%0h -> 0x%0h",
               $time, rg_q, dut.rd_side_rd_ptr_g);
        errors++;
      end
      rg_q   <= dut.rd_side_rd_ptr_g;
      rg_has <= 1'b1;
    end
  end

  // ---------------------------------------------------------------------------
  // Sequence
  // ---------------------------------------------------------------------------
  initial begin
    int guard;
    wait (wr_rst_n && rd_rst_n);

    // Phase 1: balanced
    cur_wb = WR_BIAS; cur_rb = RD_BIAS;
    wait (n_wr >= N_WRITES / 4);

    // Phase 2: write-heavy (pressure toward full)
    cur_wb = 95; cur_rb = 20;
    wait (n_wr >= N_WRITES / 2);

    // Phase 3: read-heavy (pressure toward empty — exercises the empty-side
    // pointer decode regardless of clock ratio)
    cur_wb = 20; cur_rb = 95;
    wait (n_wr >= (3 * N_WRITES) / 4);

    // Phase 4: directed fill-to-full / drain-to-empty bursts (drives the
    // pointers through their whole range including the wrap point)
    repeat (4) begin
      cur_wb = 100; cur_rb = 0;
      guard = 0;
      while (!o_full && guard < 10000) begin @(posedge wr_clk); guard++; end
      if (!o_full) begin $error("[%0t] never reached o_full in directed fill", $time); errors++; end
      repeat (8) @(posedge wr_clk);
      cur_wb = 0; cur_rb = 100;
      guard = 0;
      while (!o_empty && guard < 10000) begin @(posedge rd_clk); guard++; end
      if (!o_empty) begin $error("[%0t] never reached o_empty in directed drain", $time); errors++; end
      repeat (8) @(posedge rd_clk);
    end

    // Phase 5: balanced again to the target count
    cur_wb = WR_BIAS; cur_rb = RD_BIAS;
    wait (n_wr >= N_WRITES);

    // Final drain
    cur_wb = 0; cur_rb = 100;
    fork
      begin
        wait (o_empty && model.size() == 0);
      end
      begin
        repeat (20000) @(posedge rd_clk);
        $error("[%0t] drain timeout: model has %0d, o_empty=%b", $time, model.size(), o_empty);
        errors++;
      end
    join_any
    disable fork;

    repeat (32) @(posedge rd_clk);

    if (model.size() != 0) begin
      $error("model not drained: %0d left", model.size());
      errors++;
    end
    if (n_wr != n_rd) begin
      $error("count mismatch: n_wr=%0d n_rd=%0d", n_wr, n_rd);
      errors++;
    end

    $display("--------------------------------------------------");
    $display("WR_CLK=%0dps RD_CLK=%0dps  n_wr=%0d n_rd=%0d max_occ=%0d/%0d errors=%0d",
             WR_CLK_PS, RD_CLK_PS, n_wr, n_rd, max_occ, DEPTH, errors);
    if (errors == 0 && model.size() == 0 && n_wr == n_rd)
      $display("RESULT: PASS");
    else
      $display("RESULT: FAIL");
    $display("--------------------------------------------------");
    $finish;
  end

  // Global watchdog. longint math to avoid the 32-bit overflow a plain
  // (N_WRITES * period) delay would hit for large N_WRITES.
  initial begin
    longint unsigned slow_ps;
    slow_ps = (WR_CLK_PS > RD_CLK_PS) ? WR_CLK_PS : RD_CLK_PS;
    #(200_000 + 12 * longint'(N_WRITES) * slow_ps);
    $display("RESULT: FAIL (global watchdog: n_wr=%0d n_rd=%0d model=%0d)",
             n_wr, n_rd, model.size());
    $finish;
  end

endmodule
