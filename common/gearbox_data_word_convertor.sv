module gearbox_data_word_convertor # (
    parameter int unsigned SRC_DATA_WIDTH = 8,
    parameter int unsigned DST_DATA_WIDTH = 16,
    localparam int unsigned SRC_DATA_WIDTH_BYTES = SRC_DATA_WIDTH / 8,
    localparam int unsigned SRC_DATA_WIDTH_LOG2 = $clog2(SRC_DATA_WIDTH_BYTES),
    localparam int unsigned SHIFT_QUEUE_SIZE = (SRC_DATA_WIDTH > DST_DATA_WIDTH) ? (2 * SRC_DATA_WIDTH) : (2 * DST_DATA_WIDTH),
    localparam int unsigned SHIFT_QUEUE_SIZE_LOG2 = $clog2(SHIFT_QUEUE_SIZE)
) (
    input logic i_clk,
    input logic i_reset_n,
    input logic i_valid,
    input logic [SRC_DATA_WIDTH-1:0] i_data,
    input logic [SRC_DATA_WIDTH_LOG2:0] i_data_size, // In bytes
    output logic o_ready,

    output logic o_valid,
    output logic [DST_DATA_WIDTH-1:0] o_data,
    input logic i_ready
);

    logic [SRC_DATA_WIDTH-1:0] data_masked;
    logic [SRC_DATA_WIDTH-1:0] data_byte_enable;
    logic [SHIFT_QUEUE_SIZE_LOG2:0] shift_offset, shift_offset_q;
    logic [SHIFT_QUEUE_SIZE-1:0] shift_queue, shift_queue_q;

    // Source side
    // bytes -> data strobe for masking logic
    always_comb begin
        data_byte_enable = '0;
        for (int unsigned i = 0; i < SRC_DATA_WIDTH_BYTES; i++) begin
            if (i_data_size > i) begin
                data_byte_enable[(i * 8) +: 8] = 8'hFF;
            end
        end
    end

    assign data_masked = i_data & data_byte_enable;

    always_comb begin
        shift_offset = shift_offset_q;
        shift_queue = shift_queue_q;
        
        if (i_valid && o_ready) begin
            shift_queue |= (data_masked << shift_offset);
            shift_offset += (i_data_size << 3);
        end

        if (o_valid && i_ready) begin
            shift_offset -= DST_DATA_WIDTH;
            shift_queue >>= DST_DATA_WIDTH;
        end
    end

    always_ff @(posedge i_clk) begin
        if (~i_reset_n) begin
            shift_offset_q <= '0;
            shift_queue_q <= '0;
        end else begin
            shift_offset_q <= shift_offset;
            shift_queue_q <= shift_queue;
        end
    end

    assign o_ready = (SRC_DATA_WIDTH <= (SHIFT_QUEUE_SIZE - shift_offset_q));
    assign o_valid = (shift_offset_q >= DST_DATA_WIDTH);
    assign o_data = shift_queue_q[0 +: DST_DATA_WIDTH];

endmodule
