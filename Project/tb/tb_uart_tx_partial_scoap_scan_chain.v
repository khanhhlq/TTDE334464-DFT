`timescale 1ns / 1ps

module tb_uart_tx_partial_scoap_scan_chain;

    localparam CLKS_PER_BIT = 16;
    localparam SCAN_LENGTH  = 6;

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
    reg [SCAN_LENGTH-1:0] response;
    reg [SCAN_LENGTH-1:0] expected;

    integer k;
    integer i;
    integer p;
    integer errors;
    integer shift_tests;
    integer capture_tests;

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
        rst           = 1'b1;
        tx_data       = 8'h00;
        tx_valid      = 1'b0;
        scan_en       = 1'b0;
        scan_in       = 1'b0;
        pattern       = 0;
        response      = 0;
        expected      = 0;
        errors        = 0;
        shift_tests   = 0;
        capture_tests = 0;

        // ==========================================
        // 1. SHIFT: thu tat ca 64 mau cua chuoi 6 FF.
        // ==========================================
        for (k = 0; k < 64; k = k + 1) begin

            // Reset truoc moi mau.
            @(negedge clk);
            rst      = 1'b1;
            scan_en  = 1'b0;
            scan_in  = 1'b0;
            tx_valid = 1'b0;

            repeat (2) @(posedge clk);

            @(negedge clk);
            rst = 1'b0;

            pattern = k[5:0];

            // Shift-in: gui MSB truoc.
            for (i = SCAN_LENGTH - 1; i >= 0; i = i - 1) begin
                @(negedge clk);
                scan_en = 1'b1;
                scan_in = pattern[i];

                @(posedge clk);
                #1;
            end

            // Shift-out: doc truoc canh dich.
            response = 0;

            for (i = SCAN_LENGTH - 1; i >= 0; i = i - 1) begin
                @(negedge clk);
                scan_en    = 1'b1;
                scan_in    = 1'b0;
                response[i] = scan_out;

                @(posedge clk);
                #1;
            end

            shift_tests = shift_tests + 1;

            if (response !== pattern) begin
                errors = errors + 1;
                $display(
                    "FAIL SHIFT: pattern=%b response=%b",
                    pattern, response
                );
            end
        end

        // ==========================================
        // 2. CAPTURE trong START.
        // Vector: {clk_count[3:0], bit_index[1:0]}.
        // State khong scan, phai thiet lap chuc nang.
        // ==========================================
        for (p = 0; p < 2; p = p + 1) begin

            @(negedge clk);
            rst      = 1'b1;
            scan_en  = 1'b0;
            scan_in  = 1'b0;
            tx_valid = 1'b0;
            tx_data  = 8'hFF;

            repeat (2) @(posedge clk);

            // Dua UART tu IDLE sang START.
            @(negedge clk);
            rst      = 1'b0;
            tx_valid = 1'b1;

            @(posedge clk);
            #1;

            if (uut.state !== 2'b01)
                $fatal(1, "FAIL: cannot prepare START");

            // Khong de chen mot chu ky chuc nang
            // giua chuan bi START va shift-in.
            if (p == 0) begin
                pattern  = {4'd5, 2'd2};
                expected = {4'd6, 2'd2};
            end
            else begin
                pattern  = {4'd8, 2'd1};
                expected = {4'd9, 2'd1};
            end

            for (i = SCAN_LENGTH - 1; i >= 0; i = i - 1) begin
                @(negedge clk);
                tx_valid = 1'b0;
                scan_en  = 1'b1;
                scan_in  = pattern[i];

                @(posedge clk);
                #1;
            end

            // State khong scan van cap nhat khi shift.
            // Hai mau tren duoc chon de giu START.
            if (uut.state !== 2'b01)
                $fatal(1, "FAIL: START changed during shift");

            // Mot chu ky capture.
            @(negedge clk);
            scan_en = 1'b0;
            scan_in = 1'b0;

            @(posedge clk);
            #1;

            // Doc phan hoi qua scan_out.
            response = 0;

            for (i = SCAN_LENGTH - 1; i >= 0; i = i - 1) begin
                @(negedge clk);
                scan_en     = 1'b1;
                scan_in     = 1'b0;
                response[i] = scan_out;

                @(posedge clk);
                #1;
            end

            capture_tests = capture_tests + 1;

            if (response !== expected) begin
                errors = errors + 1;
                $display(
                    "FAIL CAPTURE: loaded=%b expected=%b actual=%b",
                    pattern, expected, response
                );
            end
            else begin
                $display(
                    "PASS CAPTURE: loaded=%b response=%b",
                    pattern, response
                );
            end
        end

        $display("Shift tests   = %0d", shift_tests);
        $display("Capture tests = %0d", capture_tests);
        $display("Errors        = %0d", errors);

        if (errors == 0) begin
            $display("PASS: SCOAP partial-scan chain and capture");
            $finish;
        end
        else begin
            $fatal(1, "FAIL: SCOAP partial-scan chain and capture");
        end
    end

    initial begin
        #100000;
        $fatal(1, "FAIL: simulation timeout");
    end

endmodule