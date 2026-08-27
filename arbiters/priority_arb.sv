module priority_arb #(
    parameter WIDTH = 4
) (
    input logic i_clk,
    input logic i_reset_n,
    input logic [WIDTH-1:0] i_request,

    output logic [WIDTH-1:0] o_grant,
    output logic o_grant_valid,
    input logic i_grant_ready
);

    logic [WIDTH-1:0] grant_q, grant_d, next_grant_d;
    logic grant_valid_q, grant_valid_d;

    always_ff @(posedge i_clk) begin
        if (~i_reset_n) begin
            grant_q <= '0;
            grant_valid_q <= '0;
        end else begin
            grant_q <= grant_d;
            grant_valid_q <= grant_valid_d;
        end
    end

    always_comb begin
        grant_d = grant_q;
        next_grant_d = i_request & ~grant_q;

        if (~grant_valid_q) begin
            grant_d = i_request & ~(i_request - WIDTH'(1));
        end else if (grant_valid_q && i_grant_ready) begin // Move to next requestor until next cycle where same requestor may assert again
            grant_d = next_grant_d & ~(next_grant_d - WIDTH'(1));
        end

        grant_valid_d = |grant_d;

    end

    assign o_grant = grant_q;
    assign o_grant_valid = grant_valid_q;

endmodule