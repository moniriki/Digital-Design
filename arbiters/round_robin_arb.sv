module round_robin_arb_ptr # (
    parameter int unsigned WIDTH = 4,
    localparam int unsigned PTR_W = $clog2(WIDTH) + 1
) (
    input logic i_clk,
    input logic i_reset_n,
    input logic [WIDTH-1:0] i_request,
    output logic [WIDTH-1:0] o_grant
);

    logic [WIDTH-1:0] grant;
    logic [PTR_W-1:0] grant_ptr_q, grant_ptr_d;
    logic [WIDTH-1:0] left_side_mask_q, left_side_mask_d;
    logic [WIDTH-1:0] left_side_req, left_side_grant, full_grant;

    always_ff @(posedge i_clk) begin
        if (~i_reset_n) begin
            grant_ptr_q <= '0;
            left_side_mask_q <= '1; // Default out of reset
        end else begin
            grant_ptr_q <= grant_ptr_d;
            left_side_mask_q <= left_side_mask_d;
        end
    end

    always_comb begin
        grant_ptr_d = grant_ptr_q;

        if (|i_request) begin
            for (int i = 1; i < (WIDTH + 1); i++) begin
                if (grant[i - 1] == 1'b1) begin
                    grant_ptr_d = PTR_W'(i);
                end
            end
        end
    end

    always_comb begin
        for (int i = 1; i < (WIDTH + 1); i++) begin
            left_side_mask_d[i - 1] = (i > grant_ptr_d);
        end
    end

    assign left_side_req = left_side_mask_q & i_request;
    assign left_side_grant = left_side_req & ~(left_side_req - WIDTH'(1));
    assign full_grant = i_request & ~(i_request - WIDTH'(1));
    assign grant = |left_side_req ? left_side_grant : full_grant;
    assign o_grant = grant;

endmodule

module tt_round_robin_arb # (
    parameter int unsigned WIDTH = 4
) (
    input logic i_clk,
    input logic i_reset_n,
    input logic [WIDTH-1:0] i_request,
    output logic [WIDTH-1:0] o_grant
);

    // Skip pointer logic, use bit-manip tricks
    function automatic logic [WIDTH-1:0] my_prio (
        input logic [WIDTH-1:0] i_mask
    );

        my_prio = i_mask & ~(i_mask - WIDTH'(1));

    endfunction

    logic [WIDTH-1:0] mask_q, mask_d;

    always_ff @(posedge i_clk) begin
        if (~i_reset_n) begin
            mask_q <= '1;
        end else begin
            mask_q <= mask_d;
        end
    end

    always_comb begin
        mask_d = mask_q;

        if (|i_request) begin
            mask_d = ~(o_grant | (o_grant - WIDTH'(1)));
        end
    end

    assign o_grant = |(i_request & mask_q) ? my_prio(i_request & mask_q) : my_prio(i_request);

endmodule