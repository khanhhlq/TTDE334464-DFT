`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/21/2026 06:52:05 PM
// Design Name: 
// Module Name: tb_uart_top
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

module tb_uart_top;

    parameter CLKS_PER_BIT = 16;
    parameter FIFO_DEPTH   = 16;
    parameter CLK_PERIOD   = 10;

    localparam NUM_BYTES    = 8;
    localparam BIT_PERIOD   = CLKS_PER_BIT * CLK_PERIOD;
    localparam FRAME_PERIOD = 10 * BIT_PERIOD;
    localparam TIMEOUT      = (NUM_BYTES + 10) * FRAME_PERIOD;

    reg       clk;
    reg       rst;

    reg       tx_wr_en;
    reg [7:0] tx_wr_data;
    wire      tx_full;

    reg       rx_rd_en;
    wire [7:0] rx_rd_data;
    wire      rx_empty;

    wire      framing_error;

    // Loopback: TX va RX noi chung mot day serial.
    wire serial_line;

    reg [7:0] test_data [0:NUM_BYTES-1];

    integer errors;
    integer i;

    uart_top #(
        .CLKS_PER_BIT(CLKS_PER_BIT),
        .FIFO_DEPTH  (FIFO_DEPTH)
    ) uut (
        .clk           (clk),
        .rst           (rst),
        .uart_rx       (serial_line),
        .uart_tx       (serial_line),
        .tx_wr_en      (tx_wr_en),
        .tx_wr_data    (tx_wr_data),
        .tx_full       (tx_full),
        .rx_rd_en      (rx_rd_en),
        .rx_rd_data    (rx_rd_data),
        .rx_empty      (rx_empty),
        .framing_error (framing_error)
    );

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2.0) clk = ~clk;

    task write_byte;
        input [7:0] data;
        begin
            @(negedge clk);

            while (tx_full !== 1'b0)
                @(negedge clk);

            tx_wr_data = data;
            tx_wr_en   = 1'b1;

            @(posedge clk);

            @(negedge clk);
            tx_wr_en = 1'b0;

            $display(
                "WRITE @ %0t: TX FIFO <- 0x%02h",
                $time, data
            );
        end
    endtask

    task read_check_byte;
        input [7:0] expected;
        reg   [7:0] actual;
        begin
            @(negedge clk);

            while (rx_empty !== 1'b0)
                @(negedge clk);

            actual = rx_rd_data;

            if (actual !== expected) begin
                errors = errors + 1;

                $display(
                    "ERROR @ %0t: expected=0x%02h actual=0x%02h",
                    $time, expected, actual
                );
            end
            else begin
                $display(
                    "READ  @ %0t: RX FIFO -> 0x%02h OK",
                    $time, actual
                );
            end

            rx_rd_en = 1'b1;

            @(posedge clk);

            @(negedge clk);
            rx_rd_en = 1'b0;
        end
    endtask

    always @(negedge clk) begin
        if (!rst && framing_error !== 1'b0) begin
            errors = errors + 1;

            $display(
                "ERROR @ %0t: framing_error=%b",
                $time, framing_error
            );
        end
    end

    initial begin
        errors     = 0;
        rst        = 1'b1;
        tx_wr_en   = 1'b0;
        tx_wr_data = 8'h00;
        rx_rd_en   = 1'b0;

        test_data[0] = 8'h53;
        test_data[1] = 8'hA5;
        test_data[2] = 8'h00;
        test_data[3] = 8'hFF;
        test_data[4] = 8'h55;
        test_data[5] = 8'hAA;
        test_data[6] = 8'h12;
        test_data[7] = 8'h34;

        if (FIFO_DEPTH < NUM_BYTES)
            $fatal(1, "FIFO_DEPTH must be >= NUM_BYTES");

        $display("TEST 1: Reset");

        repeat (4) @(posedge clk);
        @(negedge clk);

        if (tx_full !== 1'b0) begin
            errors = errors + 1;
            $display("ERROR: TX FIFO full after reset");
        end

        if (rx_empty !== 1'b1) begin
            errors = errors + 1;
            $display("ERROR: RX FIFO not empty after reset");
        end

        if (serial_line !== 1'b1) begin
            errors = errors + 1;
            $display("ERROR: UART TX not idle-high after reset");
        end

        if (framing_error !== 1'b0) begin
            errors = errors + 1;
            $display("ERROR: framing_error after reset");
        end

        rst = 1'b0;

        $display("TEST 2: Write bytes to TX FIFO");

        for (i = 0; i < NUM_BYTES; i = i + 1)
            write_byte(test_data[i]);

        $display("TEST 3: Wait for loopback reception");

        #((NUM_BYTES + 1) * (FRAME_PERIOD + CLK_PERIOD));
        @(negedge clk);

        if (rx_empty !== 1'b0) begin
            errors = errors + 1;
            $display("ERROR: RX FIFO has no data after transmission");
        end

        $display("TEST 4: Read and compare bytes");

        for (i = 0; i < NUM_BYTES; i = i + 1)
            read_check_byte(test_data[i]);

        $display("TEST 5: Check final state");

        #(FRAME_PERIOD);
        @(negedge clk);

        if (rx_empty !== 1'b1) begin
            errors = errors + 1;
            $display("ERROR: RX FIFO contains unexpected extra data");
        end

        if (serial_line !== 1'b1) begin
            errors = errors + 1;
            $display("ERROR: UART TX not idle-high after transmission");
        end

        if (tx_full !== 1'b0) begin
            errors = errors + 1;
            $display("ERROR: TX FIFO still full after transmission");
        end

        if (errors == 0) begin
            $display(
                "PASS: tb_uart_top - %0d bytes received correctly",
                NUM_BYTES
            );
            $finish;
        end
        else begin
            $fatal(1, "FAIL: tb_uart_top - %0d errors", errors);
        end
    end

    initial begin
        #(TIMEOUT);
        $fatal(1, "FAIL: tb_uart_top - simulation timeout");
    end

endmodule
