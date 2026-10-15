`timescale 1ns / 1ps

module tb_uart_tx_functional_fault_demo;

    localparam CLKS_PER_BIT = 16;
    localparam OBSERVE_CYCLES = 12 * CLKS_PER_BIT;

    reg clk;
    reg rst;
    reg [7:0] tx_data;
    reg tx_valid;

    wire good_tx;
    wire good_ready;
    wire faulty_tx;
    wire faulty_ready;

    integer cycle_no;
    integer first_detect_cycle;
    integer errors;

    reg fault_detected;

    // Both instances run with scan disabled.
    uart_tx_partial_scan #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) u_good (
        .clk      (clk),
        .rst      (rst),
        .tx_data  (tx_data),
        .tx_valid (tx_valid),
        .scan_en  (1'b0),
        .scan_in  (1'b0),
        .tx_ready (good_ready),
        .uart_tx  (good_tx),
        .scan_out ()
    );

    uart_tx_partial_scan #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) u_faulty (
        .clk      (clk),
        .rst      (rst),
        .tx_data  (tx_data),
        .tx_valid (tx_valid),
        .scan_en  (1'b0),
        .scan_in  (1'b0),
        .tx_ready (faulty_ready),
        .uart_tx  (faulty_tx),
        .scan_out ()
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        rst                = 1'b1;
        tx_data            = 8'h00;
        tx_valid           = 1'b0;
        errors             = 0;
        fault_detected     = 1'b0;
        first_detect_cycle = -1;

        repeat (3) @(posedge clk);
        #1;

        if ((good_tx      !== 1'b1) ||
            (faulty_tx    !== 1'b1) ||
            (good_ready   !== 1'b1) ||
            (faulty_ready !== 1'b1)) begin

            $fatal(1, "FAIL: incorrect reset baseline");
        end

        @(negedge clk);
        rst = 1'b0;

        // Same fault site as F0 in the previous campaign.
        force u_faulty.scan_d[11] = 1'b0;

        // Request one byte through the functional interface.
        @(negedge clk);
        tx_data  = 8'hFF;
        tx_valid = 1'b1;

        // Both DUTs must accept this byte at this edge.
        @(posedge clk);

        if ((good_ready !== 1'b1) ||
            (faulty_ready !== 1'b1)) begin

            $fatal(1, "FAIL: DUT not ready at initial handshake");
        end

        #1;

        if ((good_tx !== 1'b0) ||
            (faulty_tx !== 1'b0)) begin

            $fatal(1, "FAIL: start bit did not begin");
        end

        @(negedge clk);
        tx_valid = 1'b0;

        // cycle_no = number of rising edges after acceptance.
        for (cycle_no = 1;
             cycle_no <= OBSERVE_CYCLES;
             cycle_no = cycle_no + 1) begin

            @(posedge clk);
            #1;

            // Reject unknown values as invalid test results.
            if ((^{good_tx, good_ready,
                   faulty_tx, faulty_ready}) === 1'bx) begin

                errors = errors + 1;
                $display(
                    "ERROR: X/Z at observation cycle %0d",
                    cycle_no
                );
            end
            else if ((good_tx != faulty_tx) ||
                     (good_ready != faulty_ready)) begin

                if (!fault_detected) begin
                    fault_detected = 1'b1;
                    first_detect_cycle = cycle_no;

                    $display(
                        "DETECTED: functional outputs differ at cycle %0d",
                        cycle_no
                    );

                    $display(
                        "  TX: good=%b faulty=%b",
                        good_tx, faulty_tx
                    );

                    $display(
                        "  READY: good=%b faulty=%b",
                        good_ready, faulty_ready
                    );
                end
            end
        end

        if (!fault_detected) begin
            errors = errors + 1;
            $display("ERROR: fault not detected within test budget");
        end

        // The healthy UART should have completed its frame.
        if ((good_tx !== 1'b1) || (good_ready !== 1'b1)) begin
            errors = errors + 1;
            $display("ERROR: healthy UART did not return to IDLE");
        end

        // Predicted effect of this specific counter fault.
        if ((faulty_tx !== 1'b0) || (faulty_ready !== 1'b0)) begin
            errors = errors + 1;
            $display("ERROR: unexpected faulty UART behavior");
        end

        release u_faulty.scan_d[11];

        // Reset both DUTs after removing the fault.
        @(negedge clk);
        rst = 1'b1;

        repeat (3) @(posedge clk);
        #1;

        if ({good_tx, good_ready, faulty_tx, faulty_ready}
            !== 4'b1111) begin

            errors = errors + 1;
            $display("ERROR: reset after fault release failed");
        end

        $display("Observation budget = %0d cycles", OBSERVE_CYCLES);
        $display("First detection cycle = %0d", first_detect_cycle);
        $display("Errors = %0d", errors);

        if (errors == 0) begin
            $display("PASS: functional-only fault detection demo");
            $finish;
        end
        else begin
            $fatal(1, "FAIL: functional-only fault detection demo");
        end
    end

    initial begin
        #100000;
        $fatal(1, "FAIL: simulation timeout");
    end

endmodule