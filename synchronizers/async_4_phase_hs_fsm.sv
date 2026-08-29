// Implemented as an FSM
module async_4_phase_hs_fsm # (
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

    typedef enum logic [1:0] {
        SRC_IDLE = 0,
        SRC_REQ1,
        SRC_REQ0
    } src_state;

    typedef enum logic [1:0] {
        DST_IDLE = 0,
        DST_ACK1,
        DST_ACK0
    } dst_state;

    src_state src_state_q, src_state_d;
    dst_state dst_state_q, dst_state_d;

    logic dst_req_valid, dst_req_accepted;

    // Source side logic

    sync3 src_side_ack_sync (
        .i_clk(i_src_clk),
        .i_reset_n(i_src_reset_n),
        .i_d(ack),
        .o_q(ack_sync)
    );

    always_ff @(posedge i_src_clk) begin
        if (~i_src_reset_n) begin
            src_state_q <= SRC_IDLE;
        end else begin
            src_state_q <= src_state_d;
        end
    end

    // Next state logic
    always_comb begin
        src_state_d = src_state_q;

        case(src_state_q)
            SRC_IDLE: begin
                src_state_d = src_state'(i_valid ? SRC_REQ1 : SRC_IDLE);
            end
            SRC_REQ1: begin
                src_state_d = src_state'(ack_sync ? SRC_REQ0 : SRC_REQ1);
            end
            SRC_REQ0: begin
                src_state_d = src_state'(~ack_sync ? SRC_IDLE : SRC_REQ0);
            end
            default: begin
                src_state_d = SRC_IDLE;
            end
        endcase
    end

    // Non-resetable flop to save area
    always_ff @(posedge i_src_clk) begin
        if ((src_state_q == SRC_IDLE) && i_valid) begin
            data_reg <= i_data;
        end else begin
            data_reg <= data_reg;
        end
    end

    always_ff @(posedge i_src_clk) begin
        if (~i_src_reset_n) begin
            req <= 1'b0;
        end else begin
            req <= (src_state_d == SRC_REQ1);
        end
    end

    assign o_ready = (src_state_q == SRC_IDLE);

    // Destination side logic

    sync3 dst_side_req_sync (
        .i_clk(i_dst_clk),
        .i_reset_n(i_dst_reset_n),
        .i_d(req),
        .o_q(req_sync)
    );

    always_ff @(posedge i_dst_clk) begin
        if (~i_dst_reset_n) begin
            dst_state_q <= DST_IDLE;
        end else begin
            dst_state_q <= dst_state_d;
        end
    end

    always_comb begin
        dst_state_d = dst_state_q;

        case(dst_state_q)
            DST_IDLE: begin
                dst_state_d = dst_state'(req_sync ? DST_ACK1 : DST_IDLE);
            end
            DST_ACK1: begin
                dst_state_d = dst_state'((~req_sync && dst_req_accepted) ? DST_ACK0 : DST_ACK1);
            end
            DST_ACK0: begin
                dst_state_d = DST_IDLE;
            end
            default: begin
                dst_state_d = DST_IDLE;
            end
        endcase
    end

    always_ff @(posedge i_dst_clk) begin
        if (~i_dst_reset_n) begin
            ack <= 1'b0;
        end else begin
            ack <= (dst_state_d == DST_ACK1);
        end
    end

    always_ff @(posedge i_dst_clk) begin
        if (~i_dst_reset_n) begin
            dst_req_valid <= 1'b0;
        end else if (dst_req_valid && i_ready) begin
            dst_req_valid <= 1'b0;
        end else if (~dst_req_valid) begin
            dst_req_valid <= (dst_state_q == DST_IDLE) && (dst_state_d == DST_ACK1);
        end else begin
            dst_req_valid <= dst_req_valid;
        end
    end

    always_ff @(posedge i_dst_clk) begin
        if (~i_dst_reset_n) begin
            dst_req_accepted <= 1'b0;
        end else begin
            if (dst_req_accepted) begin
                dst_req_accepted <= (dst_state_q == DST_ACK0) ? 1'b0 : dst_req_accepted;
            end else begin
                dst_req_accepted <= (dst_state_q == DST_ACK1) && (o_valid && i_ready);
            end
        end
    end

    assign o_valid = dst_req_valid;
    assign o_data = data_reg;

endmodule
