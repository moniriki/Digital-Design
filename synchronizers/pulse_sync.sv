/* Synchronizes pulses from source to destination clock domains
 * Error output results when number of input pulses cannot be kept
 * up with. Sizing the MAX_CNT to a large enough number should avoid
 * any real workload error conditions. Credit counters may also be
 * used on the source side pulse generation to ensure we never overflow.
 * Credit counters would require this module to output a o_ready that
 * indicates when it has accepted a pulse in order to add credits to
 * the source.
*/
module pulse_sync # (
    parameter int unsigned MAX_CNT = 1024, // Must be power of 2 for this module to work
    parameter bit ASYNC_BOUNDARY = 1'b1,
    localparam MAX_CNT_W = $clog2(MAX_CNT)
) (
    input logic i_src_clk,
    input logic i_src_reset_n,
    input logic i_pulse,

    input logic i_dst_clk,
    input logic i_dst_reset_n,
    output logic o_pulse,
    output logic o_error
);

    function automatic logic [MAX_CNT_W:0] bin2gray (
        input logic [MAX_CNT_W:0] bin
    );
        bin2gray = bin ^ (bin >> 1);
    endfunction

    function automatic logic [MAX_CNT_W:0] gray2bin (
        input logic [MAX_CNT_W:0] gray
    );
        for (int i = 0; i < (MAX_CNT_W + 1); i++) begin
            gray2bin[i] = ^(gray >> i);
        end
    endfunction

    logic [MAX_CNT_W:0] src_wr_ptr_q, src_wr_ptr_d, src_wr_ptr_gray, src_rd_ptr, src_rd_ptr_gray;
    logic [MAX_CNT_W:0] dst_rd_ptr_q, dst_rd_ptr_d, dst_rd_ptr_gray, dst_wr_ptr, dst_wr_ptr_gray; 

    logic [MAX_CNT_W:0] src_side_delta, dst_side_delta;
    logic src_side_max_delta_reached;
    logic init_pulse;

    logic error_d;

    always_comb begin

        src_side_delta = src_wr_ptr_q - src_rd_ptr;
        dst_side_delta = dst_wr_ptr - dst_rd_ptr_q;

        // Start dropping pulses, let destination side catch up
        src_side_max_delta_reached = (src_side_delta == MAX_CNT);

    end

    // Source side write pointer reg
    always_ff @(posedge i_src_clk) begin
        if (~i_src_reset_n) begin
            src_wr_ptr_q <= '0;
            src_wr_ptr_gray <= '0;
        end else begin
            src_wr_ptr_q <= src_wr_ptr_d;
            src_wr_ptr_gray <= bin2gray(src_wr_ptr_d);
        end
    end

    always_comb begin
        src_wr_ptr_d = src_wr_ptr_q;
        error_d = 1'b0;

        if (~src_side_max_delta_reached) begin
            if (i_pulse) begin
                src_wr_ptr_d = src_wr_ptr_d + 1'b1;
            end
        end else begin
            if (i_pulse) begin
                error_d = 1'b1; // Pulses start dropping
            end
        end
    end

    // Error flop - persistent
    always_ff @(posedge i_src_clk) begin
        if (~i_src_reset_n) begin
            o_error <= 1'b0;
        end else begin
            if (~o_error) begin
                o_error <= error_d;
            end
        end
    end

    generate

        if (ASYNC_BOUNDARY) begin: gray_counters

            sync3 #(
                .WIDTH(MAX_CNT_W + 1)
            ) rd_ptr_sync_src_side (
                .i_clk(i_src_clk),
                .i_reset_n(i_src_reset_n),
                .i_d(dst_rd_ptr_gray),
                .o_q(src_rd_ptr_gray)
            );

            assign src_rd_ptr = gray2bin(src_rd_ptr_gray);

            sync3 #(
                .WIDTH(MAX_CNT_W + 1)
            ) wr_ptr_sync_dst_side (
                .i_clk(i_dst_clk),
                .i_reset_n(i_dst_reset_n),
                .i_d(src_wr_ptr_gray),
                .o_q(dst_wr_ptr_gray)
            );

            assign dst_wr_ptr = gray2bin(dst_wr_ptr_gray);

        end else begin: sync_counters

            // Gray counters gets synthesized out as it should be unused
            assign src_rd_ptr = dst_rd_ptr_q;
            assign dst_wr_ptr = src_wr_ptr_q;

        end

    endgenerate

    // Destination side

    always_ff @(posedge i_dst_clk) begin
        if (~i_dst_reset_n) begin
            dst_rd_ptr_q <= '0;
            dst_rd_ptr_gray <= '0;
        end else begin
            dst_rd_ptr_q <= dst_rd_ptr_d;
            dst_rd_ptr_gray <= bin2gray(dst_rd_ptr_d);
        end
    end

    always_comb begin
        dst_rd_ptr_d = dst_rd_ptr_q;
        init_pulse = 1'b0;

        if (~o_pulse && (dst_side_delta > 0)) begin
            init_pulse = 1'b1;
            dst_rd_ptr_d = dst_rd_ptr_d + 1'b1;
        end
    end

    always_ff @(posedge i_dst_clk) begin
        if (~i_dst_reset_n) begin
            o_pulse <= 1'b0;
        end else begin
            if (o_pulse) begin
                o_pulse <= 1'b0;
            end else begin
                o_pulse <= init_pulse;
            end
        end
    end

    initial assert ((MAX_CNT >= 2) && !(MAX_CNT & (MAX_CNT - 1)))
        else $fatal(1, "pulse_sync - MAX_CNT must be a power of 2 >=2 in order for gray counters to work");

endmodule
