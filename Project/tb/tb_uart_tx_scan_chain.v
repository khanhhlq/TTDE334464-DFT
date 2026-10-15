`timescale 1ns / 1ps

module tb_uart_tx_scan_chain;

    localparam CLKS_PER_BIT = 16;

    localparam COUNT_WIDTH =
        (CLKS_PER_BIT > 1) ? $clog2(CLKS_PER_BIT) : 1;

    localparam SCAN_LENGTH =
        8 + 3 + COUNT_WIDTH + 2 + 1;

    reg clk;
    reg rst;
    reg scan_en;
    reg scan_in;

    reg [7:0] tx_data;
    reg       tx_valid;

    wire tx_ready;
    wire uart_tx;
    wire scan_out;

    reg [SCAN_LENGTH-1:0] pattern;
    reg [SCAN_LENGTH-1:0] response;

    integer errors;
    integer tests;
    integer k;

    uart_tx_scan #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) uut (
        .clk      (clk),
        .rst      (rst),
        .tx_data  (tx_data),
        .tx_valid (tx_valid),
        .scan_en  (scan_en),
        .scan_in  (scan_in),
        .tx_ready (tx_ready),
        .uart_tx  (uart_tx),
        .scan_out (scan_out)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Load MSB first.
    task scan_load;
        input [SCAN_LENGTH-1:0] value;
        integer i;
        begin
            for (i = SCAN_LENGTH - 1; i >= 0; i = i - 1) begin
                @(negedge clk);
                scan_en = 1'b1;
                scan_in = value[i];

                @(posedge clk);
                #1;
            end
        end
    endtask

    // Read each outgoing bit BEFORE its shift edge.
    task scan_unload;
        output [SCAN_LENGTH-1:0] value;
        integer i;
        begin
            value = {SCAN_LENGTH{1'b0}};

            for (i = SCAN_LENGTH - 1; i >= 0; i = i - 1) begin
                @(negedge clk);
                scan_en = 1'b1;
                scan_in = 1'b0;

                value[i] = scan_out;

                @(posedge clk);
                #1;
            end
        end
    endtask

    task run_shift_test;
        input [SCAN_LENGTH-1:0] value;
        begin
            tests = tests + 1;

            scan_load(value);

            // Keep scan mode active.
            // No functional capture between load and unload.
            scan_unload(response);

            if (response !== value) begin
                errors = errors + 1;

                $display("FAIL: shift test %0d", tests);
                $display("  expected = %b", value);
                $display("  actual   = %b", response);
            end
            else begin
                $display(
                    "PASS: shift test %0d - pattern=%b response=%b",
                    tests, value, response
                );
            end
        end
    endtask

    task capture_one_cycle;
    begin
        // Switch to functional mode away from the rising edge.
        @(negedge clk);
        scan_en = 1'b0;
        scan_in = 1'b0;

        // Capture exactly one functional update.
        @(posedge clk);
        #1;

        // Return to scan mode before the next rising edge.
        @(negedge clk);
        scan_en = 1'b1;
    end
    endtask


    task run_capture_test;
    input [SCAN_LENGTH-1:0] initial_state;
    input [SCAN_LENGTH-1:0] expected_state;
    begin
        tests = tests + 1;

        scan_load(initial_state);

        capture_one_cycle;

        // Read the first captured bit immediately.
        // We are already at a falling edge here.
        response = {SCAN_LENGTH{1'b0}};
        response[SCAN_LENGTH-1] = scan_out;

        // Shift the first captured bit out.
        @(posedge clk);
        #1;

        // Read and shift out the remaining bits.
        begin : READ_REMAINING_BITS
            integer j;

            for (j = SCAN_LENGTH - 2; j >= 0; j = j - 1) begin
                @(negedge clk);
                response[j] = scan_out;

                @(posedge clk);
                #1;
            end
        end

        if (response !== expected_state) begin
            errors = errors + 1;

            $display("FAIL: capture test %0d", tests);
            $display("  loaded   = %b", initial_state);
            $display("  expected = %b", expected_state);
            $display("  actual   = %b", response);
        end
        else begin
            $display("PASS: capture test %0d", tests);
            $display("  loaded   = %b", initial_state);
            $display("  response = %b", response);
        end
    end
    endtask

    initial begin
        errors   = 0;
        tests    = 0;
        rst      = 1'b1;
        scan_en  = 1'b0;
        scan_in  = 1'b0;
        tx_data  = 8'h00;
        tx_valid = 1'b0;
        pattern  = {SCAN_LENGTH{1'b0}};
        response = {SCAN_LENGTH{1'b0}};

        repeat (3) @(posedge clk);

        @(negedge clk);
        rst = 1'b0;

        $display("SCAN_LENGTH = %0d", SCAN_LENGTH);

        // Test 1: all zeros.
        run_shift_test({SCAN_LENGTH{1'b0}});

        // Test 2: all ones.
        run_shift_test({SCAN_LENGTH{1'b1}});

        // Test 3: alternating bits.
        for (k = 0; k < SCAN_LENGTH; k = k + 1)
            pattern[k] = (k % 2);

        run_shift_test(pattern);

        // Test 4: opposite alternating pattern.
        pattern = ~pattern;
        run_shift_test(pattern);

        // Walking-one tests: exercise each bit position.
        for (k = 0; k < SCAN_LENGTH; k = k + 1) begin
            pattern = {SCAN_LENGTH{1'b0}};
            pattern[k] = 1'b1;
            run_shift_test(pattern);
        end
        
        // Capture tests below assume CLKS_PER_BIT = 16.
tx_valid = 1'b0;
tx_data  = 8'h00;

// Test A: counter increments while remaining in START.
run_capture_test(
    {1'b0, 2'b01, 4'd5,  3'd0, 8'hA5},
    {1'b0, 2'b01, 4'd6,  3'd0, 8'hA5}
);

// Test B: START ends and DATA begins with D0.
run_capture_test(
    {1'b0, 2'b01, 4'd15, 3'd0, 8'hA5},
    {1'b1, 2'b10, 4'd0,  3'd0, 8'hA5}
);

// Test C: final data bit ends and STOP begins.
run_capture_test(
    {1'b0, 2'b10, 4'd15, 3'd7, 8'h53},
    {1'b1, 2'b11, 4'd0,  3'd7, 8'h53}
);

        if (errors == 0) begin
            $display(
                "PASS: UART scan tests - %0d/%0d tests passed",
                tests, tests
            );
            $finish;
        end
        else begin
            $fatal(
                1,
                "FAIL: UART scan chain - %0d failed out of %0d tests",
                errors, tests
            );
        end
    end

    initial begin
        #100000;
        $fatal(1, "FAIL: UART scan chain - simulation timeout");
    end

endmodule