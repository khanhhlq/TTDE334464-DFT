`timescale 1ns / 1ps

module tb_uart_tx_partial_scan_chain;

    // This test uses a 4-bit counter and a 2-bit state.
    localparam CLKS_PER_BIT = 16;
    localparam SCAN_LENGTH  = 6;

    reg clk;
    reg rst;
    reg scan_en;
    reg scan_in;

    wire tx_ready;
    wire uart_tx;
    wire scan_out;

    reg [SCAN_LENGTH-1:0] response;

    integer errors;
    integer shift_tests;
    integer capture_tests;
    integer k;

    uart_tx_partial_scan #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) uut (
        .clk      (clk),
        .rst      (rst),
        .tx_data  (8'h00),
        .tx_valid (1'b0),
        .scan_en  (scan_en),
        .scan_in  (scan_in),
        .tx_ready (tx_ready),
        .uart_tx  (uart_tx),
        .scan_out (scan_out)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task reset_dut;
        begin
            @(negedge clk);
            rst     = 1'b1;
            scan_en = 1'b0;
            scan_in = 1'b0;

            repeat (3) @(posedge clk);

            @(negedge clk);
            rst = 1'b0;
        end
    endtask

    task scan_load;
        input [SCAN_LENGTH-1:0] value;
        integer i;
        begin
            for (i = SCAN_LENGTH-1; i >= 0; i = i-1) begin
                @(negedge clk);
                scan_en = 1'b1;
                scan_in = value[i];

                @(posedge clk);
                #1;
            end
        end
    endtask

    // Called after scan_load, which returns just after a posedge.
    task scan_unload;
        output [SCAN_LENGTH-1:0] value;
        integer i;
        begin
            value = 0;

            for (i = SCAN_LENGTH-1; i >= 0; i = i-1) begin
                @(negedge clk);
                scan_en = 1'b1;
                scan_in = 1'b0;

                // Read the outgoing bit before the shift edge.
                value[i] = scan_out;

                @(posedge clk);
                #1;
            end
        end
    endtask

    task run_shift_test;
        input [SCAN_LENGTH-1:0] value;
        begin
            shift_tests = shift_tests + 1;

            scan_load(value);
            scan_unload(response);

            if (response !== value) begin
                errors = errors + 1;

                $display(
                    "FAIL: shift %0d expected=%b actual=%b",
                    shift_tests, value, response
                );
            end
            else begin
                $display(
                    "PASS: shift %0d pattern=%b response=%b",
                    shift_tests, value, response
                );
            end
        end
    endtask

    task run_capture_test;
        input [SCAN_LENGTH-1:0] initial_state;
        input [SCAN_LENGTH-1:0] expected_state;
        begin
            capture_tests = capture_tests + 1;

            reset_dut;
            scan_load(initial_state);

            // Enter functional mode for one rising edge.
            @(negedge clk);
            scan_en = 1'b0;
            scan_in = 1'b0;

            @(posedge clk);
            #1;

            // This task switches back to scan at the next
            // negedge and reads the first bit before shifting.
            scan_unload(response);

            if (response !== expected_state) begin
                errors = errors + 1;

                $display("FAIL: capture %0d", capture_tests);
                $display("  loaded   = %b", initial_state);
                $display("  expected = %b", expected_state);
                $display("  actual   = %b", response);
            end
            else begin
                $display(
                    "PASS: capture %0d loaded=%b response=%b",
                    capture_tests, initial_state, response
                );
            end
        end
    endtask

    initial begin
        rst           = 1'b1;
        scan_en       = 1'b0;
        scan_in       = 1'b0;
        response      = 0;
        errors        = 0;
        shift_tests   = 0;
        capture_tests = 0;

        reset_dut;

        $display("PARTIAL SCAN_LENGTH = %0d", SCAN_LENGTH);

        // Exhaust all 64 values of the six scanned bits.
        // No functional capture between load and unload.
        for (k = 0; k < 64; k = k+1)
            run_shift_test(k[5:0]);

        // Packed vector: {state[1:0], clk_count[3:0]}.

        // START, counter 5 -> START, counter 6.
        run_capture_test(
            {2'b01, 4'd5},
            {2'b01, 4'd6}
        );

        // START, counter 15 -> DATA, counter 0.
        run_capture_test(
            {2'b01, 4'd15},
            {2'b10, 4'd0}
        );

        $display("Shift tests   = %0d", shift_tests);
        $display("Capture tests = %0d", capture_tests);
        $display("Errors        = %0d", errors);

        if (errors == 0) begin
            $display("PASS: partial-scan chain and capture tests");
            $finish;
        end
        else begin
            $fatal(1, "FAIL: partial-scan tests");
        end
    end

    initial begin
        #100000;
        $fatal(1, "FAIL: partial-scan simulation timeout");
    end

endmodule