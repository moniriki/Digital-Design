// clkdiv_sync should be used instead of this module
// to avoid cascading clock->Q delay in the clock tree

module clkdiv4 (
    input logic i_clk,
    input logic i_reset_n,
    output logic o_clk
);

    logic clk_div_2, clk_div_4;

    clkdiv2 div_2 (
        .i_clk(i_clk),
        .i_reset_n(i_reset_n),
        .o_clk(clk_div_2)
    );

    clkdiv2 div_4 (
        .i_clk(clk_div_2),
        .i_reset_n(i_reset_n),
        .o_clk(clk_div_4)
    );

    assign o_clk = clk_div_4;

endmodule
