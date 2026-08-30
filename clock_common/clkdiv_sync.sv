// Should be used for values of N > 2. Must only be used
// for even N. Odd N requires duty cycle mismatch handling
module clkdiv_sync # (
    parameter int unsigned N = 8,
    localparam int unsigned CNT_W = $clog2(N)
) (
    input logic i_clk,
    input logic i_reset_n,
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

    initial assert ((N >= 2) && ((N & 1) == 0))
        else $fatal(1, "clkdiv_sync - N must be >= 2 and an even number");
endmodule
