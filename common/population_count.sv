// This module counts the number of set bits inside
// a data bus. O(log2(N)) critical timing path.
// Only supports power of 2 WIDTHs, users should
// pad with 0s to the nearest power of 2.
module population_count #(
    parameter int unsigned WIDTH = 32,
    localparam int unsigned CNT_W = $clog2(WIDTH) + 1,
    localparam int unsigned NUM_LEVELS = $clog2(WIDTH) + 1
) (
    input logic [WIDTH-1:0] i_data,
    output logic [CNT_W-1:0] o_population_cnt
);

    int unsigned DENOMINATOR;
    int unsigned NUM_PARTIAL_SUMS;

    // Some unused bits
    logic [CNT_W-1:0] partial_sums [0:NUM_LEVELS-1][0:WIDTH-1];

    always_comb begin
        for (int i = 0; i < WIDTH; i++) begin
            partial_sums[0][i] = i_data[i];
        end

        for (int lvl = 1; lvl < NUM_LEVELS; lvl++) begin
            DENOMINATOR = (2 ** lvl);
            NUM_PARTIAL_SUMS = (WIDTH / DENOMINATOR);

            for (int pos = 0; pos < NUM_PARTIAL_SUMS; pos++) begin
                partial_sums[lvl][pos] = partial_sums[(lvl - 1)][(pos * 2)] + partial_sums[(lvl - 1)][((pos * 2) + 1)];
            end

        end

    end

    assign o_population_cnt = partial_sums[NUM_LEVELS-1][0];

`ifdef SIM
    initial assert (((WIDTH) & (WIDTH - 1)) == 0)
        else $fatal(1, "population_count - Must use power of 2 WIDTH parameter. Pad to nearest power of 2 required.");
`endif // SIM

endmodule
