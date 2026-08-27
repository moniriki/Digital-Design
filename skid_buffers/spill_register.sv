module spill_register #(
    parameter int unsigned DATA_WIDTH = 32
) (
    input logic i_clk,
    input logic i_reset_n,

    input logic i_valid,
    input logic [DATA_WIDTH-1:0] i_data,
    output logic o_ready,

    output logic o_valid,
    output logic [DATA_WIDTH-1:0] o_data,
    input logic i_ready
);

    logic spill_valid;
    logic [DATA_WIDTH-1:0] spill_data;

    assign o_ready = ~spill_valid;

    always_ff @(posedge i_clk) begin
        if (~i_reset_n) begin
            spill_valid <= 1'b0;
            spill_data <= DATA_WIDTH'(0);
        end else begin
            if (spill_valid && i_ready) begin
                spill_valid <= 1'b0;
                spill_data <= DATA_WIDTH'(0);
            end else if (~spill_valid && ~i_ready && i_valid) begin
                spill_valid <= 1'b1;
                spill_data <= i_data;
            end
        end
    end

    assign o_valid = spill_valid ? 1'b1 : i_valid;
    assign o_data  = spill_valid ? spill_data : i_data;

endmodule