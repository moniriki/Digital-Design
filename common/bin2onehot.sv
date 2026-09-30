// Binary to one-hot decoder.
module bin2onehot #(
    parameter  int unsigned WIDTH   = 8,
    localparam int unsigned BIN_W   = (WIDTH <= 1) ? 1 : $clog2(WIDTH)
) (
    input  logic [BIN_W-1:0] i_bin,
    output logic [WIDTH-1:0] o_onehot
);

    assign o_onehot = WIDTH'(1) << WIDTH'(i_bin);

endmodule
