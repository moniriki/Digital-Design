module serial_to_parallel_convertor # (
    parameter int unsigned DATA_WIDTH = 4,
    localparam int unsigned DATA_WIDTH_LOG2 = $clog2(DATA_WIDTH)
) (
    input logic i_clk,
    input logic i_reset_n,
    input logic i_valid,
    input logic i_data,
    output logic o_ready,

    output logic o_valid,
    output logic [DATA_WIDTH-1:0] o_data,
    input logic i_ready
);

    logic [DATA_WIDTH-1:0] shift_reg;
    logic [DATA_WIDTH_LOG2:0] cnt;


    always_ff @(posedge i_clk) begin
        if (~i_reset_n) begin
            cnt <= '0;
        end else begin
            if (o_valid && i_ready) begin
                cnt <= '0;
            end else begin
                if (i_valid && o_ready) begin
                    shift_reg <= {i_data, shift_reg[1 +: DATA_WIDTH-1]};
                    cnt <= cnt + 1'b1;
                end
            end
        end
    end

    assign o_ready = (cnt < DATA_WIDTH);
    assign o_valid = (cnt == DATA_WIDTH);
    assign o_data = shift_reg;

endmodule
