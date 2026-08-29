// Implemented as two states on each side; async_4_phase_hs_fsm.sv
// implementation is an FSM instead. This implementation assumes
// reset sequencing has been completed on source and destination
// resets, otherwise unintended consequences can occur.
module async_4_phase_hs # (
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
    input logic i_ready,
    output dtype_t o_data
);

    dtype_t data_reg;

    logic req, req_sync;
    logic ack, ack_sync;

    // Source side logic

    sync3 src_side_ack_sync (
        .i_clk(i_src_clk),
        .i_reset_n(i_src_reset_n),
        .i_d(ack),
        .o_q(ack_sync)
    );

    // Request flop
    always_ff @(posedge i_src_clk) begin
        if (~i_src_reset_n) begin
            req <= 1'b0;
        end else begin
            if (~req && ~ack_sync) begin // Listen to input
                req <= i_valid;
                data_reg <= i_valid ? i_data : data_reg;
            end else if (req && ack_sync) begin
                req <= 1'b0;
            end else begin
                req <= req;
            end
        end
    end

    assign o_ready = ~req && ~ack_sync;

    // Destination side logic

    sync3 dst_side_req_sync (
        .i_clk(i_dst_clk),
        .i_reset_n(i_dst_reset_n),
        .i_d(req),
        .o_q(req_sync)
    );

    logic dst_req_accepted, dst_valid;

    // Ack flop
    always_ff @(posedge i_dst_clk) begin
        if (~i_dst_reset_n) begin
            ack <= 1'b0;
        end else begin
            if (~ack && req_sync) begin
                ack <= 1'b1;
            end else if (ack && ~req_sync && dst_req_accepted) begin
                ack <= 1'b0;
            end
        end
    end

    always_ff @(posedge i_dst_clk) begin
        if (~i_dst_reset_n) begin
            dst_valid <= 1'b0;
            dst_req_accepted <= 1'b0;
        end else begin
            if (~dst_valid && ~ack && req_sync) begin
                dst_valid <= 1'b1;
                dst_req_accepted <= 1'b0;
            end else if (dst_valid && i_ready) begin
                dst_valid <= 1'b0;
                dst_req_accepted <= 1'b1;
            end else begin
                dst_valid <= dst_valid;
                dst_req_accepted <= dst_req_accepted;
            end
        end
    end

    assign o_valid = dst_valid;
    assign o_data = data_reg;

endmodule
