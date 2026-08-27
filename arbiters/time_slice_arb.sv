module time_slice_arb # (
    parameter int unsigned WIDTH = 4,
    localparam int unsigned CNT_WIDTH = (WIDTH == 0) ? 1 : $clog2(WIDTH)
) (
    input logic i_clk,
    input logic i_reset_n,
    input logic [WIDTH-1:0] i_request,
    output logic [WIDTH-1:0] o_grant
);

    logic [CNT_WIDTH-1:0] time_slice;

    always_ff @(posedge i_clk) begin
        if (~i_reset_n || (time_slice == (WIDTH - 1))) begin
            time_slice <= '0;
        end else begin
            time_slice <= time_slice + CNT_WIDTH'(1);
        end
    end

    always_comb begin
        o_grant = '0;

        for (int unsigned i = 0; i < WIDTH; i++) begin
            if (time_slice == i) begin
                o_grant[i] = i_request[i];
            end
        end
    end

endmodule