`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/07/2026 08:44:51 PM
// Design Name: 
// Module Name: scan_chain4
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


module scan_chain4(
    input        clk,
    input        rst,
    input        scan_en,
    input        scan_in,
    input  [3:0] d_in,
    output [3:0] q,
    output       scan_out
    );
    
    scan_dff #(.RESET_VALUE(1'b0)) cell0 (
        .clk(clk),
        .rst(rst),
        .scan_en(scan_en),
        .scan_in(scan_in),
        .d_in(d_in[0]),
        .q(q[0]));
        
    scan_dff #(.RESET_VALUE(1'b0)) cell1 (
        .clk(clk),
        .rst(rst),
        .scan_en(scan_en),
        .scan_in(q[0]),
        .d_in(d_in[1]),
        .q(q[1]));
        
    scan_dff #(.RESET_VALUE(1'b0)) cell2 (
        .clk(clk),
        .rst(rst),
        .scan_en(scan_en),
        .scan_in(q[1]),
        .d_in(d_in[2]),
        .q(q[2]));
        
    scan_dff #(.RESET_VALUE(1'b0)) cell3 (
        .clk(clk),
        .rst(rst),
        .scan_en(scan_en),
        .scan_in(q[2]),
        .d_in(d_in[3]),
        .q(q[3]));
        
    assign scan_out = q[3];
    
endmodule
