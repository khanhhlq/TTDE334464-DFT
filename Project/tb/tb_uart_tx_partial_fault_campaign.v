`timescale 1ns / 1ps

module tb_uart_tx_partial_fault_campaign;

    localparam SCAN_LENGTH = 6;
    localparam NUM_FAULTS  = 8;
    localparam NUM_PATTERNS = 2;

    reg clk;
    reg rst;
    reg scan_en;
    reg scan_in;

    wire tx_ready;
    wire uart_tx;
    wire scan_out;

    reg [SCAN_LENGTH-1:0] patterns [0:NUM_PATTERNS-1];
    reg [SCAN_LENGTH-1:0] expected [0:NUM_PATTERNS-1];
    reg [SCAN_LENGTH-1:0] golden   [0:NUM_PATTERNS-1];

    reg [SCAN_LENGTH-1:0] response;

    // Bit f is 1 when pattern p detects fault f.
    reg [NUM_FAULTS-1:0] detection [0:NUM_PATTERNS-1];
    reg [NUM_FAULTS-1:0] detected_union;

    integer p;
    integer f;
    integer errors;
    integer count_p0;
    integer count_p1;
    integer count_union;

    uart_tx_partial_scan #(
        .CLKS_PER_BIT(16)
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

    task capture_and_unload;
        output [SCAN_LENGTH-1:0] value;
        integer i;
        begin
            value = 0;

            @(negedge clk);
            scan_en = 1'b0;
            scan_in = 1'b0;

            @(posedge clk);
            #1;

            for (i = SCAN_LENGTH-1; i >= 0; i = i-1) begin
                @(negedge clk);
                scan_en = 1'b1;
                scan_in = 1'b0;

                // Read before the rising edge shifts this bit out.
                value[i] = scan_out;

                @(posedge clk);
                #1;
            end
        end
    endtask

    task inject_fault;
        input integer fault_id;
        begin
            // Constant bit indices keep force targets explicit.
            case (fault_id)
                0: force uut.scan_d[11] = 1'b0;
                1: force uut.scan_d[11] = 1'b1;
                2: force uut.scan_d[12] = 1'b0;
                3: force uut.scan_d[12] = 1'b1;
                4: force uut.scan_d[13] = 1'b0;
                5: force uut.scan_d[13] = 1'b1;
                6: force uut.scan_d[14] = 1'b0;
                7: force uut.scan_d[14] = 1'b1;
                default: $fatal(1, "Invalid fault ID");
            endcase
        end
    endtask

    task remove_fault;
        input integer fault_id;
        begin
            case (fault_id)
                0, 1: release uut.scan_d[11];
                2, 3: release uut.scan_d[12];
                4, 5: release uut.scan_d[13];
                6, 7: release uut.scan_d[14];
                default: $fatal(1, "Invalid fault ID");
            endcase
        end
    endtask

    initial begin
        rst            = 1'b1;
        scan_en        = 1'b0;
        scan_in        = 1'b0;
        response       = 0;
        errors         = 0;
        detected_union = 0;
        count_p0       = 0;
        count_p1       = 0;
        count_union    = 0;

        detection[0] = 0;
        detection[1] = 0;

        // Partial scan vector: {state[1:0], clk_count[3:0]}

// P0: START, counter 5 -> START, counter 6.
patterns[0] = {2'b01, 4'd5};
expected[0] = {2'b01, 4'd6};

// P1: START, counter 8 -> START, counter 9.
patterns[1] = {2'b01, 4'd8};
expected[1] = {2'b01, 4'd9};

        // 1. Establish and validate fault-free responses.
        for (p = 0; p < NUM_PATTERNS; p = p+1) begin
            reset_dut;
            scan_load(patterns[p]);
            capture_and_unload(response);

            if (response !== expected[p]) begin
                $fatal(
                    1,
                    "Baseline P%0d failed: expected=%05h actual=%05h",
                    p, expected[p], response
                );
            end

            golden[p] = response;

            $display(
                "PASS: baseline P%0d response=%05h",
                p, golden[p]
            );
        end

        // 2. Simulate one fault and one pattern per trial.
        for (p = 0; p < NUM_PATTERNS; p = p+1) begin
            for (f = 0; f < NUM_FAULTS; f = f+1) begin
                reset_dut;
                inject_fault(f);

                scan_load(patterns[p]);
                capture_and_unload(response);

                if ((^response) === 1'bx) begin
                    errors = errors + 1;

                    $display(
                        "ERROR: P%0d F%0d response contains X/Z",
                        p, f
                    );
                end
                else if (response != golden[p]) begin
                    detection[p][f] = 1'b1;

                    $display(
                        "DETECTED: P%0d F%0d good=%05h faulty=%05h",
                        p, f, golden[p], response
                    );
                end
                else begin
                    $display(
                        "NOT_DETECTED: P%0d F%0d response=%05h",
                        p, f, response
                    );
                end

                // Never let one fault leak into the next trial.
                remove_fault(f);
            end
        end

        // 3. Count unique faults detected by the pattern set.
        detected_union = detection[0] | detection[1];

        $display("Fault_ID  scan_d_bit  SA_value  P0  P1  Union");

        for (f = 0; f < NUM_FAULTS; f = f+1) begin
            $display(
                "%0d         %0d          %0d         %b   %b   %b",
                f, 11 + f/2, f%2,
                detection[0][f],
                detection[1][f],
                detected_union[f]
            );

            if (detection[0][f])
                count_p0 = count_p0 + 1;

            if (detection[1][f])
                count_p1 = count_p1 + 1;

            if (detected_union[f])
                count_union = count_union + 1;
        end

        $display("P0 detected = %0d/8", count_p0);
        $display("P1 detected = %0d/8", count_p1);
        $display("Union detected = %0d/8", count_union);

        $display(
            "Selected RTL fault coverage = %0.2f%%",
            100.0 * count_union / NUM_FAULTS
        );

        // Check the predicted detection matrix, not just totals.
        // Vector order is F7 ... F0.
        if ((detection[0] !== 8'b10010110) ||
            (detection[1] !== 8'b01101001)) begin
            errors = errors + 1;
            $display("ERROR: unexpected detection matrix");
        end

        // 4. Confirm clean operation after all faults are removed.
        for (p = 0; p < NUM_PATTERNS; p = p+1) begin
            reset_dut;
            scan_load(patterns[p]);
            capture_and_unload(response);

            if (response !== golden[p]) begin
                errors = errors + 1;
                $display("ERROR: recovery failed for P%0d", p);
            end
        end

        if (errors == 0) begin
    $display("PASS: partial-scan selected RTL fault campaign");
            $finish;
        end
        else begin
            $fatal(1, "FAIL: campaign - %0d errors", errors);
        end
    end

    initial begin
        #100000;
        $fatal(1, "FAIL: campaign timeout");
    end

endmodule