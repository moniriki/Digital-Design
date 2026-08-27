module sync_fifo_variable_depth # (
    parameter int unsigned WIDTH = 32,
    parameter int unsigned DEPTH = 8,
    parameter type data_t = logic [WIDTH-1:0],
    localparam int unsigned PTR_W = (DEPTH > 1) ? $clog2(DEPTH) : 1,
    localparam int unsigned COUNT_W = PTR_W + 1
) (
    input logic i_clk,
    input logic i_reset_n,

    input logic i_wr_valid,
    output logic o_wr_ready,
    input data_t i_wr_data,
    output logic o_rd_valid,
    input logic i_rd_ready,
    output data_t o_rd_data,

    output logic o_full,
    output logic o_empty
);

    data_t fifo [0:DEPTH-1];
    logic [PTR_W-1:0] wr_ptr, rd_ptr;
    logic [COUNT_W-1:0] count_q, count_d;

    always_comb begin
        count_d = count_q;

        if (i_wr_valid && ~o_full) begin
            count_d += 1'b1;
        end

        if (i_rd_ready && ~o_empty) begin
            count_d -= 1'b1;
        end
    end

    always_ff @(posedge i_clk) begin
        if (~i_reset_n) begin
            count_q <= '0;
        end else begin
            count_q <= count_d;
        end
    end

    always_ff @(posedge i_clk) begin
        if (~i_reset_n) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
        end else begin

            // Write side
            if (i_wr_valid && ~o_full) begin
                fifo[wr_ptr] <= i_wr_data;

                if (wr_ptr == (PTR_W'(DEPTH - 1))) begin
                    wr_ptr <= '0;
                end else begin
                    wr_ptr <= wr_ptr + 1'b1;
                end
            end

            // Read side
            if (i_rd_ready && ~o_empty) begin

                if (rd_ptr == (PTR_W'(DEPTH-1))) begin
                    rd_ptr <= '0;
                end else begin
                    rd_ptr <= rd_ptr + 1'b1;
                end
            end
        end
    end

    assign o_full = (count_q == COUNT_W'(DEPTH));
    assign o_empty = (count_q == '0);
    assign o_wr_ready = ~o_full;
    assign o_rd_valid = ~o_empty;
    assign o_rd_data = fifo[rd_ptr];

endmodule
