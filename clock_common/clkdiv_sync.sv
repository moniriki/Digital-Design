// Divide-by-N clock from a single counter (not a chain of clkdiv2), so o_clk
// has one clock-to-Q of delay from i_clk regardless of N -- unlike clkdiv4 /
// clkdiv8, whose cascaded flops add skew down the tree.
//
// N >= 2, even or odd. For even N the counter runs 0..N/2-1 and the output
// toggles each wrap, giving an exact 50% duty clock at i_clk/N. For odd N, a
// single half-period can't split N evenly, so the two half-periods alternate
// between floor(N/2) and ceil(N/2) (selected by half_toggle, flipped
// alongside the output on every wrap); every full period still sums to
// exactly N input clocks, at the cost of a one-cycle duty asymmetry between
// the two half-phases instead of a perfect 50%.
module clkdiv_sync #(
    parameter  int unsigned N       = 8,
    localparam int unsigned CNT_W   = $clog2(N),
    localparam int unsigned HALF_LO = N / 2,
    localparam int unsigned HALF_HI = HALF_LO + (N % 2)
) (
    input  logic i_clk,
    input  logic i_reset_n,
    output logic o_clk
);

    logic [CNT_W-1:0] clk_cnt;
    logic [CNT_W-1:0] half_period;
    logic toggle;
    logic half_toggle;

    assign half_period = half_toggle ? CNT_W'(HALF_HI) : CNT_W'(HALF_LO);

    always_ff @(posedge i_clk, negedge i_reset_n) begin
        if (~i_reset_n) begin
            clk_cnt     <= CNT_W'(0);
            toggle      <= 1'b0;
            half_toggle <= 1'b0;
        end else begin
            if (clk_cnt == (half_period - 1'b1)) begin
                clk_cnt     <= CNT_W'(0);
                toggle      <= ~toggle;
                half_toggle <= ~half_toggle;
            end else begin
                clk_cnt <= clk_cnt + 1'b1;
            end
        end
    end

    assign o_clk = toggle;

`ifdef SIM
    initial assert (N >= 2)
        else $fatal(1, "clkdiv_sync: N must be >= 2");
`endif
endmodule
