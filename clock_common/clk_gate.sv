module clk_gate (
    input logic i_clk,
    input logic i_en,
    output logic o_clk
);

`ifdef FOUNDRY_LIBCELL

    libcell_clkgate clkgate (
        .i_CK(i_clk),
        .i_E(i_en),
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
