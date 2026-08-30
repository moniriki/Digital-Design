// Bare combinational 4:1 clock mux, built as a tree of clkmux2:
// o_clk = i_clk[i_sel].
//
// WARNING (inherited from clkmux2): switching i_sel glitches the output even
// with a perfectly clean, single-source select. The select edge lands at an
// arbitrary phase relative to the clocks, so the switch chops the in-progress
// pulse / creates a partial pulse -> a runt on o_clk that makes downstream
// flops double-clock or capture garbage.
//
// ADDITIONAL hazard, specific to the 2-bit select: a transition that changes
// BOTH select bits (01<->10, 00<->11 -- i.e. switching between the two clock
// pairs) is unsafe. The two bits do not switch simultaneously, so i_sel passes
// through an intermediate code and o_clk briefly routes a THIRD, unselected
// clock:
//   sel 01 -> 10 : if sel[0] falls first  -> passes 00 -> o_clk = i_clk[0]
//                  if sel[1] rises first  -> passes 11 -> o_clk = i_clk[3]
//
// Only safe to use when:
//   1. every clock not currently selected is static (held 0) at switch time; or
//   2. i_sel changes are constrained to SINGLE-BIT transitions only
//      (00<->01, 00<->10, 01<->11, 10<->11), and a single output glitch on
//      that switch is acceptable; or
//   3. downstream logic is held in reset across the switch.
//
// For runtime switching between live clocks, use a glitchless 4:1 clock mux
// (four cross-coupled, per-clock negedge-synchronized enables so only one clock
// is ever enabled), or a tree of glitchless 2:1 muxes. All participating clocks
// must be running for the handover to complete.
module clkmux4 (
    input logic [3:0] i_clk,
    input logic [1:0] i_sel,
    output logic o_clk
);

    logic [1:0] internal_clk;

    clkmux2 mux0 (
        .i_clk0(i_clk[0]),
        .i_clk1(i_clk[1]),
        .i_sel(i_sel[0]),
        .o_clk(internal_clk[0])
    );

    clkmux2 mux1 (
        .i_clk0(i_clk[2]),
        .i_clk1(i_clk[3]),
        .i_sel(i_sel[0]),
        .o_clk(internal_clk[1])
    );

    clkmux2 mux2 (
        .i_clk0(internal_clk[0]),
        .i_clk1(internal_clk[1]),
        .i_sel(i_sel[1]),
        .o_clk(o_clk)
    );

endmodule
