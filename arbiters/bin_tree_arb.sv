// Binary-tree round-robin arbiter.
//
// bin_tree_2arb_block is a 2:1 round-robin node with a "request up / grant down"
// interface so nodes compose into a tree. Each node keeps a 1-bit preference
// (arb_sel) that advances to the other input whenever the currently preferred
// input is served, giving round-robin fairness at that node. o_request is the
// OR of the node's requests; o_grant is driven only when the parent grants
// (i_grant) and something is requesting.
//
// bin_tree_arb_4 wires four of these into a two-level tree: two leaf nodes plus
// a root whose i_grant is tied high (no parent). Fairness is per-node, so the
// global order is round-robin within each pair and round-robin between pairs,
// not a strict 4-way rotation.
module bin_tree_2arb_block (
    input  logic       i_clk,
    input  logic       i_reset_n,
    input  logic [1:0] i_request,
    output logic [1:0] o_grant,

    output logic       o_request,
    input  logic       i_grant
);

    logic       arb_sel;
    logic [1:0] request_mask, request;

    assign request_mask = (2'b01 << arb_sel);
    assign request       = i_request & request_mask;

    always_ff @(posedge i_clk) begin
        if (~i_reset_n) begin
            arb_sel <= 1'b0;
        end else begin
            if (o_grant[arb_sel]) begin
                arb_sel <= ~arb_sel;
            end
        end
    end

    assign o_request = |i_request; // signal upward whenever anything requests
    assign o_grant   = (o_request && i_grant) ? (|request ? request_mask : i_request) : '0;

endmodule

module bin_tree_arb_4 (
    input  logic       i_clk,
    input  logic       i_reset_n,
    input  logic [3:0] i_request,
    output logic [3:0] o_grant
);

    logic [1:0] request, grant;

    // Leaf nodes: one per request pair
    bin_tree_2arb_block block0_level1 (
        .i_clk     (i_clk),
        .i_reset_n (i_reset_n),
        .i_request (i_request[1:0]),
        .o_grant   (o_grant[1:0]),

        .o_request (request[0]),
        .i_grant   (grant[0])
    );

    bin_tree_2arb_block block1_level1 (
        .i_clk     (i_clk),
        .i_reset_n (i_reset_n),
        .i_request (i_request[3:2]),
        .o_grant   (o_grant[3:2]),

        .o_request (request[1]),
        .i_grant   (grant[1])
    );

    // Root node: no parent, so it is always granted from above
    bin_tree_2arb_block root (
        .i_clk     (i_clk),
        .i_reset_n (i_reset_n),
        .i_request (request),
        .o_grant   (grant),

        .o_request (/* unused */),
        .i_grant   (1'b1)
    );

endmodule
