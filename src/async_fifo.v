module async_fifo #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 2
)(
    input wire                     wr_clk,
    input wire                     wr_rst_n,
    input wire                     wr_en,
    input wire [DATA_WIDTH-1:0]    wr_data,
    input wire                     wr_zeroize,
    output wire                    full,
    input wire                     rd_clk,
    input wire                     rd_rst_n,
    input wire                     rd_en,
    input wire                     rd_zeroize,
    output reg [DATA_WIDTH-1:0]    rd_data,
    output wire                    empty
);
    localparam PTR_WIDTH = ADDR_WIDTH + 1;
    localparam FIFO_DEPTH = (1 << ADDR_WIDTH);
    reg [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];
    reg [PTR_WIDTH-1:0] wr_ptr_bin, rd_ptr_bin;
    reg [PTR_WIDTH-1:0] wr_ptr_bin_next, rd_ptr_bin_next;
    reg [PTR_WIDTH-1:0] wr_ptr_gray, rd_ptr_gray;
    reg [PTR_WIDTH-1:0] wr_ptr_gray_next, rd_ptr_gray_next;
    reg [PTR_WIDTH-1:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;
    reg [PTR_WIDTH-1:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;
    reg full_reg, empty_reg;
    integer i;

    assign full = full_reg;
    assign empty = empty_reg;

    always @(*) begin
        wr_ptr_bin_next = wr_ptr_bin;
        if (wr_en && !full_reg) wr_ptr_bin_next = wr_ptr_bin + 1'b1;
        wr_ptr_gray_next = wr_ptr_bin_next ^ (wr_ptr_bin_next >> 1);
    end

    always @(*) begin
        rd_ptr_bin_next = rd_ptr_bin;
        if (rd_en && !empty_reg) rd_ptr_bin_next = rd_ptr_bin + 1'b1;
        rd_ptr_gray_next = rd_ptr_bin_next ^ (rd_ptr_bin_next >> 1);
    end

    wire [PTR_WIDTH-1:0] full_compare;
    wire full_next;
    wire empty_next;
    assign full_compare = rd_ptr_gray_sync2 ^ {2'b11,{(PTR_WIDTH-2){1'b0}}};
    assign full_next = (wr_ptr_gray_next == full_compare);
    assign empty_next = (rd_ptr_gray_next == wr_ptr_gray_sync2);

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr_bin <= 0;
            wr_ptr_gray <= 0;
            full_reg <= 1'b0;
            for (i=0; i<FIFO_DEPTH; i=i+1) mem[i] <= {DATA_WIDTH{1'b0}};
        end else if (wr_zeroize) begin
            wr_ptr_bin <= 0;
            wr_ptr_gray <= 0;
            full_reg <= 1'b0;
            for (i=0; i<FIFO_DEPTH; i=i+1) mem[i] <= {DATA_WIDTH{1'b0}};
        end else begin
            wr_ptr_bin <= wr_ptr_bin_next;
            wr_ptr_gray <= wr_ptr_gray_next;
            full_reg <= full_next;
            if (wr_en && !full_reg)
                mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
        end
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr_bin <= 0;
            rd_ptr_gray <= 0;
            empty_reg <= 1'b1;
            rd_data <= {DATA_WIDTH{1'b0}};
        end else if (rd_zeroize) begin
            rd_ptr_bin <= 0;
            rd_ptr_gray <= 0;
            empty_reg <= 1'b1;
            rd_data <= {DATA_WIDTH{1'b0}};
        end else begin
            rd_ptr_bin <= rd_ptr_bin_next;
            rd_ptr_gray <= rd_ptr_gray_next;
            empty_reg <= empty_next;
            if (rd_en && !empty_reg)
                rd_data <= mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
        end
    end

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rd_ptr_gray_sync1 <= 0;
            rd_ptr_gray_sync2 <= 0;
        end else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_ptr_gray_sync1 <= 0;
            wr_ptr_gray_sync2 <= 0;
        end else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end
endmodule
