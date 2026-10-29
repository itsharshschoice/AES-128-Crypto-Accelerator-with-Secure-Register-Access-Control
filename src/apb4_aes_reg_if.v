module apb4_aes_reg_if #(
    parameter ADDR_WIDTH = 6,
    parameter DATA_WIDTH = 32
)(
    input wire                     pclk,
    input wire                     presetn,
    input wire [ADDR_WIDTH-1:0]    paddr,
    input wire                     psel,
    input wire                     penable,
    input wire                     pwrite,
    input wire [DATA_WIDTH-1:0]    pwdata,
    input wire [DATA_WIDTH/8-1:0]  pstrb,
    input wire                     pprot_privileged,
    output reg  [DATA_WIDTH-1:0]   prdata,
    output wire                    pready,
    output wire                    pslverr,

    output wire                    reg_wr_en,
    output wire [3:0]              reg_wr_addr,
    output wire [DATA_WIDTH-1:0]   reg_wr_data,
    output wire [DATA_WIDTH/8-1:0] reg_wr_strb,
    output wire                    reg_rd_en,
    output wire [3:0]              reg_rd_addr,
    input wire [DATA_WIDTH-1:0]    reg_rd_data,
    input wire                     key_lock,
    input wire                     cmd_fifo_full,
    output wire                    security_violation_set
);
    wire apb_access = psel && penable;
    wire apb_write = apb_access && pwrite;
    wire apb_read = apb_access && !pwrite;
    wire addr_aligned = (paddr[1:0] == 2'b00);
    wire valid_address = (paddr[5:2] <= 4'd14) && addr_aligned;
    wire security_register = (paddr[5:2] <= 4'd3) || (paddr[5:2] == 4'd14);
    wire nonprivileged_security_access = valid_address && security_register && !pprot_privileged;
    wire write_permission_error = pwrite && valid_address &&
        (((paddr[5:2] >= 4'd8) && (paddr[5:2] <= 4'd11)) ||
         (paddr[5:2] == 4'd13) ||
         ((paddr[5:2] <= 4'd3) && key_lock));
    wire start_full_error = pwrite && valid_address &&
        (paddr[5:2] == 4'd12) && pstrb[0] && pwdata[0] && cmd_fifo_full;

    assign reg_wr_addr = paddr[5:2];
    assign reg_rd_addr = paddr[5:2];
    assign pslverr = apb_access && (!valid_address || nonprivileged_security_access ||
                                    write_permission_error || start_full_error);
    assign pready = psel && penable;
    assign reg_wr_en = apb_write && !pslverr;
    assign reg_wr_data = pwdata;
    assign reg_wr_strb = pstrb;
    assign reg_rd_en = apb_read && valid_address && !pslverr;
    assign security_violation_set = psel && !penable && nonprivileged_security_access;

    always @(*) begin
        prdata = reg_rd_en ? reg_rd_data : {DATA_WIDTH{1'b0}};
    end
endmodule
