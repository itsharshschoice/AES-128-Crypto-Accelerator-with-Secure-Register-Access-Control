module aes128_cdc_top #(
    parameter APB_ADDR_WIDTH = 6,
    parameter APB_DATA_WIDTH = 32,
    parameter CMD_FIFO_ADDR_WIDTH = 2,
    parameter RESP_FIFO_ADDR_WIDTH = 2
)(
    input wire                         pclk,
    input wire                         presetn,
    input wire [APB_ADDR_WIDTH-1:0]    paddr,
    input wire                         psel,
    input wire                         penable,
    input wire                         pwrite,
    input wire [APB_DATA_WIDTH-1:0]    pwdata,
    input wire [APB_DATA_WIDTH/8-1:0]  pstrb,
    input wire [2:0]                   pprot,
    output wire [APB_DATA_WIDTH-1:0]   prdata,
    output wire                        pready,
    output wire                        pslverr,
    input wire                         crypto_clk,
    input wire                         crypto_rst_n
);
    wire reg_wr_en;
    wire [3:0] reg_wr_addr;
    wire [APB_DATA_WIDTH-1:0] reg_wr_data;
    wire [APB_DATA_WIDTH/8-1:0] reg_wr_strb;
    wire reg_rd_en;
    wire [3:0] reg_rd_addr;
    wire [APB_DATA_WIDTH-1:0] reg_rd_data;
    wire key_lock;
    wire security_violation_set;

    wire [255:0] cmd_fifo_wr_data, cmd_fifo_rd_data;
    wire cmd_fifo_wr_en, cmd_fifo_rd_en, cmd_fifo_full, cmd_fifo_empty;
    wire [127:0] resp_fifo_wr_data, resp_fifo_rd_data;
    wire resp_fifo_wr_en, resp_fifo_rd_en, resp_fifo_full, resp_fifo_empty;
    wire aes_start, aes_done;
    wire [127:0] aes_key, aes_plaintext, aes_ciphertext;
    wire zeroize_pulse, zeroize_toggle;
    reg zeroize_sync1, zeroize_sync2, zeroize_sync2_d;
    wire crypto_zeroize;

    assign crypto_zeroize = zeroize_sync2 ^ zeroize_sync2_d;

    always @(posedge crypto_clk or negedge crypto_rst_n) begin
        if (!crypto_rst_n) begin
            zeroize_sync1 <= 1'b0;
            zeroize_sync2 <= 1'b0;
            zeroize_sync2_d <= 1'b0;
        end else begin
            zeroize_sync1 <= zeroize_toggle;
            zeroize_sync2 <= zeroize_sync1;
            zeroize_sync2_d <= zeroize_sync2;
        end
    end

    apb4_aes_reg_if #(.ADDR_WIDTH(APB_ADDR_WIDTH), .DATA_WIDTH(APB_DATA_WIDTH)) apb_regs (
        .pclk(pclk), .presetn(presetn), .paddr(paddr), .psel(psel), .penable(penable),
        .pwrite(pwrite), .pwdata(pwdata), .pstrb(pstrb),
        .pprot_privileged(pprot[0]),
        .prdata(prdata), .pready(pready), .pslverr(pslverr),
        .reg_wr_en(reg_wr_en), .reg_wr_addr(reg_wr_addr), .reg_wr_data(reg_wr_data),
        .reg_wr_strb(reg_wr_strb), .reg_rd_en(reg_rd_en), .reg_rd_addr(reg_rd_addr),
        .reg_rd_data(reg_rd_data), .key_lock(key_lock), .cmd_fifo_full(cmd_fifo_full),
        .security_violation_set(security_violation_set)
    );

    aes_apb_reg_bank #(.DATA_WIDTH(APB_DATA_WIDTH)) reg_bank (
        .pclk(pclk), .presetn(presetn),
        .reg_wr_en(reg_wr_en), .reg_wr_addr(reg_wr_addr), .reg_wr_data(reg_wr_data),
        .reg_wr_strb(reg_wr_strb), .reg_rd_en(reg_rd_en), .reg_rd_addr(reg_rd_addr),
        .reg_rd_data(reg_rd_data), .security_violation_set(security_violation_set),
        .key_lock(key_lock), .cmd_fifo_wr_data(cmd_fifo_wr_data),
        .cmd_fifo_wr_en(cmd_fifo_wr_en), .cmd_fifo_full(cmd_fifo_full),
        .resp_fifo_rd_data(resp_fifo_rd_data), .resp_fifo_empty(resp_fifo_empty),
        .resp_fifo_rd_en(resp_fifo_rd_en), .zeroize_pulse(zeroize_pulse),
        .zeroize_toggle(zeroize_toggle)
    );

    async_fifo #(.DATA_WIDTH(256), .ADDR_WIDTH(CMD_FIFO_ADDR_WIDTH)) command_fifo (
        .wr_clk(pclk), .wr_rst_n(presetn), .wr_en(cmd_fifo_wr_en), .wr_data(cmd_fifo_wr_data),
        .wr_zeroize(zeroize_pulse), .full(cmd_fifo_full),
        .rd_clk(crypto_clk), .rd_rst_n(crypto_rst_n), .rd_en(cmd_fifo_rd_en),
        .rd_zeroize(crypto_zeroize), .rd_data(cmd_fifo_rd_data), .empty(cmd_fifo_empty)
    );

    aes_cdc_crypto_ctrl crypto_controller (
        .crypto_clk(crypto_clk), .crypto_rst_n(crypto_rst_n),
        .cmd_fifo_rdata(cmd_fifo_rd_data), .cmd_fifo_empty(cmd_fifo_empty),
        .cmd_fifo_rd_en(cmd_fifo_rd_en), .aes_start(aes_start), .aes_key(aes_key),
        .aes_plaintext(aes_plaintext), .aes_ciphertext(aes_ciphertext), .aes_done(aes_done),
        .resp_fifo_wdata(resp_fifo_wr_data), .resp_fifo_wr_en(resp_fifo_wr_en),
        .resp_fifo_full(resp_fifo_full), .zeroize(crypto_zeroize)
    );

    aes128_core aes_core (
        .clk(crypto_clk), .rst_n(crypto_rst_n), .start(aes_start),
        .plaintext(aes_plaintext), .key(aes_key), .zeroize(crypto_zeroize),
        .ciphertext(aes_ciphertext), .done(aes_done)
    );

    async_fifo #(.DATA_WIDTH(128), .ADDR_WIDTH(RESP_FIFO_ADDR_WIDTH)) response_fifo (
        .wr_clk(crypto_clk), .wr_rst_n(crypto_rst_n), .wr_en(resp_fifo_wr_en),
        .wr_data(resp_fifo_wr_data), .wr_zeroize(crypto_zeroize), .full(resp_fifo_full),
        .rd_clk(pclk), .rd_rst_n(presetn), .rd_en(resp_fifo_rd_en),
        .rd_zeroize(zeroize_pulse), .rd_data(resp_fifo_rd_data), .empty(resp_fifo_empty)
    );
endmodule
