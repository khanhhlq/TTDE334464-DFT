`timescale 1ns / 1ps

// UART RX: 8 data bits, no parity, 1 stop bit.
// Nhan LSB truoc.
// Dung CLKS_PER_BIT >= 16.

module uart_rx_scan #(
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

    localparam integer COUNT_WIDTH =
        (CLKS_PER_BIT <= 1) ? 1 : $clog2(CLKS_PER_BIT);

    localparam integer HALF_BIT = CLKS_PER_BIT / 2;

    localparam integer SCAN_LENGTH = 25 + COUNT_WIDTH;

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

    wire rx_meta_next;
    wire rx_sync_next;

    wire [SCAN_LENGTH-1:0] scan_d;
    wire [SCAN_LENGTH-1:0] scan_q;
    wire [SCAN_LENGTH:0]   scan_link;

    assign rx_meta_next = uart_rx;
    assign rx_sync_next = rx_meta;

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
                    clk_count_next = 0;

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

    assign scan_d = {
        rx_sync_next,
        rx_meta_next,
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
    } = scan_q;

    assign scan_link[0] = scan_in;
    assign scan_out    = scan_link[SCAN_LENGTH];

    genvar i;
    generate
        for (i = 0; i < SCAN_LENGTH; i = i + 1) begin : GEN_SCAN
            scan_dff #(
                .RESET_VALUE(
                    (i >= SCAN_LENGTH - 2) ? 1'b1 : 1'b0
                )
            ) u_scan_dff (
                .clk     (clk),
                .rst     (rst),
                .scan_en (scan_en),
                .d_in    (scan_d[i]),
                .scan_in (scan_link[i]),
                .q       (scan_q[i])
            );

            assign scan_link[i+1] = scan_q[i];
        end
    endgenerate

endmodule