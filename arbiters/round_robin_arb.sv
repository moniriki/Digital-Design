// Round-robin arbiter, masked-priority formulation.
//
// mask_q holds the set of requesters at or after the position just past the
// last winner. Each cycle the arbiter grants the lowest set bit of
// (i_request & mask_q); if nothing there is requesting it wraps and grants the
// lowest set bit of i_request. After a grant, mask_q is rebuilt to exclude
// everything up to and including the winner, so the next arbitration starts one
// slot further around the ring. Every requester is served within one full
// rotation -- no starvation.
//
// Single-cycle: o_grant is combinational from i_request and the registered
// mask. No handshake.
module round_robin_arb #(
    parameter int unsigned WIDTH = 4
) (
    input  logic             i_clk,
    input  logic             i_reset_n,
    input  logic [WIDTH-1:0] i_request,
    output logic [WIDTH-1:0] o_grant
);

    // Isolate the lowest set bit.
    function automatic logic [WIDTH-1:0] lowest_set (input logic [WIDTH-1:0] mask);
        lowest_set = mask & ~(mask - WIDTH'(1));
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
            // Everything strictly after this cycle's winner.
            mask_d = ~(o_grant | (o_grant - WIDTH'(1)));
        end
    end

    assign o_grant = |(i_request & mask_q) ? lowest_set(i_request & mask_q)
                                           : lowest_set(i_request);

endmodule
