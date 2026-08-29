// -----------------------------------------------------------------------------
// tb_async_hs — self-checking CDC testbench for an async handshake synchronizer
//
// Drives any module with this valid/ready-across-clock-domains interface:
//   #(dtype_t) (i_src_clk, i_src_reset_n, i_valid, i_data, o_ready,
//               i_dst_clk, i_dst_reset_n, o_valid, i_ready, o_data)
// The module under test is selected by the HS_MODULE macro
// (default async_4_phase_hs); override to test a variant.
//
// Independent src/dst clocks (periods SRC_PS / DST_PS, read clock given a small
// odd phase offset so the two clock edges never coincide -> the shared golden
// queue is race-free). A plain FIFO queue is the golden model: the src monitor
// pushes every accepted transfer (i_valid && o_ready), the dst monitor pops on
// every accepted transfer (o_valid && i_ready) and checks data + order.
//
// The dst stimulus periodically holds i_ready low for a long stretch while a
// transfer is pending, to exercise the ack-hold / data-stability path (a
// random ready alone rarely stalls long enough).
//
// Parameters (override with -P<tb>.NAME=value):
//   DW, SRC_PS, DST_PS, N_XFERS, SRC_BIAS, DST_BIAS
//
// Example (Icarus Verilog), from the synchronizers/ directory:
//   iverilog -g2012 -o sim tb/tb_async_hs.sv async_4_phase_hs.sv sync3.sv && vvp sim
//   iverilog -g2012 -Ptb_async_hs.SRC_PS=3000 -Ptb_async_hs.DST_PS=30000 \
//            -o sim tb/tb_async_hs.sv async_4_phase_hs.sv sync3.sv && vvp sim
//
// Pass criterion: "RESULT: PASS" (errors == 0, model drained, sent == recv).
// -----------------------------------------------------------------------------
`timescale 1ps/1ps

`ifndef HS_MODULE
  `define HS_MODULE async_4_phase_hs
`endif

module tb_async_hs;
  parameter int unsigned DW       = 8;
  parameter int unsigned SRC_PS   = 7000;
  parameter int unsigned DST_PS   = 11000;
  parameter int unsigned N_XFERS  = 500;
  parameter int unsigned SRC_BIAS = 60;   // % src cycles i_valid asserted
  parameter int unsigned DST_BIAS = 55;   // % dst cycles i_ready asserted

  logic sclk = 0, dclk = 0, srn, drn;
  logic            iv, ordy;
  logic [DW-1:0]   idata;
  logic            ov, irdy;
  logic [DW-1:0]   odata;

  `HS_MODULE #(.dtype_t(logic [DW-1:0])) dut (
    .i_src_clk(sclk), .i_src_reset_n(srn),
    .i_valid(iv), .i_data(idata), .o_ready(ordy),
    .i_dst_clk(dclk), .i_dst_reset_n(drn),
    .o_valid(ov), .i_ready(irdy), .o_data(odata)
  );

  always #(SRC_PS/2) sclk = ~sclk;
  initial begin #3; forever #(DST_PS/2) dclk = ~dclk; end

  logic [DW-1:0] model [$];
  int unsigned n_sent = 0, n_recv = 0, errors = 0;
  bit src_done = 0;

  // src stimulus + monitor
  always @(posedge sclk) begin
    if (!srn) iv <= 1'b0;
    else if (src_done) iv <= 1'b0;
    else begin
      iv    <= ($urandom_range(0,99) < SRC_BIAS);
      idata <= $urandom;
    end
  end
  always @(posedge sclk) begin
    if (srn && iv && ordy) begin
      model.push_back(idata);
      n_sent++;
    end
  end

  // dst stimulus (with periodic long ready-low stalls) + monitor
  int rdy_stall = 0;
  always @(posedge dclk) begin
    if (!drn) irdy <= 1'b0;
    else if (rdy_stall > 0) begin irdy <= 1'b0; rdy_stall <= rdy_stall - 1; end
    else if ($urandom_range(0,499) == 0) begin irdy <= 1'b0; rdy_stall <= 20; end
    else irdy <= ($urandom_range(0,99) < DST_BIAS);
  end
  always @(posedge dclk) begin
    if (drn && ov && irdy) begin
      logic [DW-1:0] exp;
      if (model.size() == 0) begin
        $error("[%0t] dst accepted but model empty (duplicate/spurious)", $time);
        errors++;
      end else begin
        exp = model.pop_front();
        if (odata !== exp) begin
          $error("[%0t] DATA MISMATCH: o_data=%h expected=%h", $time, odata, exp);
          errors++;
        end
        n_recv++;
      end
    end
  end

  initial begin
    srn = 0; drn = 0; iv = 0; idata = 0; irdy = 0;
    repeat (6) @(posedge sclk);
    repeat (6) @(posedge dclk);
    @(negedge sclk) srn = 1;
    @(negedge dclk) drn = 1;

    fork
      begin wait (n_sent >= N_XFERS); src_done = 1; end
      begin repeat (500 * N_XFERS) @(posedge dclk);
            $error("[%0t] STALL: n_sent=%0d n_recv=%0d (target %0d)", $time, n_sent, n_recv, N_XFERS);
            errors++; end
    join_any
    disable fork;

    fork
      begin wait (n_recv == n_sent); end
      begin repeat (4000) @(posedge dclk);
            $error("[%0t] drain stall: n_recv=%0d n_sent=%0d", $time, n_recv, n_sent);
            errors++; end
    join_any
    disable fork;

    repeat (20) @(posedge dclk);
    $display("--------------------------------------------------");
    $display("SRC=%0dps DST=%0dps  sent=%0d recv=%0d model_left=%0d errors=%0d",
             SRC_PS, DST_PS, n_sent, n_recv, model.size(), errors);
    if (errors == 0 && model.size() == 0 && n_sent == n_recv && n_sent >= N_XFERS)
      $display("RESULT: PASS");
    else
      $display("RESULT: FAIL");
    $display("--------------------------------------------------");
    $finish;
  end
endmodule
