// This module must only be used for synchronous, rational
// clock domain crossings. Technically speaking, this is more
// of a control flow module rather than a true async CDC.
module sync_2_phase_hs # (
    parameter type dtype_t = logic
) (
    input logic i_src_clk,
    input logic i_src_reset_n,
    input logic i_valid,
    output logic o_ready,
    input dtype_t i_data,

    input logic i_dst_clk,
    input logic i_dst_reset_n,
    output logic o_valid,
    input logic i_ready,
    output dtype_t o_data
);

    dtype_t data_reg;
    logic req;
    logic ack;

    logic src_req_active, dst_req_active;
    logic dst_req_accepted, dst_req_valid;

    assign src_req_active = (req ^ ack);
    assign dst_req_active = (ack ^ req);

    // Source side logic

    // Req flop
    always_ff @(posedge i_src_clk) begin
        if (~i_src_reset_n) begin
            req <= 1'b0;
        end else begin
            if (~(src_req_active)) begin
                if (i_valid) begin
                    req <= ~req;
                    data_reg <= i_data;
                end
            end
        end
    end

    assign o_ready = ~src_req_active;

    // Destination side logic

    // Ack register
    always_ff @(posedge i_dst_clk) begin
        if (~i_dst_reset_n) begin
            ack <= 1'b0;
        end else begin
            if (dst_req_active && dst_req_accepted) begin
                ack <= ~ack;
            end
        end
    end

    // Dest valid flop
    always_ff @(posedge i_dst_clk) begin
        if (~i_dst_reset_n) begin
            dst_req_valid <= 1'b0;
        end else begin
            if (dst_req_valid) begin
                dst_req_valid <= ~i_ready;
            end else if (dst_req_active) begin
                dst_req_valid <= 1'b1;
            end
        end
    end

    assign dst_req_accepted = o_valid && i_ready;

    assign o_valid = dst_req_valid;
    assign o_data = data_reg;

endmodule
