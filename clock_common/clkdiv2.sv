module clkdiv2 (
    input logic i_clk,
    input logic i_reset_n,
    output logic o_clk
);
    logic clk_div_2;

`ifdef FOUNDRY_LIBCELL

    libcell_std_inv inv (
        .i_A(o_clk),
        .o_Y(clk_div_2)
    );

    libcell_std_dffr clk_div_2_reg (
        .i_D(clk_div_2),
        .i_CK(i_clk),
        .i_RN(i_reset_n),
        .o_Q(o_clk)
    );

`else

    always_ff @(posedge i_clk, negedge i_reset_n) begin
        if (~i_reset_n) begin
            clk_div_2 <= 1'b0;
        end else begin
            clk_div_2 <= ~clk_div_2;
        end
    end

    assign o_clk = clk_div_2;

`endif // FOUNDRY_LIBCELL
endmodule
