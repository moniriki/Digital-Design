module nxn_matrix_lru_arb_complex # (
    parameter int unsigned WIDTH = 4,
    localparam int unsigned WIDTH_LOG2 = $clog2(WIDTH)
) (
    input logic i_clk,
    input logic i_reset_n,
    input logic [WIDTH-1:0] i_request,
    output logic [WIDTH-1:0] o_grant
);

    // LRU NxN decision matrix
    logic [WIDTH-1:0][WIDTH-1:0] matrix;
    logic [WIDTH_LOG2-1:0] grant_index;

    always_comb begin
        grant_index = '0;
        for (int unsigned i = 0; i < WIDTH; i++) begin
            if (o_grant[i] == 1'b1) begin
                grant_index = WIDTH_LOG2'(i);
            end
        end
    end

    always_ff @(posedge i_clk) begin
        if (~i_reset_n) begin
            for (int unsigned i = 0; i < WIDTH; i++) begin
                for (int unsigned j = 0; j < WIDTH; j++) begin
                    matrix[i][j] <= 1'b1; // Initialize all decisions to 1
                end
            end
        end else begin
            if (|o_grant) begin // Every grant requires matrix update
                for (int unsigned i = 0; i < WIDTH; i++) begin
                    if (i != grant_index) begin
                        matrix[grant_index][i] <= 1'b0;
                        matrix[i][grant_index] <= 1'b1;
                    end
                end
            end
        end
    end

    logic [WIDTH-1:0] grant_d;
    logic requestor_found, requestor_valid;

    always_comb begin
        requestor_found = 1'b0;
        grant_d = WIDTH'(0);
        requestor_valid = 1'b0;

        // Iterate across requestors
        for (int unsigned i = 0; i < WIDTH; i++) begin: iter_requestors

            // If valid requestor not found yet, and valid requestor, check matrix across columns, if all 1's then we found the grant, skip next iteration
            if (~requestor_found) begin
                if (i_request[i]) begin: valid_requestor
                    requestor_valid = 1'b1;

                    for (int unsigned j = 0; j < WIDTH; j++) begin
                        if (i_request[j]) begin
                            requestor_valid &= matrix[i][j];

                        end
                    end

                    if (requestor_valid) begin
                        requestor_found = 1'b1;
                        grant_d = (1'b1 << i);
                    end
                end
            end
        end
    end

    assign o_grant = grant_d;

endmodule

module tt_nxn_matrix_lru_arb # (
    parameter int unsigned WIDTH = 4
) (
    input logic i_clk,
    input logic i_reset_n,
    input logic [WIDTH-1:0] i_request,
    output logic [WIDTH-1:0] o_grant
);

    logic [WIDTH-1:0][WIDTH-1:0] matrix;

    always_ff @(posedge i_clk) begin
        if (~i_reset_n) begin
            for (int unsigned i = 0; i < WIDTH; i++) begin
                for (int unsigned j = 0; j < WIDTH; j++) begin
                    matrix[i][j] <= (i < j);
                end
            end
        end else begin
            for (int unsigned i = 0; i < WIDTH; i++) begin
                if (o_grant[i]) begin // one-hot signal
                    for (int unsigned j = 0; j < WIDTH; j++) begin
                        if (i != j) begin
                            matrix[i][j] <= 1'b0;
                            matrix[j][i] <= 1'b1;
                        end
                    end
                end
            end
        end
    end

    always_comb begin
        for (int unsigned i = 0; i < WIDTH; i++) begin
            o_grant[i] = i_request[i];

            for (int unsigned j = 0; j < WIDTH; j++) begin
                if (i != j) begin
                    o_grant[i] &= (~i_request[j] || matrix[i][j]);
                end
            end
        end
    end

endmodule