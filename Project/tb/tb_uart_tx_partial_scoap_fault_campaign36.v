`timescale 1ns / 1ps

module tb_uart_tx_partial_scoap_fault_campaign36;

    localparam CLKS_PER_BIT = 16;
    localparam CLK_PERIOD   = 10;
    localparam SCAN_LENGTH  = 6;
    localparam NUM_FAULTS   = 36;
    localparam NUM_PATTERNS = 4;
    localparam OBS_CYCLES   = 12 * CLKS_PER_BIT;

    // TX/READY sau capture, scan_out + TX/READY khi unload,
    // va TX/READY trong giai doan quan sat chuc nang.
    localparam RESPONSE_WIDTH =
        2 + 3 * SCAN_LENGTH + 2 * OBS_CYCLES;

    reg       clk;
    reg       rst;
    reg [7:0] tx_data;
    reg       tx_valid;
    reg       scan_en;
    reg       scan_in;

    wire tx_ready;
    wire uart_tx;
    wire scan_out;

    reg [SCAN_LENGTH-1:0] patterns [0:NUM_PATTERNS-1];
    reg [RESPONSE_WIDTH-1:0] golden [0:NUM_PATTERNS-1];
    reg [RESPONSE_WIDTH-1:0] response;

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
    integer prepare_end;
    integer load_end;

    integer prepare_cycles;
    integer wait_cycles;
    integer total_cycles;
    integer pattern_set_cycles;

    uart_tx_partial_scoap #(
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

    initial begin
        clk          = 1'b0;
        clock_cycles = 0;
    end

    always #(CLK_PERIOD / 2) clk = ~clk;

    always @(posedge clk)
        clock_cycles = clock_cycles + 1;

    // Chuan bi FF khong scan bang giao tiep chuc nang.
    // Loi chi duoc chen sau khi hoan tat chuan bi.
    task prepare_dut;
        input integer pattern_id;
        begin
            @(negedge clk);
            rst      = 1'b1;
            tx_valid = 1'b0;
            scan_en  = 1'b0;
            scan_in  = 1'b0;
            tx_data  = 8'h00;

            // Khong tinh khoang cho truoc khi bat dau reset.
            trial_start = clock_cycles;

            repeat (3) @(posedge clk);

            @(negedge clk);
            rst      = 1'b0;
            tx_data  = (pattern_id % 2 == 0) ? 8'hA5 : 8'h5A;
            tx_valid = 1'b1;

            @(posedge clk);
            #1;

            if (uut.state !== 2'b01)
                $fatal(1, "FAIL: cannot prepare START");

            @(negedge clk);
            tx_valid = 1'b0;

            // P0/P1: START; P2/P3: DATA.
            if (pattern_id >= 2) begin
                repeat (CLKS_PER_BIT) @(posedge clk);
                #1;

                if (uut.state !== 2'b10)
                    $fatal(1, "FAIL: cannot prepare DATA");
            end
        end
    endtask

    task scan_load;
        input [SCAN_LENGTH-1:0] value;
        integer i;
        begin
            // Vector: {clk_count[3:0], bit_index[1:0]}.
            for (i = SCAN_LENGTH - 1; i >= 0; i = i - 1) begin
                @(negedge clk);
                scan_en = 1'b1;
                scan_in = value[i];

                @(posedge clk);
                #1;
            end
        end
    endtask

    task capture_unload_observe;
        output [RESPONSE_WIDTH-1:0] value;
        integer i;
        integer position;
        begin
            value    = 0;
            position = 0;

            // Capture: 1 chu ky.
            @(negedge clk);
            scan_en = 1'b0;
            scan_in = 1'b0;

            @(posedge clk);
            #1;

            value[position]     = uart_tx;
            value[position + 1] = tx_ready;
            position = position + 2;

            // Unload: SCAN_LENGTH chu ky.
            for (i = SCAN_LENGTH - 1; i >= 0; i = i - 1) begin
                @(negedge clk);
                scan_en = 1'b1;
                scan_in = 1'b0;

                // Doc scan_out truoc canh dich.
                value[position] = scan_out;
                position = position + 1;

                @(posedge clk);
                #1;

                value[position]     = uart_tx;
                value[position + 1] = tx_ready;
                position = position + 2;
            end

            // Quan sat chuc nang sau unload.
            @(negedge clk);
            scan_en  = 1'b0;
            scan_in  = 1'b0;
            tx_valid = 1'b0;

            for (i = 0; i < OBS_CYCLES; i = i + 1) begin
                @(posedge clk);
                #1;

                value[position]     = uart_tx;
                value[position + 1] = tx_ready;
                position = position + 2;
            end

            if (position != RESPONSE_WIDTH)
                $fatal(1, "FAIL: response width mismatch");
        end
    endtask

    // F(2*k): scan_d[k] SA0.
    // F(2*k+1): scan_d[k] SA1.
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
        tx_data            = 0;
        tx_valid           = 1'b0;
        scan_en            = 1'b0;
        scan_in            = 1'b0;
        response           = 0;
        detected_union     = 0;
        errors             = 0;
        count_pattern      = 0;
        count_union        = 0;
        pattern_set_cycles = 0;

        for (p = 0; p < NUM_PATTERNS; p = p + 1)
            detection[p] = 0;

        patterns[0] = {4'd5, 2'd0};
        patterns[1] = {4'd8, 2'd0};
        patterns[2] = {4'd5, 2'd1};
        patterns[3] = {4'd8, 2'd2};

        // 1. Ghi golden va do chu ky cua tap pattern.
        $display("");
        $display("=== PARTIAL SCOAP TEST CYCLES ===");
        $display(
            "Pattern Reset_prepare Wait Load Capture Unload Observe Total"
        );

        for (p = 0; p < NUM_PATTERNS; p = p + 1) begin
            prepare_dut(p);
            prepare_end = clock_cycles;

            scan_load(patterns[p]);
            load_end = clock_cycles;

            capture_unload_observe(response);

            if ((^response) === 1'bx)
                $fatal(1, "FAIL: golden P%0d contains X/Z", p);

            golden[p] = response;

            prepare_cycles = prepare_end - trial_start;
            wait_cycles = load_end - prepare_end - SCAN_LENGTH;
            total_cycles = clock_cycles - trial_start;

            if (total_cycles !=
                prepare_cycles + wait_cycles +
                SCAN_LENGTH + 1 + SCAN_LENGTH + OBS_CYCLES)
                $fatal(1, "FAIL: cycle accounting P%0d", p);

            pattern_set_cycles =
                pattern_set_cycles + total_cycles;

            $display(
                "P%0d      %0d             %0d    %0d    %0d       %0d      %0d     %0d",
                p,
                prepare_cycles,
                wait_cycles,
                SCAN_LENGTH,
                1,
                SCAN_LENGTH,
                OBS_CYCLES,
                total_cycles
            );

            $display("PASS: golden P%0d recorded", p);
        end

        $display(
            "Total cycles for %0d patterns = %0d",
            NUM_PATTERNS, pattern_set_cycles
        );

        $display(
            "Test time for pattern set = %0d ns",
            pattern_set_cycles * CLK_PERIOD
        );

        // 2. Mo phong tung loi voi tung pattern.
        for (p = 0; p < NUM_PATTERNS; p = p + 1) begin
            for (f = 0; f < NUM_FAULTS; f = f + 1) begin
                prepare_dut(p);
                inject_fault(f);

                scan_load(patterns[p]);
                capture_unload_observe(response);

                if ((^response) === 1'bx) begin
                    errors = errors + 1;
                    $display("ERROR: P%0d F%0d contains X/Z", p, f);
                end
                else if (response != golden[p]) begin
                    detection[p][f] = 1'b1;
                    $display("DETECTED: P%0d F%0d", p, f);
                end
                else begin
                    $display("NOT_DETECTED: P%0d F%0d", p, f);
                end

                remove_fault(f);
            end
        end

        // 3. Tong hop ket qua phat hien loi.
        for (p = 0; p < NUM_PATTERNS; p = p + 1) begin
            count_pattern = 0;

            for (f = 0; f < NUM_FAULTS; f = f + 1) begin
                if (detection[p][f])
                    count_pattern = count_pattern + 1;
            end

            $display(
                "P%0d detected = %0d/%0d",
                p, count_pattern, NUM_FAULTS
            );

            detected_union = detected_union | detection[p];
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

        // 4. Kiem tra phuc hoi sau khi bo tat ca loi.
        for (p = 0; p < NUM_PATTERNS; p = p + 1) begin
            prepare_dut(p);
            scan_load(patterns[p]);
            capture_unload_observe(response);

            if (response !== golden[p]) begin
                errors = errors + 1;
                $display("ERROR: recovery failed for P%0d", p);
            end
        end

        $display("");
        $display("=== FINAL SUMMARY ===");
        $display("Scan FFs = %0d/18", SCAN_LENGTH);
        $display("Number of patterns = %0d", NUM_PATTERNS);
        $display("Observation cycles per pattern = %0d", OBS_CYCLES);

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

        if (errors == 0) begin
            $display("PASS: SCOAP partial-scan 36 RTL fault campaign");
            $finish;
        end
        else begin
            $fatal(1, "FAIL: campaign - %0d errors", errors);
        end
    end

    initial begin
        #1000000;
        $fatal(1, "FAIL: campaign timeout");
    end

endmodule