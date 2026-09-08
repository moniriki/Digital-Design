// Clock inverter. Trivial in RTL; exists as a named cell so the clock tree can
// be built from explicit primitives and the FOUNDRY_LIBCELL flow can swap in a
// real clock-inverter cell at this boundary.
module clkinv (
    input  logic i_clk,
    output logic o_clk
);

    assign o_clk = ~i_clk;

endmodule
