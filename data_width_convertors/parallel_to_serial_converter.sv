// Parallel-in, serial-out shifter with valid/ready on both sides.
//
// Accepts a DATA_WIDTH-bit word when idle (o_ready high) and shifts it out one
// bit per cycle, LSB first, on o_data while o_valid is high. o_data advances
// only when the sink accepts (i_ready); it holds otherwise. o_ready reasserts
// the cycle after the last bit leaves, so throughput is one word every
// DATA_WIDTH+1 cycles.
module parallel_to_serial_converter #(
    parameter  int unsigned DATA_WIDTH      = 4,
    localparam int unsigned DATA_WIDTH_LOG2 = $clog2(DATA_WIDTH)
) (
    input logic i_clk,
    input logic i_reset_n,
    input logic i_valid,
    input logic [DATA_WIDTH-1:0] i_data,
    output logic o_ready,

    output logic o_valid,
    output logic o_data,
    input logic i_ready
);

    logic [DATA_WIDTH-1:0] shift_reg;
    logic [DATA_WIDTH_LOG2:0] cnt;

    always_ff @(posedge i_clk) begin
        if (~i_reset_n) begin
            cnt <= '0;
        end else begin
            if (|cnt) begin
                if (i_ready) begin
                    shift_reg <= shift_reg >> 1'b1;
                    cnt <= cnt - 1'b1;
                end
            end else begin
                if (i_valid) begin
                    shift_reg <= i_data;
                    cnt <= (DATA_WIDTH_LOG2+1)'(DATA_WIDTH);
                end
            end
        end
    end

    assign o_ready = ~(|cnt);
    assign o_valid = |cnt;
    assign o_data = shift_reg[0];

endmodule
