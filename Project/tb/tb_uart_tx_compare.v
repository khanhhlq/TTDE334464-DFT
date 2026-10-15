`timescale 1ns / 1ps

module tb_uart_tx_compare;

    localparam CLKS_PER_BIT = 16;
    localparam CLK_PERIOD   = 10;
    localparam BIT_PERIOD   = CLKS_PER_BIT * CLK_PERIOD;

    reg       clk;
    reg       rst;
    reg [7:0] tx_data;
    reg       tx_valid;

    wire tx_ready_ref;
    wire uart_tx_ref;

    wire tx_ready_scan;
    wire uart_tx_scan_out;
    wire scan_out;

    reg compare_en;

    integer compare_errors;
    integer frame_errors;
    integer frames_checked;
    integer cycles_checked;
    integer i;

    uart_tx #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) u_ref (
        .clk      (clk),
        .rst      (rst),
        .tx_data  (tx_data),
        .tx_valid (tx_valid),
        .tx_ready (tx_ready_ref),
        .uart_tx  (uart_tx_ref)
    );

    uart_tx_scan #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) u_scan (
        .clk      (clk),
        .rst      (rst),
        .tx_data  (tx_data),
        .tx_valid (tx_valid),
        .scan_en  (1'b0),
        .scan_in  (1'b0),
        .tx_ready (tx_ready_scan),
        .uart_tx  (uart_tx_scan_out),
        .scan_out (scan_out)
    );

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2.0) clk = ~clk;

    // Compare after the previous rising-edge updates have settled.
    always @(negedge clk) begin
        if (compare_en) begin
            cycles_checked = cycles_checked + 1;

            // Case equality against legal values also detects X/Z,
            // even if both DUTs have the same unknown value.
            if (!((uart_tx_ref === 1'b0) ||
                  (uart_tx_ref === 1'b1)) ||
                !((tx_ready_ref === 1'b0) ||
                  (tx_ready_ref === 1'b1))) begin

                compare_errors = compare_errors + 1;

                $display(
                    "ERROR @ %0t: reference output contains X/Z",
                    $time
                );
            end

            if (uart_tx_ref !== uart_tx_scan_out) begin
                compare_errors = compare_errors + 1;

                $display(
                    "ERROR @ %0t: TX mismatch ref=%b scan=%b",
                    $time, uart_tx_ref, uart_tx_scan_out
                );
            end

            if (tx_ready_ref !== tx_ready_scan) begin
                compare_errors = compare_errors + 1;

                $display(
                    "ERROR @ %0t: READY mismatch ref=%b scan=%b",
                    $time, tx_ready_ref, tx_ready_scan
                );
            end
        end
    end

    task send_byte;
        input [7:0] data;
        begin
            @(negedge clk);
            tx_data  = data;
            tx_valid = 1'b1;

            // Wait for a rising edge that accepts the byte.
            @(posedge clk);
            while (tx_ready_ref !== 1'b1)
                @(posedge clk);

            @(negedge clk);
            tx_valid = 1'b0;
        end
    endtask

    // Check the reference UART against the requested frame.
    // The cycle-by-cycle monitor compares the scan UART to it.
    task check_byte;
        input [7:0] expected;
        integer bit_no;
        integer errors_before;
        begin
            errors_before = frame_errors;

            @(negedge uart_tx_ref);
            #(BIT_PERIOD / 2.0);

            if (uart_tx_ref !== 1'b0) begin
                frame_errors = frame_errors + 1;
                $display("ERROR: invalid start bit");
            end

            if (tx_ready_ref !== 1'b0) begin
                frame_errors = frame_errors + 1;
                $display("ERROR: ready must be low during START");
            end

            for (bit_no = 0; bit_no < 8; bit_no = bit_no + 1) begin
                #(BIT_PERIOD);

                if (uart_tx_ref !== expected[bit_no]) begin
                    frame_errors = frame_errors + 1;

                    $display(
                        "ERROR: byte=%02h D%0d expected=%b actual=%b",
                        expected, bit_no,
                        expected[bit_no], uart_tx_ref
                    );
                end

                if (tx_ready_ref !== 1'b0) begin
                    frame_errors = frame_errors + 1;
                    $display("ERROR: ready must be low during DATA");
                end
            end

            #(BIT_PERIOD);

            if (uart_tx_ref !== 1'b1) begin
                frame_errors = frame_errors + 1;
                $display("ERROR: invalid stop bit");
            end

            if (tx_ready_ref !== 1'b0) begin
                frame_errors = frame_errors + 1;
                $display("ERROR: ready must be low during STOP");
            end

            frames_checked = frames_checked + 1;

            if (frame_errors == errors_before)
                $display(
                    "PASS: frame %0d - byte=0x%02h",
                    frames_checked, expected
                );
            else
                $display(
                    "FAIL: frame %0d - byte=0x%02h",
                    frames_checked, expected
                );
        end
    endtask

    task run_byte;
        input [7:0] data;
        begin
            fork
                send_byte(data);
                check_byte(data);
            join

            // Wait beyond the end of STOP.
            #(BIT_PERIOD);
            @(negedge clk);
            #1;

            if (tx_ready_ref !== 1'b1) begin
                frame_errors = frame_errors + 1;
                $display("ERROR: ready did not return high");
            end

            if (uart_tx_ref !== 1'b1) begin
                frame_errors = frame_errors + 1;
                $display("ERROR: TX did not remain high after frame");
            end
        end
    endtask

    initial begin
        rst            = 1'b1;
        tx_data        = 8'h00;
        tx_valid       = 1'b0;
        compare_en     = 1'b0;
        compare_errors = 0;
        frame_errors   = 0;
        frames_checked = 0;
        cycles_checked = 0;

        repeat (3) @(posedge clk);
        #1;

        // Check both DUTs after synchronous reset.
        if ((uart_tx_ref      !== 1'b1) ||
            (uart_tx_scan_out !== 1'b1) ||
            (tx_ready_ref     !== 1'b1) ||
            (tx_ready_scan    !== 1'b1)) begin

            frame_errors = frame_errors + 1;
            $display("ERROR: incorrect outputs after reset");
        end

        @(negedge clk);
        rst = 1'b0;

        // Enable away from the monitor's falling-edge event.
        #1;
        compare_en = 1'b1;

        // Directed data patterns.
        run_byte(8'h00);
        run_byte(8'hFF);
        run_byte(8'h55);
        run_byte(8'hAA);
        run_byte(8'h53);

        // Exercise every possible byte value.
        for (i = 0; i < 256; i = i + 1)
            run_byte(i[7:0]);

        // Abort an ongoing frame with synchronous reset.
        send_byte(8'hA5);

        // START lasts N clocks; 3N clocks places us in DATA.
        repeat (3 * CLKS_PER_BIT) @(posedge clk);

        @(negedge clk);
        rst = 1'b1;

        @(posedge clk);
        #1;

        if ((uart_tx_ref      !== 1'b1) ||
            (uart_tx_scan_out !== 1'b1) ||
            (tx_ready_ref     !== 1'b1) ||
            (tx_ready_scan    !== 1'b1)) begin

            frame_errors = frame_errors + 1;
            $display("ERROR: reset during frame did not restore IDLE");
        end

        @(negedge clk);
        rst = 1'b0;

        // Confirm normal operation after reset.
        run_byte(8'h3C);

        // Finalize away from the comparison event.
        @(posedge clk);
        #1;
        compare_en = 1'b0;

        $display("Frames checked    = %0d", frames_checked);
        $display("Cycles compared   = %0d", cycles_checked);
        $display("Comparison errors = %0d", compare_errors);
        $display("Frame errors      = %0d", frame_errors);

        if ((compare_errors == 0) && (frame_errors == 0)) begin
            $display(
                "PASS: UART functional comparison - scan_en=0"
            );
            $finish;
        end
        else begin
            $fatal(1, "FAIL: UART functional comparison");
        end
    end

    initial begin
        #1000000;
        $fatal(1, "FAIL: UART functional comparison - timeout");
    end

endmodule