// One-hot to binary encoder.
module onehot2bin #(
    parameter  int unsigned WIDTH   = 8,
    localparam int unsigned BIN_W   = (WIDTH <= 1) ? 1 : $clog2(WIDTH)
) (
    input  logic [WIDTH-1:0] i_onehot,
    output logic [BIN_W-1:0] o_bin
);

    always_comb begin
        o_bin = '0;
        for (int unsigned i = 0; i < WIDTH; i++) begin
            if (i_onehot[i]) begin
                o_bin = BIN_W'(i);
            end
        end
    end

endmodule
