// Time-division arbiter: slot i is the only one that can be granted in cycle i,
// and only if requester i is asserting that cycle. The slot counter advances
// every cycle and wraps at WIDTH-1, so each requester owns exactly one slot in
// every WIDTH-cycle frame regardless of the others.
//
// Not work-conserving: if the current slot's requester is idle, that cycle is
// wasted even when others are waiting. This gives hard, request-independent
// bandwidth and latency bounds, which is the reason to use it over a
// work-conserving arbiter.
module time_slice_arb #(
    parameter  int unsigned WIDTH     = 4,
    localparam int unsigned CNT_WIDTH = (WIDTH <= 1) ? 1 : $clog2(WIDTH)
) (
    input  logic             i_clk,
    input  logic             i_reset_n,
    input  logic [WIDTH-1:0] i_request,
    output logic [WIDTH-1:0] o_grant
);

    logic [CNT_WIDTH-1:0] time_slice;

    always_ff @(posedge i_clk) begin
        if (~i_reset_n || (time_slice == CNT_WIDTH'(WIDTH - 1))) begin
            time_slice <= '0;
        end else begin
            time_slice <= time_slice + CNT_WIDTH'(1);
        end
    end

    always_comb begin
        o_grant = '0;
        for (int unsigned i = 0; i < WIDTH; i++) begin
            if (time_slice == CNT_WIDTH'(i)) begin
                o_grant[i] = i_request[i];
            end
        end
    end

endmodule
