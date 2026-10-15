`timescale 1ns / 1ps

module uart_rx_partial_scan #(
    parameter CLKS_PER_BIT = 16
)(
    input        clk,
    input        rst,
    input        uart_rx,
    input        rx_ready,

    input        scan_en,
    input        scan_in,
    output       scan_out,

    output [7:0] rx_data,
    output       rx_valid,
    output       framing_error
);

    localparam COUNT_WIDTH =
        (CLKS_PER_BIT > 1) ? $clog2(CLKS_PER_BIT) : 1;

    localparam HALF_BIT = CLKS_PER_BIT / 2;

    localparam TOTAL_FF    = 25 + COUNT_WIDTH;
    localparam SCAN_LENGTH = COUNT_WIDTH + 2;

    localparam SCAN_FIRST = 8 + 3;
    localparam SCAN_LAST  = SCAN_FIRST + SCAN_LENGTH - 1;

    localparam [1:0] IDLE  = 2'b00,
                     START = 2'b01,
                     DATA  = 2'b10,
                     STOP  = 2'b11;

    wire [7:0]             data_reg;
    wire [2:0]             bit_index;
    wire [COUNT_WIDTH-1:0] clk_count;
    wire [1:0]             state;

    wire rx_meta;
    wire rx_sync;

    reg [7:0]             data_next;
    reg [2:0]             bit_index_next;
    reg [COUNT_WIDTH-1:0] clk_count_next;
    reg [1:0]             state_next;

    reg [7:0] rx_data_next;
    reg       rx_valid_next;
    reg       framing_error_next;

    wire [TOTAL_FF-1:0]    ff_d;
    wire [TOTAL_FF-1:0]    ff_q;
    wire [SCAN_LENGTH:0]  scan_link;

    always @(*) begin
        data_next          = data_reg;
        bit_index_next     = bit_index;
        clk_count_next     = clk_count;
        state_next         = state;

        rx_data_next       = rx_data;
        rx_valid_next      = rx_valid;
        framing_error_next = 1'b0;

        if (rx_valid && rx_ready)
            rx_valid_next = 1'b0;

        case (state)
            IDLE: begin
                clk_count_next = 0;
                bit_index_next = 0;

                if (!rx_sync)
                    state_next = START;
            end

            START: begin
                if (clk_count == HALF_BIT - 1) begin
                    clk_count_next = 0;

                    if (rx_sync)
                        state_next = IDLE;
                    else
                        state_next = DATA;
                end
                else begin
                    clk_count_next = clk_count + 1'b1;
                end
            end

            DATA: begin
                if (clk_count < CLKS_PER_BIT - 1) begin
                    clk_count_next = clk_count + 1'b1;
                end
                else begin
                    clk_count_next       = 0;
                    data_next[bit_index] = rx_sync;

                    if (bit_index < 7)
                        bit_index_next = bit_index + 1'b1;
                    else
                        state_next = STOP;
                end
            end

            STOP: begin
                if (clk_count < CLKS_PER_BIT - 1) begin
                    clk_count_next = clk_count + 1'b1;
                end
                else begin
                    clk_count_next = 0;
                    state_next     = IDLE;

                    if (rx_sync) begin
                        if (!rx_valid || rx_ready) begin
                            rx_data_next  = data_reg;
                            rx_valid_next = 1'b1;
                        end
                    end
                    else begin
                        framing_error_next = 1'b1;
                    end
                end
            end

            default: begin
                state_next     = IDLE;
                clk_count_next = 0;
                bit_index_next = 0;
            end
        endcase
    end

    assign ff_d = {
        rx_meta,
        uart_rx,
        framing_error_next,
        rx_valid_next,
        rx_data_next,
        state_next,
        clk_count_next,
        bit_index_next,
        data_next
    };

    assign {
        rx_sync,
        rx_meta,
        framing_error,
        rx_valid,
        rx_data,
        state,
        clk_count,
        bit_index,
        data_reg
    } = ff_q;

    genvar i;
    generate
        for (i = 0; i < TOTAL_FF; i = i + 1) begin : GEN_FF

            if ((i >= SCAN_FIRST) &&
                (i <= SCAN_LAST)) begin : SCANNED

                scan_dff #(
                    .RESET_VALUE(1'b0)
                ) u_scan_dff (
                    .clk     (clk),
                    .rst     (rst),
                    .scan_en (scan_en),
                    .d_in    (ff_d[i]),
                    .scan_in (scan_link[i - SCAN_FIRST]),
                    .q       (ff_q[i])
                );

                assign scan_link[i - SCAN_FIRST + 1] =
                    ff_q[i];

            end
            else begin : NON_SCANNED
                reg q_reg;

                always @(posedge clk) begin
                    if (rst)
                        q_reg <= (i >= TOTAL_FF - 2)
                                 ? 1'b1 : 1'b0;
                    else
                        q_reg <= ff_d[i];
                end

                assign ff_q[i] = q_reg;
            end
        end
    endgenerate

    assign scan_link[0] = scan_in;
    assign scan_out    = scan_link[SCAN_LENGTH];

endmodule