module bin_tree_2arb_block (
    input logic i_clk,
    input logic i_reset_n,
    input logic [1:0] i_request,
    output logic [1:0] o_grant,

    output logic o_request,
    input logic i_grant
);

    logic arb_sel;
    logic [1:0] request_mask, request;

    assign request_mask = (2'b01 << arb_sel);
    assign request = i_request & request_mask;

    always_ff @(posedge i_clk) begin
        if (~i_reset_n) begin
            arb_sel <= 1'b0;
        end else begin
            if (o_grant[arb_sel]) begin
                arb_sel <= ~arb_sel;
            end
        end
    end

    assign o_request = |i_request; // Always signal if we ever have any request
    assign o_grant = (o_request && i_grant) ? (|request ? request_mask : i_request) : '0;

endmodule

module tt_bin_tree_arb_4 (
    input logic i_clk,
    input logic i_reset_n,
    input logic [4-1:0] i_request,
    output logic [4-1:0] o_grant
);

    logic [1:0] request, grant;
    logic root_request;

    // Level 1 modules
    tt_bin_tree_2arb_block block0_level1 (
        .i_clk(i_clk),
        .i_reset_n(i_reset_n),
        .i_request(i_request[1:0]),
        .o_grant(o_grant[1:0]),

        .o_request(request[0]),
        .i_grant(grant[0])
    );

    tt_bin_tree_2arb_block block1_level1 (
        .i_clk(i_clk),
        .i_reset_n(i_reset_n),
        .i_request(i_request[3:2]),
        .o_grant(o_grant[3:2]),

        .o_request(request[1]),
        .i_grant(grant[1])
    );

    tt_bin_tree_2arb_block root (
        .i_clk(i_clk),
        .i_reset_n(i_reset_n),
        .i_request(request[1:0]),
        .o_grant(grant[1:0]),

        .o_request(root_request),
        .i_grant(root_request)
    );

endmodule