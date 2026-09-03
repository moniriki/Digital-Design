module lfsr # (
    parameter int unsigned WIDTH = 4
) (
    input logic i_clk,
    input logic i_reset_n,
    input logic [WIDTH-1:0] i_seed,

    output logic [WIDTH-1:0] o_lfsr
);

    logic [WIDTH-1:0] lfsr_reg;

    always_ff @(posedge i_clk) begin
        if (~i_reset_n) begin
            lfsr_reg <= i_seed;
        end else begin
            lfsr_reg <= {lfsr_reg[0 +: WIDTH-1], lfsr_reg[WIDTH-2] ^ lfsr_reg[WIDTH-1]};
        end
    end

    assign o_lfsr = lfsr_reg;

endmodule
