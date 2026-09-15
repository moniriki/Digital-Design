module weighted_priority_arb #(
    parameter int unsigned WIDTH = 4,
    parameter int unsigned WEIGHT_WIDTH = 4
) (
    input  logic                    i_clk,
    input  logic                    i_reset_n,
    input  logic [WIDTH-1:0]        i_request,
    input  logic [WEIGHT_WIDTH-1:0] i_request_weight [WIDTH-1:0],

    output logic [WIDTH-1:0]        o_grant,
    output logic                    o_grant_valid
);

    typedef struct packed {
        logic valid;
        logic [WEIGHT_WIDTH-1:0] weight;
        logic [WIDTH-1:0] tiebreak;
    } tuple_datum;

    localparam int unsigned TUPLE_BITS = $bits(tuple_datum);

    logic [TUPLE_BITS-1:0] requestor_num [0:WIDTH-1];
    logic [TUPLE_BITS-1:0] requestor_max;

    // Flop inputs every cycle for timing
    always_ff @(posedge i_clk) begin
        if (~i_reset_n) begin
            for (int i = 0; i < WIDTH; i++) begin
                requestor_num[i] <= '0;
            end
        end else begin
            for (int i = 0; i < WIDTH; i++) begin
                requestor_num[i] <= {i_request[i], i_request_weight[i], ~(WIDTH'(1) << i)};
            end
        end
    end

    min_max_tree #(
        .NUM_DATA(WIDTH),
        .DATA_WIDTH($bits(tuple_datum)),
        .MIN_FUNCTION(1'b0)
    ) max_tree (
        .i_data(requestor_num),
        .o_min_max(requestor_max)
    );

    assign o_grant = ~(requestor_max[0 +: WIDTH]);
    assign o_grant_valid = requestor_max[WIDTH + WEIGHT_WIDTH +: 1];

endmodule
