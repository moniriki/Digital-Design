/* This implementation assumes that the sync_fifo depth will always be a power of 2
 * >= 2. This allows us to take advantage of wrapping power of 2 pointers to track full
 * or empty status. If arbitrary depths are required, a counter implementation would suffice.
 */

module sync_fifo # (
    parameter int unsigned WIDTH = 32,
    parameter int unsigned DEPTH = 8, // Must be a power of 2, >= 2
    parameter type dtype_t = logic [WIDTH-1:0],
    localparam int unsigned PTR_W = $clog2(DEPTH)
) (
    input logic i_clk,
    input logic i_reset_n,

    input logic i_wr_valid,
    output logic o_wr_ready,
    input dtype_t i_wr_data,
    output logic o_rd_valid,
    input logic i_rd_ready,
    output dtype_t o_rd_data,

    output logic o_full,
    output logic o_empty
);

    dtype_t fifo [0:DEPTH-1];
    logic [PTR_W:0] wr_ptr, rd_ptr; // MSB tracks wrapping

    always_ff @(posedge i_clk) begin
        if (~i_reset_n) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
        end else begin

            // Write side
            if (i_wr_valid && ~o_full) begin
                fifo[wr_ptr[PTR_W-1:0]] <= i_wr_data;
                wr_ptr <= wr_ptr + 1'b1;
            end

            // Read side
            if (i_rd_ready && ~o_empty) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end

    assign o_full = (wr_ptr[PTR_W] != rd_ptr[PTR_W]) && (wr_ptr[PTR_W-1:0] == rd_ptr[PTR_W-1:0]);
    assign o_empty = (wr_ptr == rd_ptr);
    assign o_wr_ready = ~o_full;
    assign o_rd_valid = ~o_empty;
    assign o_rd_data = fifo[rd_ptr[PTR_W-1:0]];

`ifdef SIM
    initial assert ((DEPTH >= 2) && !(DEPTH & (DEPTH - 1)))
        else $fatal(1, "sync_fifo: DEPTH must be a power of two >= 2");
`endif

endmodule
