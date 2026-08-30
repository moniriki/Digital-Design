// Glitchless 2:1 clock mux (cross-coupled select design).
//
// Each clock has a "select" flop clocked by that clock, whose assertion is
// gated by "the other clock is not selected" (synchronized from the other
// domain). The cross-coupling guarantees only one clock is ever gated on, and
// each clkgate is fed a select that is stable in its own domain, so switching
// produces no runt pulse -- there is a brief dead window (both gates off)
// during the handover, then the new clock comes up cleanly.
//
// Usage constraints:
//   * i_sel is a QUASI-STATIC control. Hold it stable for at least
//     ~2 * (synchronizer depth) + a few cycles of BOTH clocks between changes.
//     Toggling it faster leaves the cross-coupled feedback mid-flight, breaks
//     mutual exclusion, and glitches o_clk.
//   * BOTH clocks must be running for a switch to complete. If the target
//     clock is stopped, the handover never finishes: o_clk parks off (low)
//     until that clock returns, then the switch completes.
//   * After reset, i_clk0 is selected (sel_clk0 resets to 1). The reset values
//     of the synchronized copies are made consistent via sync3s (set to 1) on
//     the clk0 path and sync3r (reset to 0) on the clk1 path.
//
// For a glitch on i_sel to be acceptable is NOT a valid use of this module --
// that is what clkmux2 is for. Use this when o_clk must stay clean across the
// switch and downstream logic keeps running.
module anti_glitch_clkmux (
    input logic i_clk0,
    input logic i_clk1,
    input logic i_reset_n, // async reset
    input logic i_sel,
    output logic o_clk
);

    // Select handshake
    logic sel_clk0, sel_clk0_sync;
    logic sel_clk1, sel_clk1_sync;

    logic clk0_gated, clk1_gated;

    // Clock0 select flop
    always_ff @(posedge i_clk0, negedge i_reset_n) begin
        if (~i_reset_n) begin
            sel_clk0 <= 1'b1;
        end else begin
            sel_clk0 <= ~i_sel && ~sel_clk1_sync;
        end
    end

    // Clock1 select flop
    always_ff @(posedge i_clk1, negedge i_reset_n) begin
        if (~i_reset_n) begin
            sel_clk1 <= 1'b0;
        end else begin
            sel_clk1 <= i_sel && ~sel_clk0_sync;
        end
    end

    sync3s sync_sel_clk0 (
        .i_clk(i_clk1),
        .i_reset_n(i_reset_n),
        .i_d(sel_clk0),
        .o_q(sel_clk0_sync)
    );

    sync3r sync_sel_clk1 (
        .i_clk(i_clk0),
        .i_reset_n(i_reset_n),
        .i_d(sel_clk1),
        .o_q(sel_clk1_sync)
    );

    // Clock gaters

    clkgate clk0_gate (
        .i_clk(i_clk0),
        .i_en(sel_clk0),
        .o_clk(clk0_gated)
    );

    clkgate clk1_gate (
        .i_clk(i_clk1),
        .i_en(sel_clk1),
        .o_clk(clk1_gated)
    );

    // Final clock generation
    clkor clk_gf (
        .i_clk0(clk0_gated),
        .i_clk1(clk1_gated),
        .o_clk(o_clk)
    );

endmodule
