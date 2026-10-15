`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/07/2026 10:27:35 AM
// Design Name: 
// Module Name: uart_tx
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// Định dạng khung truyền là 8N1: 1 bit start, 8 bit dữ liệu, không parity, 1 bit stop. 
// Bit dữ liệu thấp nhất được gửi trước.

module uart_tx #(parameter CLKS_PER_BIT = 16)(
    input            clk,
    input            rst,
    input      [7:0] tx_data,
    input            tx_valid,
    output           tx_ready,
    output reg       uart_tx
    );
    
    localparam COUNT_WIDTH = (CLKS_PER_BIT > 1) ? $clog2(CLKS_PER_BIT) : 1;
    
    localparam IDLE  = 2'b00;
    localparam START = 2'b01;
    localparam DATA  = 2'b10;
    localparam STOP  = 2'b11;
    
    reg [7:0]             data_reg; 
    reg [2:0]             bit_index;
    reg [COUNT_WIDTH-1:0] clk_count;
    reg [1:0]             state;
    
    always @(posedge clk) begin
        if (rst) begin
            state     <= IDLE;
            uart_tx   <= 1'b1;
            data_reg  <= 0;
            bit_index <= 0;
            clk_count <= 0;
        end
        else begin
            case (state)
                IDLE: begin
                        uart_tx   <= 1'b1;
                        clk_count <= 1'b0;
                        bit_index <= 1'b0;
                    
                    if (tx_valid && tx_ready) begin 
                        data_reg <= tx_data;
                        uart_tx  <= 1'b0;
                        state    <= START;
                    end
                end
                START: begin
                    if (clk_count != CLKS_PER_BIT -1)
                        clk_count <= clk_count +1;
                    else begin
                        clk_count <= 1'b0;
                        uart_tx   <= data_reg[0];
                        state     <= DATA;
                    end
                end
                DATA: begin
                    if (clk_count != CLKS_PER_BIT -1)
                        clk_count <= clk_count +1;
                    else begin
                        if (bit_index < 7) begin
                            clk_count <= 1'b0;
                            bit_index <= bit_index +1;
                            uart_tx   <= data_reg[bit_index +1];
                        end
                        else begin
                            clk_count <= 1'b0;
                            uart_tx   <= 1'b1;
                            state     <= STOP;
                        end
                    end
                end
                STOP: begin
                    if (clk_count != CLKS_PER_BIT -1) 
                        clk_count <= clk_count +1;
                    else begin
                        clk_count <= 1'b0;
                        state     <= IDLE;
                    end
                end
            endcase
        end
    end
    
    assign tx_ready = (state == IDLE) ? 1'b1 : 1'b0; 
    
endmodule
