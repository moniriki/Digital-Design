module clkinv (
    input logic i_clk,
    output logic o_clk
);

    assign o_clk = ~i_clk;

endmodule
