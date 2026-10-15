`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/21/2026 03:03:00 PM
// Design Name: 
// Module Name: tb_uart_rx
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


module tb_uart_rx;

    parameter CLKS_PER_BIT = 16;
    parameter CLK_PERIOD   = 10;

    localparam [7:0] TEST_BYTE = 8'h53;
    localparam BIT_PERIOD = CLKS_PER_BIT * CLK_PERIOD;
    localparam TIMEOUT = 100 * BIT_PERIOD + 20 * CLK_PERIOD;

    reg clk;
    reg rst;
    reg uart_rx;
    reg rx_ready;

    wire [7:0] rx_data;
    wire       rx_valid;
    wire       framing_error;

    integer errors;

    uart_rx #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) uut (
        .clk           (clk),
        .rst           (rst),
        .uart_rx       (uart_rx),
        .rx_ready      (rx_ready),
        .rx_data       (rx_data),
        .rx_valid      (rx_valid),
        .framing_error (framing_error)
    );

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2.0) clk = ~clk;

    // Phat mot frame UART 8N1 vao chan uart_rx.
    task send_byte;
        input [7:0] data;
        integer i;
        begin
            @(negedge clk);

            // Start bit.
            uart_rx = 1'b0;
            #(BIT_PERIOD);

            // 8 bit du lieu, LSB truoc.
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = data[i];
                #(BIT_PERIOD);
            end

            // Stop bit.
            uart_rx = 1'b1;
            #(BIT_PERIOD);
        end
    endtask

    task check_byte;
        input [7:0] expected;
        integer i;
        begin
            // Kiem tra tai canh xuong de tranh thoi diem
            // DUT cap nhat thanh ghi o canh len.
            @(negedge clk);
            while (rx_valid !== 1'b1)
                @(negedge clk);

            if (rx_data !== expected) begin
                errors = errors + 1;
                $display(
                    "ERROR @ %0t: data expected=0x%02h actual=0x%02h",
                    $time, expected, rx_data
                );
            end

            // rx_ready van bang 0:
            // RX phai giu rx_valid va rx_data.
            for (i = 0; i < 5; i = i + 1) begin
                @(negedge clk);

                if (rx_valid !== 1'b1) begin
                    errors = errors + 1;
                    $display(
                        "ERROR @ %0t: rx_valid dropped before handshake",
                        $time
                    );
                end

                if (rx_data !== expected) begin
                    errors = errors + 1;
                    $display(
                        "ERROR @ %0t: rx_data changed while waiting",
                        $time
                    );
                end
            end

            // Cho phep nhan byte.
            // Handshake xay ra tai canh len ke tiep.
            rx_ready = 1'b1;

            @(posedge clk);
            @(negedge clk);

            if (rx_valid !== 1'b0) begin
                errors = errors + 1;
                $display(
                    "ERROR @ %0t: rx_valid did not clear after handshake",
                    $time
                );
            end

            rx_ready = 1'b0;
        end
    endtask

    // Theo doi loi khung trong toan bo bai test.
    // Frame dang phat hop le nen khong duoc bao loi.
    always @(negedge clk) begin
        if (!rst && framing_error !== 1'b0) begin
            errors = errors + 1;
            $display(
                "ERROR @ %0t: unexpected framing_error=%b",
                $time, framing_error
            );
        end
    end

    initial begin
        errors   = 0;
        rst      = 1'b1;
        uart_rx  = 1'b1;
        rx_ready = 1'b0;

        repeat (3) @(posedge clk);
        @(negedge clk);

        // Kiem tra dau ra sau reset.
        if (rx_valid !== 1'b0 ||
            rx_data !== 8'h00 ||
            framing_error !== 1'b0) begin
            errors = errors + 1;
            $display("ERROR: incorrect outputs after reset");
        end

        rst = 1'b0;

        // Giu duong truyen o muc nghi truoc khi phat.
        repeat (3) @(negedge clk);

        fork
            send_byte(TEST_BYTE);
            check_byte(TEST_BYTE);
        join

        // Doi them de kiem tra RX khong bao byte moi.
        #(BIT_PERIOD);
        @(negedge clk);

        if (rx_valid !== 1'b0) begin
            errors = errors + 1;
            $display("ERROR: unexpected rx_valid after frame");
        end

        if (errors == 0) begin
            $display("PASS: tb_uart_rx - byte 0x%02h", TEST_BYTE);
            $finish;
        end
        else begin
            $fatal(1, "FAIL: tb_uart_rx - %0d errors", errors);
        end
    end

    initial begin
        #(TIMEOUT);
        $fatal(1, "FAIL: tb_uart_rx - simulation timeout");
    end

endmodule