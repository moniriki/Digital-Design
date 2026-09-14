// Byte-packing gearbox. Each source beat carries i_src_byte_en marking which
// bytes of i_src_data are live (holes allowed); the enabled bytes are compacted
// (gaps removed) via a prefix-sum crossbar and appended to a shift queue, which
// emits fixed DST_DATA_WIDTH words LSB-first. Works up, down, or equal width.
//
// Valid/ready on both sides: a source beat is taken only when o_src_ready (the
// queue has room for this beat's packed byte count); a destination word leaves
// only when o_dst_valid && i_dst_ready. Single clock. i_src_byte_en should be
// registered upstream since o_src_ready depends on its population count.
module packing_gearbox # (
    parameter int unsigned SRC_DATA_WIDTH = 8,
    parameter int unsigned DST_DATA_WIDTH = 8,
    localparam int unsigned SRC_DATA_BYTES = SRC_DATA_WIDTH / 8,
    localparam int unsigned DST_DATA_BYTES = DST_DATA_WIDTH / 8,
    localparam int unsigned QUEUE_SIZE = (SRC_DATA_WIDTH >= DST_DATA_WIDTH) ? (2 * SRC_DATA_WIDTH) : (2 * DST_DATA_WIDTH),
    localparam int unsigned QUEUE_BYTES = QUEUE_SIZE / 8,
    localparam int unsigned PTR_W = $clog2(QUEUE_BYTES) + 1,       // holds 0 .. QUEUE_BYTES
    localparam int unsigned PC_W  = $clog2(SRC_DATA_BYTES + 1)     // holds 0 .. SRC_DATA_BYTES
) (
    input logic i_clk,
    input logic i_reset_n,

    input logic [SRC_DATA_WIDTH-1:0] i_src_data,
    input logic [SRC_DATA_BYTES-1:0] i_src_byte_en,
    output logic o_src_ready,

    output logic [DST_DATA_WIDTH-1:0] o_dst_data,
    output logic o_dst_valid,
    input logic i_dst_ready
);

    logic [QUEUE_SIZE-1:0] sq_q, sq_d;
    logic [PTR_W-1:0]      sq_wr_ptr_q, sq_wr_ptr_d;

    // Data pack + mask logic
    logic [PC_W-1:0]           src_data_pc [SRC_DATA_BYTES];
    logic [SRC_DATA_WIDTH-1:0] src_data_packed;
    logic [PC_W-1:0]           src_data_packed_size;

    // Population count per index becomes your packed index
    always_comb begin
        src_data_pc[0] = PC_W'(i_src_byte_en[0]);
        for (int i = 1; i < SRC_DATA_BYTES; i++) begin
            src_data_pc[i] = src_data_pc[i - 1] + PC_W'(i_src_byte_en[i]);
        end
        src_data_packed_size = src_data_pc[SRC_DATA_BYTES - 1];
    end

    always_comb begin
        src_data_packed = '0;

        for (int i = 0; i < SRC_DATA_BYTES; i++) begin // Pack index
            for (int j = 0; j < SRC_DATA_BYTES; j++) begin // Data index
                if (i_src_byte_en[j] && ((src_data_pc[j] - PC_W'(1)) == PC_W'(i))) begin
                    src_data_packed[(i * 8) +: 8] = i_src_data[(j * 8) +: 8];
                end
            end
        end
    end

    always_ff @(posedge i_clk) begin
        if (~i_reset_n) begin
            sq_wr_ptr_q <= '0;
            sq_q <= '0;
        end else begin
            sq_wr_ptr_q <= sq_wr_ptr_d;
            sq_q <= sq_d;
        end
    end

    always_comb begin
        sq_wr_ptr_d = sq_wr_ptr_q;
        sq_d = sq_q;

        if (|i_src_byte_en && o_src_ready) begin
            sq_wr_ptr_d += PTR_W'(src_data_packed_size);
            sq_d |= (QUEUE_SIZE'(src_data_packed) << (QUEUE_SIZE'(sq_wr_ptr_q) << 3));
        end

        if (o_dst_valid && i_dst_ready) begin
            sq_wr_ptr_d -= PTR_W'(DST_DATA_BYTES);
            sq_d = sq_d >> (DST_DATA_BYTES * 8);
        end
    end

    // Timing-aggressive ready: only claims room for this beat's packed size, not
    // a full source word. Safe as long as i_src_byte_en is registered upstream.
    assign o_src_ready = (QUEUE_BYTES - 32'(sq_wr_ptr_q)) >= 32'(src_data_packed_size);
    assign o_dst_valid = (32'(sq_wr_ptr_q) >= DST_DATA_BYTES);
    assign o_dst_data  = sq_q[0 +: DST_DATA_WIDTH];

endmodule
