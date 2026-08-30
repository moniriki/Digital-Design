module sync3r #(
    parameter int unsigned WIDTH = 1
) (
    input logic i_clk,
    input logic i_reset_n,
    input logic [WIDTH-1:0] i_d,
    output logic [WIDTH-1:0] o_q
);

`ifndef FOUNDRY_LIBCELL

    logic [WIDTH-1:0] q, qq, qqq;

    always_ff @(posedge i_clk, negedge i_reset_n) begin
        if (~i_reset_n) begin
            q <= '0;
            qq <= '0;
            qqq <= '0;
        end else begin
            q <= i_d;
            qq <= q;
            qqq <= qq;
        end
    end

    assign o_q = qqq;

`endif // FOUNDRY_LIBCELL

endmodule
