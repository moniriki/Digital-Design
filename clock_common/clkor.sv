// Clock OR: o_clk = i_clk0 | i_clk1.
//
// Intended to merge two mutually-exclusive gated clocks (e.g. the two branches
// of a glitchless clock mux, where cross-coupled enables guarantee at most one
// input is toggling at a time). The plain OR is glitch-free only under that
// mutual-exclusion guarantee; ORing two independently running clocks produces
// merged/runt pulses.
//
// FOUNDRY_LIBCELL: instantiate the library clock-OR / combinational clock cell
// instead (placeholder name/pins -- remap to the real cell).
module clkor (
    input  logic i_clk0,
    input  logic i_clk1,
    output logic o_clk
);

`ifdef FOUNDRY_LIBCELL

    libcell_clkor u_ckor (
        .i_CK0(i_clk0),
        .i_CK1(i_clk1),
        .o_CK (o_clk)
    );

`else

    assign o_clk = i_clk0 | i_clk1;

`endif // FOUNDRY_LIBCELL

endmodule
