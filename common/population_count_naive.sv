// This module (naively) counts the number of set bits inside
// a data bus. The better timing critical path approach is to
// use the population_count module instead, which implements
// this in a binary-tree like fashion to cut the critical
// timing path to O(log2(WIDTH)) instead of O(N).
module population_count_naive #(
    parameter int unsigned WIDTH = 32,
    localparam int unsigned CNT_W = $clog2(WIDTH) + 1
) (
    input logic [WIDTH-1:0] i_data,
    output logic [CNT_W-1:0] o_population_cnt
);

    always_comb begin
        o_population_cnt = '0;

        for (int unsigned i = 0; i < WIDTH; i++) begin
            o_population_cnt += i_data[i];
        end
    end

endmodule