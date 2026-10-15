`timescale 1ns / 1ps

module tb_scan_chain4;

    reg       clk;
    reg       rst;
    reg       scan_en;
    reg       scan_in;
    reg [3:0] d_in;

    wire [3:0] q;
    wire       scan_out;

    integer errors;

    scan_chain4 uut (
        .clk      (clk),
        .rst      (rst),
        .scan_en  (scan_en),
        .scan_in  (scan_in),
        .d_in     (d_in),
        .q        (q),
        .scan_out (scan_out)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task check_q;
        input [3:0] expected;
        begin
            if (q !== expected) begin
                errors = errors + 1;
                $display(
                    "ERROR @ %0t: q expected=%b actual=%b",
                    $time, expected, q
                );
            end
        end
    endtask

    task check_scan_out;
        input expected;
        begin
            if (scan_out !== expected) begin
                errors = errors + 1;
                $display(
                    "ERROR @ %0t: scan_out expected=%b actual=%b",
                    $time, expected, scan_out
                );
            end
        end
    endtask

    initial begin
        errors  = 0;
        rst     = 1'b1;
        scan_en = 1'b0;
        scan_in = 1'b0;
        d_in    = 4'b0000;

        repeat (3) @(posedge clk);
        #1;
        check_q(4'b0000);

        @(negedge clk);
        rst = 1'b0;

        // Shift-in: 1, 0, 1, 1.
        @(negedge clk);
        scan_en = 1'b1;
        scan_in = 1'b1;

        @(posedge clk);
        #1;
        check_q(4'b0001);

        @(negedge clk);
        scan_in = 1'b0;

        @(posedge clk);
        #1;
        check_q(4'b0010);

        @(negedge clk);
        scan_in = 1'b1;

        @(posedge clk);
        #1;
        check_q(4'b0101);

        @(negedge clk);
        scan_in = 1'b1;

        @(posedge clk);
        #1;
        check_q(4'b1011);

        // Capture parallel input.
        @(negedge clk);
        scan_en = 1'b0;
        d_in    = 4'b0110;

        @(posedge clk);
        #1;
        check_q(4'b0110);

        // Shift-out bit 3, before shifting.
        @(negedge clk);
        scan_en = 1'b1;
        scan_in = 1'b0;
        check_scan_out(1'b0);

        @(posedge clk);
        #1;
        check_q(4'b1100);

        // Shift-out bit 2.
        @(negedge clk);
        check_scan_out(1'b1);

        @(posedge clk);
        #1;
        check_q(4'b1000);

        // Shift-out bit 1.
        @(negedge clk);
        check_scan_out(1'b1);

        @(posedge clk);
        #1;
        check_q(4'b0000);

        // Shift-out bit 0.
        @(negedge clk);
        check_scan_out(1'b0);

        @(posedge clk);
        #1;
        check_q(4'b0000);

        if (errors == 0) begin
            $display("PASS: tb_scan_chain4");
            $finish;
        end
        else begin
            $fatal(1, "FAIL: tb_scan_chain4 - %0d errors", errors);
        end
    end

    initial begin
        #10000;
        $fatal(1, "FAIL: tb_scan_chain4 - simulation timeout");
    end

endmodule