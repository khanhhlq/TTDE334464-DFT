`timescale 1ns / 1ps

module tb_uart_tx_fault_demo;

    // This demo uses the existing 18-bit scan mapping.
    localparam CLKS_PER_BIT = 16;
    localparam SCAN_LENGTH  = 18;

    localparam [SCAN_LENGTH-1:0] LOAD_STATE =
        {1'b0, 2'b01, 4'd5, 3'd0, 8'hA5};

    localparam [SCAN_LENGTH-1:0] EXPECTED_GOOD =
        {1'b0, 2'b01, 4'd6, 3'd0, 8'hA5};

    localparam [SCAN_LENGTH-1:0] EXPECTED_FAULTY =
        {1'b0, 2'b01, 4'd4, 3'd0, 8'hA5};

    // Pattern that does not activate scan_d[12] stuck-at-0.
    localparam [SCAN_LENGTH-1:0] LOAD_INACTIVE =
        {1'b0, 2'b01, 4'd4, 3'd0, 8'hA5};

    localparam [SCAN_LENGTH-1:0] EXPECTED_INACTIVE =
        {1'b0, 2'b01, 4'd5, 3'd0, 8'hA5};
    
    reg clk;
    reg rst;
    reg scan_en;
    reg scan_in;

    reg [7:0] tx_data;
    reg       tx_valid;

    wire tx_ready;
    wire uart_tx;
    wire scan_out;

    reg [SCAN_LENGTH-1:0] good_response;
    reg [SCAN_LENGTH-1:0] faulty_response;
    reg [SCAN_LENGTH-1:0] recovered_response;
    reg [SCAN_LENGTH-1:0] diff_mask;
    
    reg [SCAN_LENGTH-1:0] inactive_good_response;
    reg [SCAN_LENGTH-1:0] inactive_faulty_response;

    integer errors;

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

    task reset_dut;
        begin
            @(negedge clk);
            rst      = 1'b1;
            scan_en  = 1'b0;
            scan_in  = 1'b0;
            tx_valid = 1'b0;
            tx_data  = 8'h00;

            repeat (3) @(posedge clk);

            @(negedge clk);
            rst = 1'b0;
        end
    endtask

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

    // Capture and unload are combined to avoid losing
    // the first response bit between separate tasks.
    task capture_and_unload;
        output [SCAN_LENGTH-1:0] value;
        integer i;
        begin
            value = {SCAN_LENGTH{1'b0}};

            // Enter functional mode.
            @(negedge clk);
            scan_en = 1'b0;
            scan_in = 1'b0;

            // Exactly one functional capture.
            @(posedge clk);
            #1;

            // Each iteration reads before its shift edge.
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

    initial begin
        errors             = 0;
        rst                = 1'b1;
        scan_en            = 1'b0;
        scan_in            = 1'b0;
        tx_data            = 8'h00;
        tx_valid           = 1'b0;
        good_response      = 0;
        faulty_response    = 0;
        recovered_response = 0;
        diff_mask          = 0;
        inactive_good_response   = 0;
        inactive_faulty_response = 0;

        // ------------------------------------------
        // Run 1: fault-free baseline
        // ------------------------------------------
        reset_dut;
        scan_load(LOAD_STATE);
        capture_and_unload(good_response);

        $display("GOOD response     = %05h", good_response);

        if (good_response !== EXPECTED_GOOD) begin
            $fatal(
                1,
                "FAIL: baseline expected=%05h actual=%05h",
                EXPECTED_GOOD, good_response
            );
        end

        $display("PASS: fault-free baseline");
// Establish the fault-free response for the inactive pattern.
reset_dut;
scan_load(LOAD_INACTIVE);
capture_and_unload(inactive_good_response);

$display(
    "INACTIVE GOOD response = %05h",
    inactive_good_response
);

if (inactive_good_response !== EXPECTED_INACTIVE) begin
    $fatal(
        1,
        "FAIL: inactive baseline expected=%05h actual=%05h",
        EXPECTED_INACTIVE,
        inactive_good_response
    );
end

$display("PASS: inactive-pattern baseline");
        // ------------------------------------------
        // Run 2: functional D input stuck-at-0
        // ------------------------------------------
        reset_dut;

        // scan_d[12] maps to clk_count_next[1].
        // Keep the fault active during load,
        // capture and unload.
        force uut.scan_d[12] = 1'b0;

        scan_load(LOAD_STATE);
        capture_and_unload(faulty_response);

        $display("FAULTY response   = %05h", faulty_response);

        // Do not count unknown data as fault detection.
        if ((^faulty_response) === 1'bx) begin
            errors = errors + 1;
            $display("ERROR: faulty response contains X/Z");
        end
        else begin
            diff_mask = good_response ^ faulty_response;

            $display("DIFF mask         = %05h", diff_mask);

            if (faulty_response != good_response) begin
                $display(
                    "DETECTED: scan_d[12] stuck-at-0 via scan_out"
                );
            end
            else begin
                errors = errors + 1;
                $display("ERROR: fault was not detected");
            end

            // Also verify the specifically predicted effect.
            if (faulty_response !== EXPECTED_FAULTY) begin
                errors = errors + 1;

                $display(
                    "ERROR: expected faulty=%05h actual=%05h",
                    EXPECTED_FAULTY, faulty_response
                );
            end
        end

        // ------------------------------------------
        // Run 3: remove fault and verify recovery
        // ------------------------------------------
        
        // The SA0 fault is still active here.
reset_dut;
scan_load(LOAD_INACTIVE);
capture_and_unload(inactive_faulty_response);

$display(
    "INACTIVE FAULTY response = %05h",
    inactive_faulty_response
);

// First reject unknown or otherwise incorrect responses.
if (inactive_faulty_response !== EXPECTED_INACTIVE) begin
    errors = errors + 1;

    $display(
        "ERROR: inactive faulty expected=%05h actual=%05h",
        EXPECTED_INACTIVE,
        inactive_faulty_response
    );
end
else if (inactive_faulty_response !== inactive_good_response) begin
    errors = errors + 1;
    $display("ERROR: inactive pattern unexpectedly changed response");
end
else begin
    $display(
        "PASS: negative control - fault NOT detected, as expected"
    );
end
        release uut.scan_d[12];

        reset_dut;
        scan_load(LOAD_STATE);
        capture_and_unload(recovered_response);

        $display("RECOVERED response = %05h", recovered_response);

        if (recovered_response !== EXPECTED_GOOD) begin
            errors = errors + 1;
            $display("ERROR: incorrect response after fault release");
        end
        else begin
            $display("PASS: recovery after fault release");
        end

        if (errors == 0) begin
            $display("PASS: RTL single-fault injection demo");
            $finish;
        end
        else begin
            $fatal(1, "FAIL: fault demo - %0d errors", errors);
        end
    end

    initial begin
        #100000;
        $fatal(1, "FAIL: fault demo - simulation timeout");
    end

endmodule