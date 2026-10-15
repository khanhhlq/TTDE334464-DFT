`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/21/2026 03:17:19 PM
// Design Name: 
// Module Name: FIFO
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


module sync_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 16
)(
    input                        clk,
    input                        rst,
    input                        wr_en,
    input      [DATA_WIDTH-1:0]  wr_data,
    input                        rd_en,
    output     [DATA_WIDTH-1:0]  rd_data,
    output                       full,
    output                       empty
);

    localparam PTR_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1;

    localparam COUNT_WIDTH = $clog2(DEPTH + 1);

    reg [DATA_WIDTH-1:0]  mem [0:DEPTH-1];

    reg [PTR_WIDTH-1:0]   wr_ptr;
    reg [PTR_WIDTH-1:0]   rd_ptr;
    reg [COUNT_WIDTH-1:0] count;

    wire write_ok;
    wire read_ok;

    assign write_ok = wr_en && !full;  
    assign read_ok  = rd_en && !empty; 

    assign full  = (count == DEPTH);
    assign empty = (count == 0);

    assign rd_data = mem[rd_ptr];

    always @(posedge clk) begin
        if (rst) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count  <= 0;
        end
        else begin

            if (write_ok) begin

                mem[wr_ptr] <= wr_data;

                if (wr_ptr == DEPTH - 1)
                    wr_ptr <= 0;
                else
                    wr_ptr <= wr_ptr + 1'b1;
            end

            if (read_ok) begin
                if (rd_ptr == DEPTH - 1)
                    rd_ptr <= 0;
                else
                    rd_ptr <= rd_ptr + 1'b1;
            end

             case ({write_ok, read_ok})
                2'b10: count <= count + 1'b1; 
                2'b01: count <= count - 1'b1; 
                default: count <= count;     
            endcase
        end
    end

endmodule
