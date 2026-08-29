// This module should only be used on fast-to-slow
// synchronous rational crossings (2:1, 4:1, etc)
// It uses source and sink counters with a sink-side
// buffer to enable better throughput through the crossing.
// The obvious PD STA guarantees on setup/hold timing
// must be met for this module to function correctly
// in silicon.
module fast2slow_sync_crossing # (
    parameter type dtype_t = logic
) (
    input logic i_src_clk,
    input logic i_src_reset_n,
    input logic i_valid,
    input dtype_t i_data,
    output logic o_ready,

    input logic i_dst_clk,
    input logic i_dst_reset_n,
    output logic o_valid,
    output dtype_t o_data,
    input logic i_ready
);

    // Could also use single bit toggle regs with XOR logic
    logic [1:0] src_cnt, sink_cnt;
    dtype_t src_data;
    logic sink_buf_ready;
    logic src_req_ready, sink_req_active;

    // Source side
    // Must check two conditions:
    // Count values match - (if they don't match the sink buf has not accepted the previous data)
    // Sink buffer ready - Prevents overflow if downstream has not popped
    assign src_req_ready = (src_cnt == sink_cnt) && sink_buf_ready;

    // src_data flop
    // src_cnt flop
    always_ff @(posedge i_src_clk) begin
        if (~i_src_reset_n) begin
            src_cnt <= 2'd0;
        end else begin
            if (src_req_ready && i_valid) begin // checks if sink buf is ready as well to prevent overflow
                src_cnt <= src_cnt + 2'd1;
                src_data <= i_data;
            end
        end
    end

    assign o_ready = src_req_ready;

    // Sink side
    assign sink_req_active = (src_cnt != sink_cnt);

    // sink_cnt flop
    always_ff @(posedge i_dst_clk) begin
        if (~i_dst_reset_n) begin
            sink_cnt <= 2'd0;
        end else begin
            if (sink_req_active) begin
                sink_cnt <= sink_cnt + 2'd1;
            end
        end
    end

    // Sink buffer
    sync_fifo # (
        .WIDTH($bits(dtype_t)),
        .DEPTH(2)
    ) sink_buf (
        .i_clk(i_dst_clk),
        .i_reset_n(i_dst_reset_n),
        .i_wr_valid(sink_req_active),
        .o_wr_ready(sink_buf_ready),
        .i_wr_data(src_data),
        .o_rd_valid(o_valid),
        .i_rd_ready(i_ready),
        .o_rd_data(o_data),

        // Unconnected
        .o_full(),
        .o_empty()
    );

endmodule
