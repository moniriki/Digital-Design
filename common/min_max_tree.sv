// Finds the unsigned minimum or maximum of a data bus.
// Only supports power of 2 datums. Pad with 0 to the
// nearest power of 2.
module min_max_tree # (
    parameter int unsigned NUM_DATA = 32,
    parameter int unsigned DATA_WIDTH = 32,
    parameter bit          MIN_FUNCTION = 1, // 1 -> minimum; 0 -> maximum
    localparam int unsigned TREE_LEVELS = $clog2(NUM_DATA) + 1
) (
    input logic [DATA_WIDTH-1:0] i_data [0:NUM_DATA-1],
    output logic [DATA_WIDTH-1:0] o_min_max
);

    int unsigned MAX_POSITIONS;

    logic [DATA_WIDTH-1:0] partial_min_max [0:TREE_LEVELS-1][0:NUM_DATA-1];
    logic [DATA_WIDTH-1:0] a, b;
    always_comb begin
        a = '0;
        b = '0;

        // Level 0 initialization
        for (int i = 0; i < NUM_DATA; i++) begin
            partial_min_max[0][i] = i_data[i];
        end

        for (int lvl = 1; lvl < TREE_LEVELS; lvl++) begin
            MAX_POSITIONS = (NUM_DATA / (2 ** lvl));

            for (int pos = 0; pos < MAX_POSITIONS; pos++) begin
                a = partial_min_max[(lvl - 1)][(pos * 2)];
                b = partial_min_max[(lvl - 1)][((pos * 2) + 1)];

                if (MIN_FUNCTION) begin
                    partial_min_max[lvl][pos] = (a > b) ? b : a;
                end else begin
                    partial_min_max[lvl][pos] = (a > b) ? a : b;
                end

            end
        end
    end

    assign o_min_max = partial_min_max[TREE_LEVELS-1][0];

`ifdef SIM
    initial assert ((NUM_DATA & (NUM_DATA - 1)) == 0)
        else $fatal(1, "min_max_tree - Must use power of 2 NUM_DATA parameter. Pad to nearest power of 2.");
`endif // SIM

endmodule
