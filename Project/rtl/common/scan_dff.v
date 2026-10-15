`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/07/2026 07:45:41 PM
// Design Name: 
// Module Name: scan_dff
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


module scan_dff #(parameter RESET_VALUE = 1'b0)(
    input      clk,
    input      rst,
    input      scan_en,
    input      d_in,
    input      scan_in,
    output reg q
    );
    
    wire d;
    
    always @(posedge clk) begin
        if (rst) q <= RESET_VALUE;
        else q <= d;
    end
    
    assign d = scan_en ? scan_in : d_in;
    
endmodule
