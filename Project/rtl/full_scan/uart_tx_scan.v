`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/07/2026 10:27:35 AM
// Design Name: 
// Module Name: uart_tx_scan
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


module uart_tx_scan #(parameter CLKS_PER_BIT = 16)(
    input            clk,
    input            rst,
    input      [7:0] tx_data,
    input            tx_valid,
    input            scan_en,
    input            scan_in,
    output           tx_ready,
    output           uart_tx,
    output           scan_out
    );
    
    localparam COUNT_WIDTH = 
    (CLKS_PER_BIT > 1) ? $clog2(CLKS_PER_BIT) : 1;
    localparam SCAN_LENGTH = 8 + 3 + COUNT_WIDTH + 2 + 1;
    localparam IDLE  = 2'b00;
    localparam START = 2'b01;
    localparam DATA  = 2'b10;
    localparam STOP  = 2'b11;
    
    wire [7:0] data_reg; 
    wire [2:0] bit_index;
    wire [COUNT_WIDTH-1:0] clk_count;
    wire [1:0] state;
    
    reg [7:0] data_next; 
    reg [2:0] bit_index_next;
    reg [COUNT_WIDTH-1:0] clk_count_next;
    reg [1:0] state_next; 
    reg uart_tx_next;
    
    wire [SCAN_LENGTH-1:0] scan_d;
    wire [SCAN_LENGTH-1:0] scan_q;
    wire [SCAN_LENGTH:0]   scan_link;
        
    always @(*) begin
        data_next      = data_reg;
        bit_index_next = bit_index;
        clk_count_next = clk_count;
        state_next     = state;
        uart_tx_next   = uart_tx;

        case (state)
            IDLE: begin
                    uart_tx_next   = 1'b1;
                    clk_count_next = 1'b0;
                    bit_index_next = 1'b0;
                    
                if (tx_valid && tx_ready) begin 
                    data_next    = tx_data;
                    uart_tx_next = 1'b0;
                    state_next   = START;
                end
            end
            START: begin
                    if (clk_count != CLKS_PER_BIT -1)
                        clk_count_next = clk_count +1;
                    else begin
                        clk_count_next = 1'b0;
                        uart_tx_next   = data_reg[0];
                        state_next     = DATA;
                    end
                end
            DATA: begin
                    if (clk_count != CLKS_PER_BIT -1)
                        clk_count_next = clk_count +1;
                    else begin
                        if (bit_index < 7) begin
                            clk_count_next = 1'b0;
                            bit_index_next = bit_index +1;
                            uart_tx_next   = data_reg[bit_index +1];
                        end
                        else begin
                            clk_count_next = 1'b0;
                            uart_tx_next   = 1'b1;
                            state_next     = STOP;
                        end
                    end
                end
                STOP: begin
                    if (clk_count != CLKS_PER_BIT -1) 
                        clk_count_next = clk_count +1;
                    else begin
                        clk_count_next = 1'b0;
                        state_next     = IDLE;
                    end
                end    
        endcase
    end
    
    genvar i;
    generate
    for (i = 0; i < SCAN_LENGTH; i = i + 1) begin : GEN_SCAN
        scan_dff #(.RESET_VALUE((i == SCAN_LENGTH - 1) ? 1'b1 : 1'b0)) u_scan_dff (
            .clk(clk),
            .rst(rst),
            .scan_en(scan_en),
            .d_in(scan_d[i]),
            .scan_in(scan_link[i]),
            .q(scan_q[i]));
            
        assign scan_link[i+1] = scan_q[i];
    end
    endgenerate
    
    assign tx_ready = (state == IDLE) ? 1'b1 : 1'b0;   

    assign scan_d = {uart_tx_next, state_next, clk_count_next, bit_index_next, data_next};    
    
    assign {uart_tx, state, clk_count, bit_index, data_reg} = scan_q;
        
    assign scan_link[0] = scan_in;
    
    assign scan_out = scan_link[SCAN_LENGTH];
    
endmodule
