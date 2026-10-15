`timescale 1ns / 1ps

module tb_uart_tx_functional_fault_campaign;

    localparam CLKS_PER_BIT   = 16;
    localparam OBSERVE_CYCLES = 12 * CLKS_PER_BIT;
    localparam NUM_FAULTS     = 8;

    reg       clk;
    reg       rst;
    reg [7:0] tx_data;
    reg       tx_valid;

    wire good_tx;
    wire good_ready;
    wire faulty_tx;
    wire faulty_ready;

    reg [NUM_FAULTS-1:0] detected;

    integer first_cycle    [0:NUM_FAULTS-1];
    integer expected_cycle [0:NUM_FAULTS-1];

    integer f;
    integer cycle_no;
    integer errors;
    integer detected_count;

    // Fault-free reference, scan disabled.
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

    // Faulty DUT, scan disabled.
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

    task inject_fault;
        input integer fault_id;
        begin
            case (fault_id)
                0: force u_faulty.scan_d[11] = 1'b0;
                1: force u_faulty.scan_d[11] = 1'b1;
                2: force u_faulty.scan_d[12] = 1'b0;
                3: force u_faulty.scan_d[12] = 1'b1;
                4: force u_faulty.scan_d[13] = 1'b0;
                5: force u_faulty.scan_d[13] = 1'b1;
                6: force u_faulty.scan_d[14] = 1'b0;
                7: force u_faulty.scan_d[14] = 1'b1;
                default: $fatal(1, "Invalid fault ID");
            endcase
        end
    endtask

    task remove_fault;
        input integer fault_id;
        begin
            case (fault_id)
                0, 1: release u_faulty.scan_d[11];
                2, 3: release u_faulty.scan_d[12];
                4, 5: release u_faulty.scan_d[13];
                6, 7: release u_faulty.scan_d[14];
                default: $fatal(1, "Invalid fault ID");
            endcase
        end
    endtask

    initial begin
        rst            = 1'b1;
        tx_data        = 8'h00;
        tx_valid       = 1'b0;
        errors         = 0;
        detected       = 0;
        detected_count = 0;

        // Expected first detection cycles for:
        // CLKS_PER_BIT=16, byte=FF,
        // fault active before byte acceptance.
        //
        // SA0: faulty UART remains in START.
        // SA1: counter skips values on every update.
        expected_cycle[0] = 16;
        expected_cycle[1] = 8;
        expected_cycle[2] = 16;
        expected_cycle[3] = 8;
        expected_cycle[4] = 16;
        expected_cycle[5] = 8;
        expected_cycle[6] = 16;
        expected_cycle[7] = 8;

        $display(
            "BUILD: FUNCTIONAL_FAULT_CAMPAIGN_V3_EXPECTED_FIXED"
        );
        $display("Scan disabled; observe only TX and READY.");

        for (f = 0; f < NUM_FAULTS; f = f + 1) begin
            first_cycle[f] = -1;

            // Reset both DUTs before each fault trial.
            @(negedge clk);
            rst      = 1'b1;
            tx_data  = 8'h00;
            tx_valid = 1'b0;

            repeat (3) @(posedge clk);
            #1;

            if ({good_tx, good_ready, faulty_tx, faulty_ready}
                !== 4'b1111) begin

                $fatal(
                    1,
                    "FAIL: reset baseline for F%0d",
                    f
                );
            end

            // Inject one fault after releasing reset.
            @(negedge clk);
            rst = 1'b0;
            inject_fault(f);

            // Apply the same byte to both DUTs.
            @(negedge clk);
            tx_data  = 8'hFF;
            tx_valid = 1'b1;

            // Check ready before the nonblocking state update.
            @(posedge clk);

            if ((good_ready !== 1'b1) ||
                (faulty_ready !== 1'b1)) begin

                $fatal(
                    1,
                    "FAIL: initial handshake for F%0d",
                    f
                );
            end

            #1;

            if ((good_tx !== 1'b0) ||
                (faulty_tx !== 1'b0)) begin

                $fatal(
                    1,
                    "FAIL: initial start bit for F%0d",
                    f
                );
            end

            @(negedge clk);
            tx_valid = 1'b0;

            // Observe outputs for the full test budget.
            for (cycle_no = 1;
                 cycle_no <= OBSERVE_CYCLES;
                 cycle_no = cycle_no + 1) begin

                @(posedge clk);
                #1;

                // X/Z is a test error, not valid fault detection.
                if ((^{good_tx, good_ready,
                       faulty_tx, faulty_ready}) === 1'bx) begin

                    errors = errors + 1;

                    $display(
                        "ERROR: F%0d X/Z at cycle %0d",
                        f, cycle_no
                    );
                end
                else if ((good_tx != faulty_tx) ||
                         (good_ready != faulty_ready)) begin

                    if (!detected[f]) begin
                        detected[f] = 1'b1;
                        first_cycle[f] = cycle_no;

                        $display(
                            "DETECTED: F%0d first_cycle=%0d",
                            f, cycle_no
                        );

                        $display(
                            "  TX good=%b faulty=%b READY good=%b faulty=%b",
                            good_tx, faulty_tx,
                            good_ready, faulty_ready
                        );
                    end
                end
            end

            // Healthy UART must finish the frame.
            if ((good_tx !== 1'b1) ||
                (good_ready !== 1'b1)) begin

                errors = errors + 1;

                $display(
                    "ERROR: healthy UART did not finish for F%0d",
                    f
                );
            end

            if (!detected[f]) begin
                $display(
                    "NOT_DETECTED: F%0d within %0d cycles",
                    f, OBSERVE_CYCLES
                );
            end

            // Print the actual expected value used in this run.
            $display(
                "CHECK: F%0d expected=%0d actual=%0d errors_before_check=%0d",
                f, expected_cycle[f], first_cycle[f], errors
            );

            if (first_cycle[f] != expected_cycle[f]) begin
                errors = errors + 1;

                $display(
                    "ERROR: F%0d expected first_cycle=%0d actual=%0d",
                    f, expected_cycle[f], first_cycle[f]
                );
            end

            // Remove this fault before the next trial.
            remove_fault(f);
        end

        // Confirm reset recovery after all faults are removed.
        @(negedge clk);
        rst      = 1'b1;
        tx_valid = 1'b0;

        repeat (3) @(posedge clk);
        #1;

        if ({good_tx, good_ready, faulty_tx, faulty_ready}
            !== 4'b1111) begin

            errors = errors + 1;
            $display("ERROR: final reset recovery");
        end

        $display(
            "Fault_ID  scan_d_bit  SA_value  Detected  First_cycle"
        );

        for (f = 0; f < NUM_FAULTS; f = f + 1) begin
            $display(
                "%0d         %0d          %0d         %b         %0d",
                f,
                11 + f/2,
                f%2,
                detected[f],
                first_cycle[f]
            );

            if (detected[f])
                detected_count = detected_count + 1;
        end

        $display("Functional byte = FF");

        $display(
            "Observation budget per trial = %0d cycles",
            OBSERVE_CYCLES
        );

        $display("Detected = %0d/8", detected_count);

        $display(
            "Selected RTL fault coverage = %0.2f%%",
            100.0 * detected_count / NUM_FAULTS
        );

        $display("Errors = %0d", errors);

        if (errors == 0) begin
            $display(
                "PASS: functional-only selected RTL fault campaign"
            );
            $finish;
        end
        else begin
            $fatal(1, "FAIL: functional-only fault campaign");
        end
    end

    initial begin
        #100000;
        $fatal(1, "FAIL: functional-only campaign timeout");
    end

endmodule