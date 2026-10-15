`timescale 1ns / 1ps

module sync_fifo_partial_scan #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 16
)(
    input                       clk,
    input                       rst,

    input                       wr_en,
    input  [DATA_WIDTH-1:0]      wr_data,
    input                       rd_en,

    output [DATA_WIDTH-1:0]      rd_data,
    output                      full,
    output                      empty,

    input                       scan_en,
    input                       scan_in,
    output                      scan_out
);

    localparam PTR_WIDTH =
        (DEPTH > 1) ? $clog2(DEPTH) : 1;

    localparam COUNT_WIDTH = $clog2(DEPTH + 1);

    localparam SCAN_LENGTH =
        2 * PTR_WIDTH + COUNT_WIDTH;

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    wire [PTR_WIDTH-1:0]   wr_ptr;
    wire [PTR_WIDTH-1:0]   rd_ptr;
    wire [COUNT_WIDTH-1:0] count;

    reg [PTR_WIDTH-1:0]   wr_ptr_next;
    reg [PTR_WIDTH-1:0]   rd_ptr_next;
    reg [COUNT_WIDTH-1:0] count_next;

    wire write_ok;
    wire read_ok;

    wire [SCAN_LENGTH-1:0] scan_d;
    wire [SCAN_LENGTH-1:0] scan_q;
    wire [SCAN_LENGTH:0]   scan_link;

    assign full  = (count == DEPTH);
    assign empty = (count == 0);

    assign write_ok = wr_en && !full;
    assign read_ok  = rd_en && !empty;

    assign rd_data = mem[rd_ptr];

    always @(posedge clk) begin
        if (!rst && write_ok)
            mem[wr_ptr] <= wr_data;
    end

    always @(*) begin
        wr_ptr_next = wr_ptr;
        rd_ptr_next = rd_ptr;
        count_next  = count;

        if (write_ok) begin
            if (wr_ptr == DEPTH - 1)
                wr_ptr_next = 0;
            else
                wr_ptr_next = wr_ptr + 1'b1;
        end

        if (read_ok) begin
            if (rd_ptr == DEPTH - 1)
                rd_ptr_next = 0;
            else
                rd_ptr_next = rd_ptr + 1'b1;
        end

        case ({write_ok, read_ok})
            2'b10: count_next = count + 1'b1;
            2'b01: count_next = count - 1'b1;
            default: count_next = count;
        endcase
    end

    assign scan_d = {
        count_next,
        rd_ptr_next,
        wr_ptr_next
    };

    assign {
        count,
        rd_ptr,
        wr_ptr
    } = scan_q;

    genvar i;
    generate
        for (i = 0; i < SCAN_LENGTH; i = i + 1) begin : GEN_SCAN

            scan_dff #(
                .RESET_VALUE(1'b0)
            ) u_scan_dff (
                .clk     (clk),
                .rst     (rst),
                .scan_en (scan_en),
                .d_in    (scan_d[i]),
                .scan_in (scan_link[i]),
                .q       (scan_q[i])
            );

            assign scan_link[i+1] = scan_q[i];
        end
    endgenerate

    assign scan_link[0] = scan_in;
    assign scan_out    = scan_link[SCAN_LENGTH];

endmodule