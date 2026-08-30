// Bare combinational 2:1 clock mux: o_clk = i_sel ? i_clk1 : i_clk0.
//
// WARNING: this glitches on the output even with a perfectly clean,
// single-source i_sel. The select edge lands at an arbitrary phase relative
// to i_clk0 and i_clk1, so switching chops whatever pulse is in progress on
// the "from" clock, or creates a partial pulse on the "to" clock -> a runt /
// sub-minimum-width pulse on o_clk, which makes downstream flops double-clock
// or capture garbage. A non-glitching i_sel is necessary but NOT sufficient.
//
// Only safe to use when:
//   1. one clock is guaranteed static (held at 0, not toggling) at the moment
//      of the switch  -- no pulse to chop; or
//   2. i_sel is constrained to change only while both clocks are low (which is
//      essentially re-implementing a glitchless mux); or
//   3. a single output glitch is acceptable -- e.g. a debug/observation clock,
//      or downstream logic held in reset across the switch.
//
// For runtime switching between two LIVE clocks, use a glitchless clock mux
// (per-clock negedge-synchronized enables, cross-coupled so only one clock is
// ever enabled, each gated on/off in sync with its own clock). Both clocks
// must be running for the handover to complete; the output has a brief low
// dead-window but no runt pulses.

module clkmux2 (
    input logic i_clk0,
    input logic i_clk1,
    input logic i_sel,
    output logic o_clk
);

    assign o_clk = i_sel ? i_clk1 : i_clk0;

endmodule
