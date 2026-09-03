module parallel_to_serial_convertor # (
    parameter int unsigned DATA_WIDTH = 4,
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
