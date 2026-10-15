`timescale 1ns / 1ps

module tb_uart_tx_partial_scoap_fault_campaign;

    localparam CLKS_PER_BIT = 16;
    localparam SCAN_LENGTH  = 6;
    localparam NUM_FAULTS   = 8;
    localparam NUM_PATTERNS = 2;

    reg       clk;
    reg       rst;
    reg [7:0] tx_data;
    reg       tx_valid;
    reg       scan_en;
    reg       scan_in;

    wire tx_ready;
    wire uart_tx;
    wire scan_out;

    reg [SCAN_LENGTH-1:0] pattern;
    reg [SCAN_LENGTH-1:0] expected;
    reg [SCAN_LENGTH-1:0] response;

    reg [SCAN_LENGTH-1:0] golden [0:NUM_PATTERNS-1];
    reg [NUM_FAULTS-1:0] detection [0:NUM_PATTERNS-1];
    reg [NUM_FAULTS-1:0] detected_union;

    integer p;
    integer f;
    integer i;
    integer errors;
    integer detected_count;

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

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        rst            = 1'b1;
        tx_data        = 8'hFF;
        tx_valid       = 1'b0;
        scan_en        = 1'b0;
        scan_in        = 1'b0;
        pattern        = 0;
        expected       = 0;
        response       = 0;
        errors         = 0;
        detected_count = 0;
        detected_union = 0;

        detection[0] = 0;
        detection[1] = 0;

        for (p = 0; p < NUM_PATTERNS; p = p + 1) begin

            // Vector scan: {clk_count, bit_index[1:0]}.
            if (p == 0) begin
                pattern  = {4'd5, 2'd0};
                expected = {4'd6, 2'd0};
            end
            else begin
                pattern  = {4'd8, 2'd0};
                expected = {4'd9, 2'd0};
            end

            // f=-1: chay khong loi de lay golden.
            // f=0..7: chay tung loi rieng biet.
            for (f = -1; f < NUM_FAULTS; f = f + 1) begin

                @(negedge clk);
                rst      = 1'b1;
                tx_valid = 1'b0;
                scan_en  = 1'b0;
                scan_in  = 1'b0;

                repeat (2) @(posedge clk);

                // State khong scan: dung giao tiep UART
                // de thiet lap START.
                @(negedge clk);
                rst      = 1'b0;
                tx_data  = 8'hFF;
                tx_valid = 1'b1;

                @(posedge clk);
                #1;

                if (uut.state !== 2'b01)
                    $fatal(1, "FAIL: cannot prepare START");

                // Chi chen loi sau khi chuan bi START.
                // Cac loi nam tai dau vao D chuc nang;
                // shift van di qua nhanh scan.
                case (f)
                    -1: begin end
                     0: force uut.scan_d[11] = 1'b0;
                     1: force uut.scan_d[11] = 1'b1;
                     2: force uut.scan_d[12] = 1'b0;
                     3: force uut.scan_d[12] = 1'b1;
                     4: force uut.scan_d[13] = 1'b0;
                     5: force uut.scan_d[13] = 1'b1;
                     6: force uut.scan_d[14] = 1'b0;
                     7: force uut.scan_d[14] = 1'b1;
                endcase

                // Shift-in.
                for (i = SCAN_LENGTH - 1; i >= 0; i = i - 1) begin
                    @(negedge clk);
                    tx_valid = 1'b0;
                    scan_en  = 1'b1;
                    scan_in  = pattern[i];

                    @(posedge clk);
                    #1;
                end

                if (uut.state !== 2'b01)
                    $fatal(1, "FAIL: START changed during shift");

                // Capture mot chu ky.
                @(negedge clk);
                scan_en = 1'b0;
                scan_in = 1'b0;

                @(posedge clk);
                #1;

                // Shift-out.
                response = 0;

                for (i = SCAN_LENGTH - 1; i >= 0; i = i - 1) begin
                    @(negedge clk);
                    scan_en     = 1'b1;
                    scan_in     = 1'b0;
                    response[i] = scan_out;

                    @(posedge clk);
                    #1;
                end

                if (f == -1) begin
                    if (response !== expected)
                        $fatal(
                            1,
                            "FAIL GOLDEN: P%0d expected=%b actual=%b",
                            p, expected, response
                        );

                    golden[p] = response;
                    $display(
                        "PASS GOLDEN: P%0d response=%b",
                        p, response
                    );
                end
                else begin
                    if ((^response) === 1'bx) begin
                        errors = errors + 1;
                        $display("ERROR: P%0d F%0d contains X/Z", p, f);
                    end
                    else if (response != golden[p]) begin
                        detection[p][f] = 1'b1;
                        $display(
                            "DETECTED: P%0d F%0d good=%b faulty=%b",
                            p, f, golden[p], response
                        );
                    end
                    else begin
                        $display("NOT_DETECTED: P%0d F%0d", p, f);
                    end
                end

                // Bo loi truoc lan thu tiep theo.
                case (f)
                    0, 1: release uut.scan_d[11];
                    2, 3: release uut.scan_d[12];
                    4, 5: release uut.scan_d[13];
                    6, 7: release uut.scan_d[14];
                    default: begin end
                endcase
            end
        end

        detected_union = detection[0] | detection[1];

        $display("Fault_ID  D_bit  SA  P0  P1  Union");

        for (f = 0; f < NUM_FAULTS; f = f + 1) begin
            $display(
                "%0d         %0d     %0d   %b   %b   %b",
                f, 11 + f/2, f%2,
                detection[0][f],
                detection[1][f],
                detected_union[f]
            );

            if (detected_union[f])
                detected_count = detected_count + 1;
        end

        $display("Detected = %0d/%0d", detected_count, NUM_FAULTS);
        $display(
            "Selected RTL fault coverage = %0.2f%%",
            100.0 * detected_count / NUM_FAULTS
        );

        // Kiem tra ma tran du kien cua hai mau.
        if ((detection[0] !== 8'b10010110) ||
            (detection[1] !== 8'b01101001))
            errors = errors + 1;

        $display("Errors = %0d", errors);

        if (errors == 0) begin
            $display("PASS: SCOAP partial-scan selected fault campaign");
            $finish;
        end
        else begin
            $fatal(1, "FAIL: SCOAP partial-scan fault campaign");
        end
    end

    initial begin
        #100000;
        $fatal(1, "FAIL: campaign timeout");
    end

endmodule