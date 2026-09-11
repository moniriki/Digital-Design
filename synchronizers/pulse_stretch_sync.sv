// Stretch-and-resync pulse CDC: widens a 1-cycle i_src_clk pulse to ~2 dst
// periods, then 3-FF syncs and edge-detects it in i_dst_clk. Async-safe, but
// only if source pulses are spaced >= ~6*CDC_RATIO source cycles apart.
module pulse_stretch_sync #(
    parameter int unsigned SRC_FREQ = 2,
    parameter int unsigned DST_FREQ = 1,
    localparam int unsigned CDC_RATIO = (SRC_FREQ >= DST_FREQ) ? (2 * ((SRC_FREQ + DST_FREQ - 1) / DST_FREQ)) : 2,
    localparam int unsigned STRETCH_CNT = (CDC_RATIO == 1) ? 1 : $clog2(CDC_RATIO)
) (
    input  logic i_src_clk,
    input  logic i_src_reset_n,
    input  logic i_pulse,

    input  logic i_dst_clk,
    input  logic i_dst_reset_n,
    output logic o_pulse
);

    logic src_q, src_d;
    logic [STRETCH_CNT:0] cnt_q, cnt_d;
    logic dst_qqq, dst_qq, dst_q, dst_d;
    logic src_pulse_stretched;

    always_ff @(posedge i_src_clk) begin
        if (~i_src_reset_n) begin
            src_q <= 1'b0;
            cnt_q <= '0;
        end else begin
            src_q <= src_d;
            cnt_q <= cnt_d;
        end
    end

    always_comb begin
        src_d = i_pulse;
        cnt_d = cnt_q;

        // Count logic
        if ((cnt_d == ((STRETCH_CNT + 1)'(CDC_RATIO - 1))) || ((cnt_q == 0) && ~(src_d && ~src_q))) begin
            cnt_d = '0;
        end else begin
            cnt_d += 1'b1;
        end

    end

    always_ff @(posedge i_src_clk) begin
        if (~i_src_reset_n) begin
            src_pulse_stretched <= 1'b0;
        end else begin
            if (cnt_q == 0) begin
                src_pulse_stretched <= i_pulse;
            end
        end
    end

    // Destination pulse detector with 3 stage synchronizer
    always_ff @(posedge i_dst_clk) begin
        if (~i_dst_reset_n) begin
            dst_q <= 1'b0;
            dst_qq <= 1'b0;
            dst_qqq <= 1'b0;
        end else begin
            dst_q <= dst_d;
            dst_qq <= dst_q;
            dst_qqq <= dst_qq;
        end
    end

    always_comb begin
        dst_d = src_pulse_stretched;
    end

    assign o_pulse = ~dst_qqq && dst_qq;

`ifdef SIM
    initial assert ((SRC_FREQ >= 1) && (DST_FREQ >= 1))
        else $fatal(1, "pulse_stretch_sync: SRC_FREQ and DST_FREQ must be >= 1");
`endif

endmodule
