// Multi-flop synchronizer for a signal crossing into i_clk's domain.
//
// STAGES back-to-back flops (default 3) drop the probability of a metastable
// sample propagating. Only use this on signals that are safe to sample one bit
// skewed: a single control bit, or a gray-coded bus where at most one bit
// changes per source cycle. A plain binary bus needs a handshake or a FIFO
// instead.
//
// Reset drives every stage to RESET_VAL. RESET_ASYNC selects the reset style so
// the synchronizer matches its parent: synchronous by default, asynchronous
// (async-assert / sync-release) when the surrounding logic uses async reset,
// e.g. the clock-domain selects in anti_glitch_clkmux. RESET_VAL lets a
// synchronized copy power up in the same state as its source register.
module sync #(
    parameter int unsigned WIDTH       = 1,
    parameter int unsigned STAGES      = 3,
    parameter bit          RESET_VAL   = 1'b0,
    parameter bit          RESET_ASYNC = 1'b0
) (
    input  logic             i_clk,
    input  logic             i_reset_n,
    input  logic [WIDTH-1:0] i_d,
    output logic [WIDTH-1:0] o_q
);

    logic [WIDTH-1:0] stage [STAGES];

    // Shift i_d down the chain each cycle; reset every stage to RESET_VAL.
    generate
        if (RESET_ASYNC) begin : g_async_reset
            always_ff @(posedge i_clk or negedge i_reset_n) begin
                if (~i_reset_n) begin
                    for (int unsigned s = 0; s < STAGES; s++) stage[s] <= {WIDTH{RESET_VAL}};
                end else begin
                    stage[0] <= i_d;
                    for (int unsigned s = 1; s < STAGES; s++) stage[s] <= stage[s-1];
                end
            end
        end else begin : g_sync_reset
            always_ff @(posedge i_clk) begin
                if (~i_reset_n) begin
                    for (int unsigned s = 0; s < STAGES; s++) stage[s] <= {WIDTH{RESET_VAL}};
                end else begin
                    stage[0] <= i_d;
                    for (int unsigned s = 1; s < STAGES; s++) stage[s] <= stage[s-1];
                end
            end
        end
    endgenerate

    assign o_q = stage[STAGES-1];

endmodule
