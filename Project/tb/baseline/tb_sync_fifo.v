`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/21/2026 04:08:22 PM
// Design Name: 
// Module Name: tb_sync_fifo
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1ns / 1ps

module tb_sync_fifo;

    parameter DATA_WIDTH = 8;
    parameter DEPTH      = 16;
    parameter CLK_PERIOD = 10;

    localparam TIMEOUT = (20 * DEPTH + 100) * CLK_PERIOD;

    reg                      clk;
    reg                      rst;
    reg                      wr_en;
    reg [DATA_WIDTH-1:0]     wr_data;
    reg                      rd_en;

    wire [DATA_WIDTH-1:0]    rd_data;
    wire                     full;
    wire                     empty;

    integer errors;
    integer i;

    // Bo nho tham chieu de so sanh voi FIFO.
    reg [DATA_WIDTH-1:0] expected_mem [0:DEPTH-1];

    integer expected_count;
    integer expected_wr_ptr;
    integer expected_rd_ptr;

    sync_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (DEPTH)
    ) uut (
        .clk     (clk),
        .rst     (rst),
        .wr_en   (wr_en),
        .wr_data (wr_data),
        .rd_en   (rd_en),
        .rd_data (rd_data),
        .full    (full),
        .empty   (empty)
    );

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2.0) clk = ~clk;

    // Kiem tra cac dau ra theo trang thai tham chieu.
    task check_outputs;
        begin
            if (full !== (expected_count == DEPTH)) begin
                errors = errors + 1;
                $display(
                    "ERROR @ %0t: full=%b expected=%b",
                    $time, full, (expected_count == DEPTH)
                );
            end

            if (empty !== (expected_count == 0)) begin
                errors = errors + 1;
                $display(
                    "ERROR @ %0t: empty=%b expected=%b",
                    $time, empty, (expected_count == 0)
                );
            end

            // Chi kiem tra du lieu khi FIFO khong rong.
            if (expected_count > 0) begin
                if (rd_data !== expected_mem[expected_rd_ptr]) begin
                    errors = errors + 1;
                    $display(
                        "ERROR @ %0t: rd_data=%h expected=%h",
                        $time,
                        rd_data,
                        expected_mem[expected_rd_ptr]
                    );
                end
            end
        end
    endtask

    // Thuc hien mot chu ky doc/ghi.
    task fifo_cycle;
        input do_write;
        input do_read;
        input [DATA_WIDTH-1:0] data;

        reg accept_write;
        reg accept_read;

        begin
            // Doi dau vao tai canh xuong, tranh race voi DUT.
            @(negedge clk);
            wr_en   = do_write;
            rd_en   = do_read;
            wr_data = data;

            // Quyet dinh theo trang thai TRUOC canh len.
            // Khong dua vao full/empty cua DUT de tinh dap an.
            accept_write = do_write && (expected_count < DEPTH);
            accept_read  = do_read  && (expected_count > 0);

            // Kiem tra phan tu dau hang truoc khi doc.
            check_outputs;

            @(posedge clk);

            // Cap nhat mo hinh tham chieu.
            if (accept_write) begin
                expected_mem[expected_wr_ptr] = data;
                expected_wr_ptr =
                    (expected_wr_ptr + 1) % DEPTH;
            end

            if (accept_read) begin
                expected_rd_ptr =
                    (expected_rd_ptr + 1) % DEPTH;
            end

            case ({accept_write, accept_read})
                2'b10: expected_count = expected_count + 1;
                2'b01: expected_count = expected_count - 1;
                default: begin end
            endcase

            // Cho DUT cap nhat nonblocking va logic dau ra.
            #1;
            check_outputs;
        end
    endtask

    task reset_fifo;
        begin
            @(negedge clk);
            rst     = 1'b1;
            wr_en   = 1'b0;
            rd_en   = 1'b0;
            wr_data = 0;

            repeat (3) @(posedge clk);

            #1;
            expected_count  = 0;
            expected_wr_ptr = 0;
            expected_rd_ptr = 0;

            check_outputs;

            @(negedge clk);
            rst = 1'b0;
        end
    endtask

    initial begin
        errors          = 0;
        expected_count  = 0;
        expected_wr_ptr = 0;
        expected_rd_ptr = 0;

        rst     = 1'b1;
        wr_en   = 1'b0;
        rd_en   = 1'b0;
        wr_data = 0;

        // 1. Reset.
        $display("TEST 1: Reset");
        reset_fifo;

        // 2. Doc khi rong: phai bi chan.
        $display("TEST 2: Read while empty");
        fifo_cycle(1'b0, 1'b1, 0);

        // 3. Ghi day FIFO.
        $display("TEST 3: Fill FIFO");
        for (i = 0; i < DEPTH; i = i + 1)
            fifo_cycle(1'b1, 1'b0, i + 8'h10);

        // 4. Ghi khi day: khong duoc ghi de du lieu cu.
        $display("TEST 4: Write while full");
        fifo_cycle(1'b1, 1'b0, 8'hEE);

        // 5. Doc het, kiem tra dung thu tu.
        $display("TEST 5: Drain FIFO");
        for (i = 0; i < DEPTH; i = i + 1)
            fifo_cycle(1'b0, 1'b1, 0);

        // 6. Rong va cung yeu cau doc/ghi:
        // chi ghi duoc chap nhan.
        $display("TEST 6: Simultaneous requests while empty");
        fifo_cycle(1'b1, 1'b1, 8'hA5);

        // Doc lai byte vua ghi.
        fifo_cycle(1'b0, 1'b1, 0);

        // 7. Tao mot phan tu, sau do doc/ghi dong thoi.
        // So phan tu giu nguyen, con tro quay nhieu vong.
        $display("TEST 7: Simultaneous read/write and wraparound");
        fifo_cycle(1'b1, 1'b0, 8'h33);

        for (i = 0; i < 2 * DEPTH + 3; i = i + 1)
            fifo_cycle(1'b1, 1'b1, i + 8'h40);

        fifo_cycle(1'b0, 1'b1, 0);

        // 8. Day va cung yeu cau doc/ghi:
        // chi doc duoc chap nhan theo quy uoc hien tai.
        $display("TEST 8: Simultaneous requests while full");
        for (i = 0; i < DEPTH; i = i + 1)
            fifo_cycle(1'b1, 1'b0, i + 8'h80);

        fifo_cycle(1'b1, 1'b1, 8'hFF);

        // Con DEPTH - 1 phan tu cu.
        for (i = 0; i < DEPTH - 1; i = i + 1)
            fifo_cycle(1'b0, 1'b1, 0);

        // 9. Reset khi FIFO dang co du lieu.
        $display("TEST 9: Reset while occupied");
        fifo_cycle(1'b1, 1'b0, 8'hAB);
        reset_fifo;

        // Kiem tra hoat dong lai sau reset.
        fifo_cycle(1'b1, 1'b0, 8'h5A);
        fifo_cycle(1'b0, 1'b1, 0);

        // 10. Khong doc/ghi: giu nguyen trang thai.
        $display("TEST 10: Idle");
        fifo_cycle(1'b0, 1'b0, 0);
        fifo_cycle(1'b0, 1'b0, 0);

        if (errors == 0) begin
            $display("PASS: tb_sync_fifo - all tests passed");
            $finish;
        end
        else begin
            $fatal(1, "FAIL: tb_sync_fifo - %0d errors", errors);
        end
    end

    initial begin
        #(TIMEOUT);
        $fatal(1, "FAIL: tb_sync_fifo - simulation timeout");
    end

endmodule
