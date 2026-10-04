// -----------------------------------------------------------------------------
// tb_packing_gearbox - self-checking testbench for the byte-packing gearbox.
//
//   #(SRC_DATA_WIDTH, DST_DATA_WIDTH) (i_clk, i_reset_n,
//       i_src_data, i_src_byte_en, o_src_ready,
//       o_dst_data, o_dst_valid, i_dst_ready)
//
// A source beat is offered whenever i_src_byte_en != 0 and is taken on a cycle
// with o_src_ready high; the source holds data and enables until then.
//
// Golden model: a byte queue. Each accepted source beat pushes only its enabled
// bytes, in lane order (disabled lanes are driven with garbage to prove they
// are dropped). Each accepted destination word pops DST_DATA_WIDTH/8 bytes,
// little-endian, and must match. Additional checks:
//   - o_dst_valid == (bytes held >= one destination word) every cycle
//   - o_dst_valid / o_dst_data stable while stalled (valid && !ready)
//   - no output while in reset, and a mid-run reset flushes all held bytes
//   - drains completely and never deadlocks (timeout)
//
// Phases: directed masks (all lanes, every single lane, alternating, first /
// last lane), a fill phase with the sink stalled to force source back-pressure,
// a random phase (random masks, idle bubbles, random sink ready), a mid-run
// reset, then a second random phase.
//
// Exercised for upsizing (SRC < DST), downsizing (SRC > DST), equal widths and
// non-power-of-two byte counts by overriding SRC_DATA_WIDTH / DST_DATA_WIDTH.
//
// Run from data_width_convertors/:
//   iverilog -g2012 -o sim tb/tb_packing_gearbox.sv packing_gearbox.sv && vvp sim
//   iverilog -g2012 -Ptb_packing_gearbox.SRC_DATA_WIDTH=128 \
//            -Ptb_packing_gearbox.DST_DATA_WIDTH=32 \
//            -o sim tb/tb_packing_gearbox.sv packing_gearbox.sv && vvp sim
//
// Pass criterion: "RESULT: PASS" (errors == 0, model drained).
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_packing_gearbox;

  parameter int unsigned SRC_DATA_WIDTH = 64;
  parameter int unsigned DST_DATA_WIDTH = 32;
  parameter int unsigned N_BEATS        = 3000;

  localparam int unsigned SRCB = SRC_DATA_WIDTH / 8;
  localparam int unsigned DSTB = DST_DATA_WIDTH / 8;

  logic clk = 0;
  logic rst_n;
  always #5 clk = ~clk;

  logic [SRC_DATA_WIDTH-1:0] i_src_data;
  logic [SRCB-1:0]           i_src_byte_en;
  logic                      o_src_ready;
  logic [DST_DATA_WIDTH-1:0] o_dst_data;
  logic                      o_dst_valid, i_dst_ready;

  packing_gearbox #(
    .SRC_DATA_WIDTH (SRC_DATA_WIDTH),
    .DST_DATA_WIDTH (DST_DATA_WIDTH)
  ) dut (
    .i_clk(clk), .i_reset_n(rst_n),
    .i_src_data(i_src_data), .i_src_byte_en(i_src_byte_en), .o_src_ready(o_src_ready),
    .o_dst_data(o_dst_data), .o_dst_valid(o_dst_valid), .i_dst_ready(i_dst_ready)
  );

  int unsigned errors = 0;
  int unsigned beats_in = 0, words_out = 0, bytes_in = 0, bytes_out = 0;
  int unsigned bp_cycles = 0;   // cycles a beat was offered but not taken

  byte unsigned model [$];
  byte unsigned eb;
  logic prev_ov = 0, prev_ir = 0, in_rst_q = 0;
  logic [DST_DATA_WIDTH-1:0] prev_od = '0;

  // ---- monitor / scoreboard ----
  always @(posedge clk) begin
    if (!rst_n) begin
      model.delete();
      // synchronous reset: outputs are only required clear after the first edge
      if (in_rst_q && o_dst_valid === 1'b1) begin
        errors++; $error("[%0t] o_dst_valid high during reset", $time);
      end
      prev_ov <= 1'b0;
    end else begin
      // valid must reflect occupancy exactly (checked before this edge's updates)
      if (o_dst_valid !== (model.size() >= DSTB)) begin
        errors++;
        $error("[%0t] o_dst_valid=%b but %0d bytes modelled", $time, o_dst_valid, model.size());
      end
      if (prev_ov && !prev_ir) begin
        if (!o_dst_valid)           begin errors++; $error("[%0t] o_dst_valid dropped while stalled", $time); end
        if (o_dst_data !== prev_od) begin errors++; $error("[%0t] o_dst_data moved while stalled", $time); end
      end
      if (o_dst_valid && i_dst_ready) begin
        if (model.size() < DSTB) begin
          errors++; $error("[%0t] output word but only %0d bytes modelled", $time, model.size());
        end else begin
          for (int k = 0; k < DSTB; k++) begin
            eb = model.pop_front();
            if (o_dst_data[8*k +: 8] !== eb) begin
              errors++;
              $error("[%0t] word %0d byte %0d: got %02h exp %02h",
                     $time, words_out, k, o_dst_data[8*k +: 8], eb);
            end
          end
          words_out++; bytes_out += DSTB;
        end
      end
      if (|i_src_byte_en) begin
        if (o_src_ready) begin
          for (int k = 0; k < SRCB; k++)
            if (i_src_byte_en[k]) begin model.push_back(i_src_data[8*k +: 8]); bytes_in++; end
          beats_in++;
        end else begin
          bp_cycles++;
        end
      end
      prev_ov <= o_dst_valid;
    end
    prev_ir <= i_dst_ready; prev_od <= o_dst_data;
    in_rst_q <= !rst_n;
  end

  // ---- source helpers ----
  task automatic send(input logic [SRCB-1:0] en);
    logic [SRC_DATA_WIDTH-1:0] d;
    for (int k = 0; k < SRCB; k++) d[8*k +: 8] = $urandom;   // all lanes random
    @(negedge clk);
    i_src_data    = d;
    i_src_byte_en = en;
    if (en != '0) begin
      @(posedge clk);
      while (!o_src_ready) @(posedge clk);
    end
    @(negedge clk);
    i_src_byte_en = '0;
    i_src_data    = {SRC_DATA_WIDTH{1'bx}};
  endtask

  task automatic send_random(input int unsigned n);
    logic [SRCB-1:0] en;
    for (int unsigned i = 0; i < n; i++) begin
      while ($urandom_range(0, 3) == 0) @(negedge clk);     // idle bubble
      for (int k = 0; k < SRCB; k++) en[k] = $urandom_range(0, 1);
      if ($urandom_range(0, 7) == 0) en = '1;                // bias toward full beats
      send(en);
    end
  endtask

  task automatic drain();
    repeat (8 * (SRCB + DSTB) + 40) @(negedge clk);
  endtask

  // ---- sink: random ready unless forced ----
  logic sink_random = 1'b1;
  logic sink_force  = 1'b1;
  initial begin
    i_dst_ready = 1'b0;
    forever begin
      @(negedge clk);
      i_dst_ready = sink_random ? ($urandom_range(0, 1) == 1) : sink_force;
    end
  end

  // ---- stimulus ----
  initial begin : stim
    i_src_data = '0; i_src_byte_en = '0; rst_n = 1'b0;
    repeat (4) @(negedge clk);
    rst_n = 1'b1;

    // Phase 1: directed masks, sink always ready
    sink_random = 1'b0; sink_force = 1'b1;
    repeat (2) send('1);
    for (int k = 0; k < SRCB; k++) send(SRCB'(1) << k);
    for (int r = 0; r < 4; r++) begin
      for (int k = 0; k < SRCB; k++) send({SRCB{1'b0}} | ({SRCB{1'b1}} >> k));
    end
    begin
      logic [SRCB-1:0] alt;
      for (int k = 0; k < SRCB; k++) alt[k] = k[0];
      repeat (4) begin send(alt); send(~alt); end
    end
    repeat (3) begin send(SRCB'(1)); send(SRCB'(1) << (SRCB - 1)); end
    send('0);                                                // empty beat: no transfer
    drain();

    // Phase 2: sink stalled, push until the source is back-pressured, then release
    sink_force = 1'b0;
    fork
      repeat (4 * (SRCB + DSTB) + 8) send('1);
      begin
        repeat (6 * (SRCB + DSTB) + 40) @(negedge clk);
        sink_force = 1'b1;
      end
    join
    drain();
    if (bp_cycles == 0) begin
      errors++; $error("source was never back-pressured in the fill phase");
    end

    // Phase 3: random
    sink_random = 1'b1;
    send_random(N_BEATS / 2);

    // Phase 4: mid-run reset with data held and a beat still being offered
    // (sink stalled so the queue fills) flushes the queue
    sink_random = 1'b0; sink_force = 1'b0;
    repeat (SRCB + DSTB) begin
      @(negedge clk);
      for (int k = 0; k < SRCB; k++) i_src_data[8*k +: 8] = $urandom;
      i_src_byte_en = '1;
    end
    rst_n = 1'b0;
    repeat (3) @(negedge clk);
    i_src_byte_en = '0;
    i_src_data    = {SRC_DATA_WIDTH{1'bx}};
    rst_n = 1'b1;
    @(negedge clk);
    if (o_dst_valid !== 1'b0) begin errors++; $error("o_dst_valid set after mid-run reset"); end
    sink_random = 1'b1;

    // Phase 5: random again after reset
    send_random(N_BEATS / 2);

    // drain and report
    sink_random = 1'b0; sink_force = 1'b1;
    drain();
    if (model.size() >= DSTB) begin
      errors++; $error("undrained: %0d bytes still modelled", model.size());
    end
    $display("--------------------------------------------------");
    $display("SRC=%0d DST=%0d beats_in=%0d words_out=%0d bytes_in=%0d bytes_out=%0d bp_cycles=%0d errors=%0d",
             SRC_DATA_WIDTH, DST_DATA_WIDTH, beats_in, words_out, bytes_in, bytes_out, bp_cycles, errors);
    if (errors == 0) $display("RESULT: PASS");
    else             $display("RESULT: FAIL");
    $display("--------------------------------------------------");
    $finish;
  end

  initial begin #40_000_000; $error("TIMEOUT"); $finish; end

endmodule
