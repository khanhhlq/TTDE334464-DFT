`timescale 1ns / 1ps

// UART RX: 8 data bits, no parity, 1 stop bit.
// Nhan LSB truoc.
// Dung CLKS_PER_BIT >= 16 cho ban thiet ke nay.

module uart_rx #(
    parameter CLKS_PER_BIT = 16
)(
    input            clk,
    input            rst,
    input            uart_rx,
    input            rx_ready,
    output reg [7:0] rx_data,
    output reg       rx_valid,
    output reg       framing_error
);

    localparam integer COUNT_WIDTH = (CLKS_PER_BIT <= 1) ? 1 : $clog2(CLKS_PER_BIT);

    localparam integer HALF_BIT = CLKS_PER_BIT / 2;

    localparam [1:0] IDLE  = 2'b00,
                     START = 2'b01,
                     DATA  = 2'b10,
                     STOP  = 2'b11;

    reg [2:0]             bit_index;
    reg [COUNT_WIDTH-1:0] clk_count;
    reg [1:0]             state;
    reg [7:0]             data_reg;

    reg rx_meta;
    reg rx_sync;

    always @(posedge clk) begin
        if (rst) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end
        else begin
            rx_meta <= uart_rx;
            rx_sync <= rx_meta;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state         <= IDLE;
            rx_data       <= 8'b0;
            rx_valid      <= 1'b0;
            framing_error <= 1'b0;
            clk_count     <= 0;
            bit_index     <= 0;
            data_reg      <= 8'b0;
        end
        else begin

            framing_error <= 1'b0;

            if (rx_valid && rx_ready)
                rx_valid <= 1'b0;

            case (state)

                IDLE: begin
                    clk_count <= 0;
                    bit_index <= 0;

                    if (!rx_sync)
                        state <= START;
                end

                START: begin
                    if (clk_count == HALF_BIT - 1) begin
                        
                        clk_count <= 0;

                        if (rx_sync)
                            state <= IDLE;
                        else
                            state <= DATA;
                    end
                    else 
                        clk_count <= clk_count + 1'b1;
                end

                DATA: begin

                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end
                    else begin

                        clk_count <= 0;
                        data_reg[bit_index] <= rx_sync;

                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1'b1;
                        end
                        else begin
                            state <= STOP;
                        end
                    end
                end

                STOP: begin
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end
                    else begin
                        clk_count <= 0;
                        state <= IDLE;

                        if (rx_sync) begin

                            if (!rx_valid || rx_ready) begin
                                rx_data  <= data_reg;
                                rx_valid <= 1'b1;
                            end
                        end
                        else 
                            framing_error <= 1'b1;
                    end
                end

                default: begin
                    state     <= IDLE;
                    clk_count <= 0;
                    bit_index <= 0;
                end

            endcase
        end
    end

endmodule