module skid_buf #(
    parameter int unsigned WIDTH = 32
) (
    input logic i_clk,
    input logic i_reset_n,

    input logic i_valid,
    input logic [WIDTH-1:0] i_data,
    output logic o_ready,

    output logic o_valid,
    output logic [WIDTH-1:0] o_data,
    input logic i_ready
);

    logic master_valid;
    logic [WIDTH-1:0] master_data;

    logic skid_valid;
    logic [WIDTH-1:0] skid_data;

    assign o_ready = ~skid_valid; // Cut timing
    assign o_valid = master_valid; // Cut timing
    assign o_data = master_data; // Cut timing

    always_ff @(posedge i_clk) begin
        if (~i_reset_n) begin
            master_valid <= 1'b0;
            master_data <= '0;
            skid_valid <= 1'b0;
            skid_data <= '0;
        end else begin
            if (~skid_valid) begin
                if (master_valid) begin
                    if (i_ready) begin
                        master_valid <= i_valid;
                        master_data <= i_valid ? i_data : master_data;
                    end else begin
                        skid_valid <= i_valid;
                        skid_data <= i_valid ? i_data : skid_data;
                    end
                end else begin
                    master_valid <= i_valid;
                    master_data <= i_valid ? i_data : master_data;
                end // ~master_valid
            end else begin
                if (i_ready) begin
                    master_valid <= skid_valid;
                    master_data <= skid_data;
                    skid_valid <= 1'b0;
                    skid_data <= WIDTH'(0);
                end
            end // skid_valid
        end
    end

endmodule