`timescale 1ns / 1ps

module tb_uart_tx_full_fault_campaign36;

    localparam CLKS_PER_BIT = 16;
    localparam CLK_PERIOD   = 10;
    localparam SCAN_LENGTH  = 18;
    localparam NUM_FAULTS   = 36;
    localparam NUM_PATTERNS = 4;

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

    reg [NUM_FAULTS-1:0] detection [0:NUM_PATTERNS-1];
    reg [NUM_FAULTS-1:0] detected_union;

    integer p;
    integer f;
    integer errors;
    integer count_pattern;
    integer count_union;

    // Bo dem chu ky.
    integer clock_cycles;
    integer trial_start;
    integer reset_end;
    integer load_end;

    integer reset_cycles;
    integer wait_cycles;
    integer total_cycles;
    integer pattern_set_cycles;

    uart_tx_scan #(
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

    initial begin
        clk          = 1'b0;
        clock_cycles = 0;
    end

    always #(CLK_PERIOD / 2) clk = ~clk;

    always @(posedge clk)
        clock_cycles = clock_cycles + 1;

    task reset_dut;
        begin
            @(negedge clk);
            rst     = 1'b1;
            scan_en = 1'b0;
            scan_in = 1'b0;

            // Bat dau do khi da dat tin hieu reset.
            trial_start = clock_cycles;

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

    task capture_and_unload;
        output [SCAN_LENGTH-1:0] value;
        integer i;
        begin
            value = 0;

            // Capture: mot chu ky chuc nang.
            @(negedge clk);
            scan_en = 1'b0;
            scan_in = 1'b0;

            @(posedge clk);
            #1;

            // Unload: doc truoc canh clock dich.
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

    /*
     * F(2*k)   : scan_d[k] stuck-at-0.
     * F(2*k+1) : scan_d[k] stuck-at-1.
     *
     * scan_d[7:0]   : data_next.
     * scan_d[10:8]  : bit_index_next.
     * scan_d[14:11] : clk_count_next.
     * scan_d[16:15] : state_next.
     * scan_d[17]    : uart_tx_next.
     */
    task inject_fault;
        input integer fault_id;
        begin
            case (fault_id)
                 0: force uut.scan_d[0]  = 1'b0;
                 1: force uut.scan_d[0]  = 1'b1;
                 2: force uut.scan_d[1]  = 1'b0;
                 3: force uut.scan_d[1]  = 1'b1;
                 4: force uut.scan_d[2]  = 1'b0;
                 5: force uut.scan_d[2]  = 1'b1;
                 6: force uut.scan_d[3]  = 1'b0;
                 7: force uut.scan_d[3]  = 1'b1;
                 8: force uut.scan_d[4]  = 1'b0;
                 9: force uut.scan_d[4]  = 1'b1;
                10: force uut.scan_d[5]  = 1'b0;
                11: force uut.scan_d[5]  = 1'b1;
                12: force uut.scan_d[6]  = 1'b0;
                13: force uut.scan_d[6]  = 1'b1;
                14: force uut.scan_d[7]  = 1'b0;
                15: force uut.scan_d[7]  = 1'b1;
                16: force uut.scan_d[8]  = 1'b0;
                17: force uut.scan_d[8]  = 1'b1;
                18: force uut.scan_d[9]  = 1'b0;
                19: force uut.scan_d[9]  = 1'b1;
                20: force uut.scan_d[10] = 1'b0;
                21: force uut.scan_d[10] = 1'b1;
                22: force uut.scan_d[11] = 1'b0;
                23: force uut.scan_d[11] = 1'b1;
                24: force uut.scan_d[12] = 1'b0;
                25: force uut.scan_d[12] = 1'b1;
                26: force uut.scan_d[13] = 1'b0;
                27: force uut.scan_d[13] = 1'b1;
                28: force uut.scan_d[14] = 1'b0;
                29: force uut.scan_d[14] = 1'b1;
                30: force uut.scan_d[15] = 1'b0;
                31: force uut.scan_d[15] = 1'b1;
                32: force uut.scan_d[16] = 1'b0;
                33: force uut.scan_d[16] = 1'b1;
                34: force uut.scan_d[17] = 1'b0;
                35: force uut.scan_d[17] = 1'b1;
                default: $fatal(1, "Invalid fault ID");
            endcase
        end
    endtask

    task remove_fault;
        input integer fault_id;
        begin
            case (fault_id)
                 0,  1: release uut.scan_d[0];
                 2,  3: release uut.scan_d[1];
                 4,  5: release uut.scan_d[2];
                 6,  7: release uut.scan_d[3];
                 8,  9: release uut.scan_d[4];
                10, 11: release uut.scan_d[5];
                12, 13: release uut.scan_d[6];
                14, 15: release uut.scan_d[7];
                16, 17: release uut.scan_d[8];
                18, 19: release uut.scan_d[9];
                20, 21: release uut.scan_d[10];
                22, 23: release uut.scan_d[11];
                24, 25: release uut.scan_d[12];
                26, 27: release uut.scan_d[13];
                28, 29: release uut.scan_d[14];
                30, 31: release uut.scan_d[15];
                32, 33: release uut.scan_d[16];
                34, 35: release uut.scan_d[17];
                default: $fatal(1, "Invalid fault ID");
            endcase
        end
    endtask

    initial begin
        rst                = 1'b1;
        scan_en            = 1'b0;
        scan_in            = 1'b0;
        response           = 0;
        errors             = 0;
        detected_union     = 0;
        count_pattern      = 0;
        count_union        = 0;
        pattern_set_cycles = 0;

        for (p = 0; p < NUM_PATTERNS; p = p + 1)
            detection[p] = 0;

        // Vector:
        // {uart_tx, state, clk_count, bit_index, data_reg}.

        // P0: START, counter 5 -> 6.
        patterns[0] = {1'b0, 2'b01, 4'd5, 3'd0, 8'hA5};
        expected[0] = {1'b0, 2'b01, 4'd6, 3'd0, 8'hA5};

        // P1: START, counter 8 -> 9.
        patterns[1] = {1'b0, 2'b01, 4'd8, 3'd0, 8'hA5};
        expected[1] = {1'b0, 2'b01, 4'd9, 3'd0, 8'hA5};

        // P2: Dao data va dat bit_index = 7.
        patterns[2] = {1'b0, 2'b01, 4'd8, 3'd7, 8'h5A};
        expected[2] = {1'b0, 2'b01, 4'd9, 3'd7, 8'h5A};

        // P3: DATA, counter 5 -> 6.
        patterns[3] = {1'b1, 2'b10, 4'd5, 3'd0, 8'hA5};
        expected[3] = {1'b1, 2'b10, 4'd6, 3'd0, 8'hA5};

        // 1. Kiem tra golden va do chu ky moi pattern.
        $display("");
        $display("=== FULL SCAN TEST CYCLES ===");
        $display(
            "Pattern Reset_prepare Wait Load Capture Unload Observe Total"
        );

        for (p = 0; p < NUM_PATTERNS; p = p + 1) begin
            reset_dut;
            reset_end = clock_cycles;

            scan_load(patterns[p]);
            load_end = clock_cycles;

            capture_and_unload(response);

            if (response !== expected[p]) begin
                $fatal(
                    1,
                    "Baseline P%0d failed: expected=%05h actual=%05h",
                    p, expected[p], response
                );
            end

            golden[p] = response;

            reset_cycles = reset_end - trial_start;

            // Canh clock cho giua reset va shift dau tien.
            wait_cycles = load_end - reset_end - SCAN_LENGTH;

            total_cycles = clock_cycles - trial_start;

            if (total_cycles !=
                reset_cycles + wait_cycles +
                SCAN_LENGTH + 1 + SCAN_LENGTH)
                $fatal(1, "FAIL: cycle accounting P%0d", p);

            pattern_set_cycles =
                pattern_set_cycles + total_cycles;

            $display(
                "P%0d      %0d             %0d    %0d   %0d       %0d     %0d       %0d",
                p,
                reset_cycles,
                wait_cycles,
                SCAN_LENGTH,
                1,
                SCAN_LENGTH,
                0,
                total_cycles
            );

            $display(
                "PASS: baseline P%0d response=%05h",
                p, golden[p]
            );
        end

        $display(
            "Total cycles for %0d patterns = %0d",
            NUM_PATTERNS, pattern_set_cycles
        );

        $display(
            "Test time for pattern set = %0d ns",
            pattern_set_cycles * CLK_PERIOD
        );

        // 2. Moi lan thu chi chen mot loi.
        for (p = 0; p < NUM_PATTERNS; p = p + 1) begin
            for (f = 0; f < NUM_FAULTS; f = f + 1) begin
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

                remove_fault(f);
            end
        end

        // 3. Hop cac loi phat hien, khong dem trung.
        for (p = 0; p < NUM_PATTERNS; p = p + 1) begin
            detected_union = detected_union | detection[p];
            count_pattern = 0;

            for (f = 0; f < NUM_FAULTS; f = f + 1) begin
                if (detection[p][f])
                    count_pattern = count_pattern + 1;
            end

            $display(
                "P%0d detected = %0d/%0d",
                p, count_pattern, NUM_FAULTS
            );
        end

        $display("Fault_ID  D_bit  SA  P0 P1 P2 P3  Union");

        for (f = 0; f < NUM_FAULTS; f = f + 1) begin
            $display(
                "%0d         %0d     %0d   %b  %b  %b  %b    %b",
                f, f/2, f%2,
                detection[0][f],
                detection[1][f],
                detection[2][f],
                detection[3][f],
                detected_union[f]
            );

            if (detected_union[f])
                count_union = count_union + 1;
        end

        // 4. Kiem tra phuc hoi sau khi bo loi.
        for (p = 0; p < NUM_PATTERNS; p = p + 1) begin
            reset_dut;
            scan_load(patterns[p]);
            capture_and_unload(response);

            if (response !== golden[p]) begin
                errors = errors + 1;
                $display("ERROR: recovery failed for P%0d", p);
            end
        end

        $display("");
        $display("=== FINAL SUMMARY ===");
        $display("Scan FFs = %0d/18", SCAN_LENGTH);
        $display("Number of patterns = %0d", NUM_PATTERNS);
        $display("Observation cycles after unload = 0");

        $display(
            "Pattern-set test cycles (including reset/preparation) = %0d",
            pattern_set_cycles
        );

        $display(
            "Pattern-set test time = %0d ns",
            pattern_set_cycles * CLK_PERIOD
        );

        $display(
            "Union detected = %0d/%0d",
            count_union, NUM_FAULTS
        );

        $display(
            "Selected RTL fault coverage = %0.2f%%",
            100.0 * count_union / NUM_FAULTS
        );

        $display("Errors = %0d", errors);

        // PASS kiem tra campaign; coverage bao cao rieng.
        if (errors == 0) begin
            $display("PASS: full-scan 36 selected RTL fault campaign");
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