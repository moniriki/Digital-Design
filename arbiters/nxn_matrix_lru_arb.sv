// N-requester least-recently-used arbiter, matrix formulation.
//
// State is an N x N bit matrix where matrix[i][j] == 1 means "requester i
// currently outranks requester j". It is kept antisymmetric off the diagonal
// (matrix[i][j] != matrix[j][i]), so for any set of contending requesters
// exactly one wins:
//
//   o_grant[i] = i_request[i] AND (for every other requester j, matrix[i][j])
//
// After a grant, the winner is pushed to lowest priority: its row is cleared
// and its column is set, so every other requester now outranks it. Reset seeds
// a strict order (matrix[i][j] = i < j), i.e. lower index starts highest.
//
// Purely single-cycle: the grant is combinational from the registered matrix
// and i_request; no handshake or backpressure.
module nxn_matrix_lru_arb #(
    parameter int unsigned WIDTH = 4
) (
    input  logic             i_clk,
    input  logic             i_reset_n,
    input  logic [WIDTH-1:0] i_request,
    output logic [WIDTH-1:0] o_grant
);

    logic matrix [WIDTH][WIDTH];

    always_ff @(posedge i_clk) begin
        if (~i_reset_n) begin
            for (int unsigned i = 0; i < WIDTH; i++) begin
                for (int unsigned j = 0; j < WIDTH; j++) begin
                    matrix[i][j] <= (i < j);
                end
            end
        end else begin
            for (int unsigned i = 0; i < WIDTH; i++) begin
                if (o_grant[i]) begin // o_grant is one-hot
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
