// This module must only be used with power of 2 depths >= 2
// This module also assumes the WR and RD side resets have
// been sequenced correctly, such that the assertion of one
// does not impact the async fifos functionality.
module async_fifo #(
    parameter int unsigned WIDTH = 32,
    parameter int unsigned DEPTH = 8,
    parameter type dtype_t = logic [WIDTH-1:0],
    localparam int unsigned CNT_W = $clog2(DEPTH)
) (
    // Write side
    input logic i_wr_clk,
    input logic i_wr_reset_n,
    input logic i_wr_valid,
    output logic o_wr_ready,
    input dtype_t i_wr_data,

    input logic i_rd_clk,
    input logic i_rd_reset_n,
    output logic o_rd_valid,
    input logic i_rd_ready,
    output dtype_t o_rd_data,

    output logic o_full, // write side synced
    output logic o_empty // read side synced
);

    function automatic logic [CNT_W:0] bin2gray (
        input logic [CNT_W:0] bin
    );
        bin2gray = bin ^ (bin >> 1);
    endfunction

    function automatic logic [CNT_W:0] gray2bin (
        input logic [CNT_W:0] gray
    );
        for (int i = 0; i < (CNT_W+1); i++) begin
            gray2bin[i] = ^(gray >> i);
        end
    endfunction

    dtype_t array [0:DEPTH-1];

    // Write side wires/regs
    logic [CNT_W:0] wr_side_wr_ptr_b, wr_side_wr_ptr_g;
    logic [CNT_W:0] wr_side_rd_ptr_b, wr_side_rd_ptr_g;

    // Read side wires/regs
    logic [CNT_W:0] rd_side_rd_ptr_b, rd_side_rd_ptr_g;
    logic [CNT_W:0] rd_side_wr_ptr_b, rd_side_wr_ptr_g;

    // Synchronize pointers to each side

    // Write pointer sync to read side
    sync3 #(
        .WIDTH(CNT_W + 1)
    ) wr_ptr_sync_read_side (
        .i_clk(i_rd_clk),
        .i_reset_n(i_rd_reset_n),
        .i_d(wr_side_wr_ptr_g),
        .o_q(rd_side_wr_ptr_g)
    );

    assign rd_side_wr_ptr_b = gray2bin(rd_side_wr_ptr_g);

    // Read pointer sync to write side
    sync3 #(
        .WIDTH(CNT_W + 1)
    ) rd_ptr_sync_write_side (
        .i_clk(i_wr_clk),
        .i_reset_n(i_wr_reset_n),
        .i_d(rd_side_rd_ptr_g),
        .o_q(wr_side_rd_ptr_g)
    );

    assign wr_side_rd_ptr_b = gray2bin(wr_side_rd_ptr_g);

    // Write side storage + pointer incrementing
    always_ff @(posedge i_wr_clk) begin
        if (~i_wr_reset_n) begin
            wr_side_wr_ptr_b <= '0;
            wr_side_wr_ptr_g <= '0;
        end else begin
            if (i_wr_valid && o_wr_ready) begin
                array[wr_side_wr_ptr_b[CNT_W-1:0]] <= i_wr_data;
                wr_side_wr_ptr_b <= wr_side_wr_ptr_b + 1'b1;
                wr_side_wr_ptr_g <= bin2gray(wr_side_wr_ptr_b + 1'b1);
            end
        end
    end

    // Read side pointer incrementing
    always_ff @(posedge i_rd_clk) begin
        if (~i_rd_reset_n) begin
            rd_side_rd_ptr_b <= '0;
            rd_side_rd_ptr_g <= '0;
        end else begin
            if (i_rd_ready && o_rd_valid) begin
                rd_side_rd_ptr_b <= rd_side_rd_ptr_b + 1'b1;
                rd_side_rd_ptr_g <= bin2gray(rd_side_rd_ptr_b + 1'b1);
            end
        end
    end

    // Outputs
    assign o_full = (wr_side_rd_ptr_b[CNT_W] != wr_side_wr_ptr_b[CNT_W]) && (wr_side_rd_ptr_b[CNT_W-1:0] == wr_side_wr_ptr_b[CNT_W-1:0]);
    assign o_empty = (rd_side_rd_ptr_b == rd_side_wr_ptr_b);
    assign o_wr_ready = ~o_full;
    assign o_rd_valid = ~o_empty;
    assign o_rd_data = array[rd_side_rd_ptr_b[CNT_W-1:0]];

`ifdef SIM
    initial assert ((DEPTH >= 2) && !(DEPTH & (DEPTH - 1)))
        else $fatal(1, "async_fifo - DEPTH parameter must be a power of 2 parameter that is >= 2");
`endif

endmodule
