// Divide-by-N clock from a single counter (not a chain of clkdiv2), so o_clk
// has one clock-to-Q of delay from i_clk regardless of N -- unlike clkdiv4 /
// clkdiv8, whose cascaded flops add skew down the tree.
//
// N must be even and >= 2 (checked below): the counter runs 0..N/2-1 and the
// output toggles each wrap, giving a 50% duty clock at i_clk/N. Odd N would
// need explicit duty-cycle handling and is not supported.
module clkdiv_sync #(
    parameter  int unsigned N     = 8,
    localparam int unsigned CNT_W = $clog2(N)
) (
    input  logic i_clk,
    input  logic i_reset_n,
    output logic o_clk
);

    logic [CNT_W-1:0] clk_cnt;
    logic toggle;

    always_ff @(posedge i_clk, negedge i_reset_n) begin
        if (~i_reset_n) begin
            clk_cnt <= CNT_W'(0);
            toggle <= 1'b0;
        end else begin
            clk_cnt <= (clk_cnt == CNT_W'((N / 2) - 1)) ? CNT_W'(0) : clk_cnt + 1'b1;
            toggle <= (clk_cnt == '0) ? ~toggle : toggle;
        end
    end

    assign o_clk = toggle;

`ifdef SIM
    initial assert ((N >= 2) && ((N & 1) == 0))
        else $fatal(1, "clkdiv_sync: N must be an even number >= 2");
`endif
endmodule
