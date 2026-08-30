// Glitch-free clock gate: low-phase enable latch + AND.
//
// latch_enable is a level-sensitive latch, transparent while i_clk is low and
// opaque while i_clk is high. Because i_en can only reach the AND gate while
// i_clk is 0, the gated clock never sees a partial pulse -> o_clk starts and
// stops only on clean full-period boundaries. latch_enable MUST be a storage
// element (latch, or a negedge flop); if it were combinational, i_en toggling
// during the high phase would glitch o_clk.
//
// FOUNDRY_LIBCELL: instantiate the library integrated clock-gating cell
// instead (placeholder name/pins -- remap to the real cell, e.g. CKLNQD*).
module clkgate (
    input  logic i_clk,
    input  logic i_en,
    output logic o_clk
);

`ifdef FOUNDRY_LIBCELL

    libcell_clkgate u_icg (
        .i_CK(i_clk),
        .i_E (i_en),
        .o_CK(o_clk)
    );

`else

    logic latch_enable;

    always_latch begin
        if (~i_clk) begin
            latch_enable = i_en;
        end
    end

    assign o_clk = i_clk & latch_enable;

`endif // FOUNDRY_LIBCELL

endmodule
