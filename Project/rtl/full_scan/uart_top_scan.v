`timescale 1ns / 1ps

module uart_top_scan #(
    parameter CLKS_PER_BIT = 16,
    parameter FIFO_DEPTH   = 16
)(
    input        clk,
    input        rst,

    input        uart_rx,
    output       uart_tx,

    input        tx_wr_en,
    input  [7:0] tx_wr_data,
    output       tx_full,

    input        rx_rd_en,
    output [7:0] rx_rd_data,
    output       rx_empty,

    output       framing_error,

    input        scan_en,
    input        scan_in,
    output       scan_out
);

    wire [7:0] tx_fifo_rd_data;
    wire       tx_fifo_empty;
    wire       tx_fifo_rd_en;

    wire [7:0] tx_data;
    wire       tx_valid;
    wire       tx_ready;

    wire [7:0] rx_data;
    wire       rx_valid;
    wire       rx_ready;

    wire [7:0] rx_fifo_wr_data;
    wire       rx_fifo_wr_en;
    wire       rx_fifo_full;

    wire scan_tx_fifo_to_tx;
    wire scan_tx_to_rx;
    wire scan_rx_to_rx_fifo;

    assign tx_data       = tx_fifo_rd_data;
    assign tx_valid      = !rst && !tx_fifo_empty;
    assign tx_fifo_rd_en = tx_valid && tx_ready;

    assign rx_ready        = !rst && !rx_fifo_full;
    assign rx_fifo_wr_data = rx_data;
    assign rx_fifo_wr_en   = rx_valid && rx_ready;

    sync_fifo_scan #(
        .DATA_WIDTH(8),
        .DEPTH     (FIFO_DEPTH)
    ) tx_fifo (
        .clk      (clk),
        .rst      (rst),

        .wr_en    (tx_wr_en),
        .wr_data  (tx_wr_data),
        .rd_en    (tx_fifo_rd_en),
        .rd_data  (tx_fifo_rd_data),
        .full     (tx_full),
        .empty    (tx_fifo_empty),

        .scan_en  (scan_en),
        .scan_in  (scan_in),
        .scan_out (scan_tx_fifo_to_tx)
    );

    uart_tx_scan #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) tx (
        .clk      (clk),
        .rst      (rst),

        .tx_data  (tx_data),
        .tx_valid (tx_valid),
        .tx_ready (tx_ready),
        .uart_tx  (uart_tx),

        .scan_en  (scan_en),
        .scan_in  (scan_tx_fifo_to_tx),
        .scan_out (scan_tx_to_rx)
    );

    uart_rx_scan #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) rx (
        .clk           (clk),
        .rst           (rst),

        .uart_rx       (uart_rx),
        .rx_ready      (rx_ready),
        .rx_data       (rx_data),
        .rx_valid      (rx_valid),
        .framing_error (framing_error),

        .scan_en       (scan_en),
        .scan_in       (scan_tx_to_rx),
        .scan_out      (scan_rx_to_rx_fifo)
    );

    sync_fifo_scan #(
        .DATA_WIDTH(8),
        .DEPTH     (FIFO_DEPTH)
    ) rx_fifo (
        .clk      (clk),
        .rst      (rst),

        .wr_en    (rx_fifo_wr_en),
        .wr_data  (rx_fifo_wr_data),
        .rd_en    (rx_rd_en),
        .rd_data  (rx_rd_data),
        .full     (rx_fifo_full),
        .empty    (rx_empty),

        .scan_en  (scan_en),
        .scan_in  (scan_rx_to_rx_fifo),
        .scan_out (scan_out)
    );

endmodule