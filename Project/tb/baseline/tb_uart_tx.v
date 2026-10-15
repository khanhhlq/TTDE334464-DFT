`timescale 1ns / 1ps

module tb_uart_tx;

    parameter CLKS_PER_BIT = 16;
    parameter CLK_PERIOD   = 10;

    localparam [7:0] TEST_BYTE = 8'h53;
    localparam BIT_PERIOD = CLKS_PER_BIT * CLK_PERIOD;
    localparam TIMEOUT = 100 * BIT_PERIOD + 20 * CLK_PERIOD;

    reg       clk;
    reg       rst;
    reg [7:0] tx_data;
    reg       tx_valid;

    wire tx_ready;
    wire uart_tx;

    integer errors;

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) uut (
        .clk      (clk),
        .rst      (rst),
        .tx_data  (tx_data),
        .tx_valid (tx_valid),
        .tx_ready (tx_ready),
        .uart_tx  (uart_tx)
    );

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2.0) clk = ~clk;

    task send_byte;
        input [7:0] data;
        begin
            @(negedge clk);
            tx_data  = data;
            tx_valid = 1'b1;

            // Handshake is evaluated at a rising edge.
            @(posedge clk);
            while (tx_ready !== 1'b1)
                @(posedge clk);

            @(negedge clk);
            tx_valid = 1'b0;
        end
    endtask

    task check_byte;
        input [7:0] expected;
        integer i;
        begin
            // Detect start, then sample its center.
            @(negedge uart_tx);
            #(BIT_PERIOD / 2.0);

            if (uart_tx !== 1'b0) begin
                errors = errors + 1;
                $display(
                    "ERROR @ %0t: start bit expected=0 actual=%b",
                    $time, uart_tx
                );
            end

            // UART sends LSB first.
            for (i = 0; i < 8; i = i + 1) begin
                #(BIT_PERIOD);

                if (uart_tx !== expected[i]) begin
                    errors = errors + 1;
                    $display(
                        "ERROR @ %0t: D%0d expected=%b actual=%b",
                        $time, i, expected[i], uart_tx
                    );
                end
            end

            #(BIT_PERIOD);

            if (uart_tx !== 1'b1) begin
                errors = errors + 1;
                $display(
                    "ERROR @ %0t: stop bit expected=1 actual=%b",
                    $time, uart_tx
                );
            end
        end
    endtask

    initial begin
        errors   = 0;
        rst      = 1'b1;
        tx_data  = 8'h00;
        tx_valid = 1'b0;

        repeat (3) @(posedge clk);

        @(negedge clk);
        rst = 1'b0;

        fork
            send_byte(TEST_BYTE);
            check_byte(TEST_BYTE);
        join

        // Allow the stop bit to finish and the FSM to return to IDLE.
        #(BIT_PERIOD);
        @(negedge clk);

        if (tx_ready !== 1'b1) begin
            errors = errors + 1;
            $display("ERROR: tx_ready did not return to 1");
        end

        if (uart_tx !== 1'b1) begin
            errors = errors + 1;
            $display("ERROR: uart_tx is not high after frame");
        end

        if (errors == 0) begin
            $display("PASS: tb_uart_tx - byte 0x%02h", TEST_BYTE);
            $finish;
        end
        else begin
            $fatal(1, "FAIL: tb_uart_tx - %0d errors", errors);
        end
    end

    initial begin
        #(TIMEOUT);
        $fatal(1, "FAIL: tb_uart_tx - simulation timeout");
    end

endmodule