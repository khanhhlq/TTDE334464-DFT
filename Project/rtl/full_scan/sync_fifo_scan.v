`timescale 1ns / 1ps

module sync_fifo_scan #(
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

    localparam MEM_BITS = DATA_WIDTH * DEPTH;

    localparam SCAN_LENGTH =
        MEM_BITS + 2 * PTR_WIDTH + COUNT_WIDTH;

    wire [PTR_WIDTH-1:0]   wr_ptr;
    wire [PTR_WIDTH-1:0]   rd_ptr;
    wire [COUNT_WIDTH-1:0] count;

    reg [PTR_WIDTH-1:0]   wr_ptr_next;
    reg [PTR_WIDTH-1:0]   rd_ptr_next;
    reg [COUNT_WIDTH-1:0] count_next;

    wire [MEM_BITS-1:0] mem_q;
    wire [MEM_BITS-1:0] mem_d;

    wire write_ok;
    wire read_ok;

    wire [SCAN_LENGTH-1:0] scan_d;
    wire [SCAN_LENGTH-1:0] scan_q;
    wire [SCAN_LENGTH:0]   scan_link;

    assign write_ok = wr_en && !full;
    assign read_ok  = rd_en && !empty;

    assign full  = (count == DEPTH);
    assign empty = (count == 0);

    assign rd_data = mem_q[rd_ptr*DATA_WIDTH +: DATA_WIDTH];

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

    genvar word_idx;
    generate
        for (word_idx = 0; word_idx < DEPTH;
             word_idx = word_idx + 1) begin : GEN_MEM_NEXT

            assign mem_d[word_idx*DATA_WIDTH +: DATA_WIDTH] =
                (!rst && write_ok && (wr_ptr == word_idx))
                ? wr_data
                : mem_q[word_idx*DATA_WIDTH +: DATA_WIDTH];

        end
    endgenerate

    assign scan_d = {
        count_next,
        rd_ptr_next,
        wr_ptr_next,
        mem_d
    };

    assign {
        count,
        rd_ptr,
        wr_ptr,
        mem_q
    } = scan_q;

    assign scan_link[0] = scan_in;
    assign scan_out    = scan_link[SCAN_LENGTH];

    genvar i;
    generate
        for (i = 0; i < SCAN_LENGTH; i = i + 1) begin : GEN_SCAN

            if (i < MEM_BITS) begin : GEN_MEM_FF
                reg mem_bit_q;

                always @(posedge clk) begin
                    if (scan_en)
                        mem_bit_q <= scan_link[i];
                    else
                        mem_bit_q <= scan_d[i];
                end

                assign scan_q[i] = mem_bit_q;
            end
            else begin : GEN_CTRL_FF
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
            end

            assign scan_link[i+1] = scan_q[i];
        end
    endgenerate

endmodule