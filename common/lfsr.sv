// Fibonacci (external-XOR) linear-feedback shift register.
//
// Each cycle the register shifts left and the new LSB is the XOR of the top two
// bits (fixed taps at WIDTH-1 and WIDTH-2). That tap pair is a primitive
// polynomial only for WIDTH in {2, 3, 4, 6, 7}; there a non-zero seed walks all
// 2**WIDTH-1 non-zero states before repeating. Other widths give a shorter,
// non-maximal cycle (e.g. WIDTH 5 -> period 21, WIDTH 8 -> period 63) and would
// need a width-specific tap set for a maximal sequence.
//
// The all-zeros state is a lock-up (XOR of zeros stays zero), so i_seed must be
// non-zero -- it is loaded synchronously while i_reset_n is low.
module lfsr #(
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
