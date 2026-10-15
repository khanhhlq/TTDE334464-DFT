`timescale 1ns / 1ps

module tb_scan_dff;

    reg clk;
    reg rst;
    reg d_in;
    reg scan_in;
    reg scan_en;

    wire q;

    integer errors;

    scan_dff #(.RESET_VALUE(1'b0)) uut (
        .clk     (clk),
        .rst     (rst),
        .scan_en (scan_en),
        .d_in    (d_in),
        .scan_in (scan_in),
        .q       (q)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task check_q;
        input expected;
        begin
            if (q !== expected) begin
                errors = errors + 1;
                $display(
                    "ERROR @ %0t: rst=%b scan_en=%b expected=%b actual=%b",
                    $time, rst, scan_en, expected, q
                );
            end
        end
    endtask

    initial begin
        errors  = 0;
        rst     = 1'b1;
        scan_en = 1'b1;
        d_in    = 1'b1;
        scan_in = 1'b1;

        @(posedge clk);
        #1;
        check_q(1'b0);

        @(negedge clk);
        rst     = 1'b0;
        scan_en = 1'b0;
        d_in    = 1'b1;
        scan_in = 1'b0;

        @(posedge clk);
        #1;
        check_q(1'b1);

        @(negedge clk);
        d_in    = 1'b0;
        scan_in = 1'b1;

        @(posedge clk);
        #1;
        check_q(1'b0);

        @(negedge clk);
        scan_en = 1'b1;
        d_in    = 1'b0;
        scan_in = 1'b1;

        @(posedge clk);
        #1;
        check_q(1'b1);

        @(negedge clk);
        d_in    = 1'b1;
        scan_in = 1'b0;

        @(posedge clk);
        #1;
        check_q(1'b0);

        @(negedge clk);
        scan_en = 1'b0;
        d_in    = 1'b1;

        @(posedge clk);
        #1;
        check_q(1'b1);

        @(negedge clk);
        rst = 1'b1;

        #1;
        check_q(1'b1);

        @(posedge clk);
        #1;
        check_q(1'b0);

        @(negedge clk);
        rst = 1'b0;

        @(posedge clk);
        #1;
        check_q(1'b1);

        if (errors == 0) begin
            $display("PASS: tb_scan_dff");
            $finish;
        end
        else begin
            $fatal(1, "FAIL: tb_scan_dff - %0d errors", errors);
        end
    end

    initial begin
        #10000;
        $fatal(1, "FAIL: tb_scan_dff - simulation timeout");
    end

endmodule