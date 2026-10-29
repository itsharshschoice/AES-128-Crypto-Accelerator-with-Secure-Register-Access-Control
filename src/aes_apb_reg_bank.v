module aes_apb_reg_bank #(
    parameter DATA_WIDTH = 32,
    parameter OUTSTANDING_WIDTH = 3
)(
    input  wire                     pclk,
    input  wire                     presetn,

    // Generic 32-bit register interface from APB slave.
    input  wire                     reg_wr_en,
    input  wire [3:0]               reg_wr_addr,
    input  wire [DATA_WIDTH-1:0]    reg_wr_data,
    input  wire [DATA_WIDTH/8-1:0]  reg_wr_strb,
    input  wire                     reg_rd_en,
    input  wire [3:0]               reg_rd_addr,
    output reg  [DATA_WIDTH-1:0]    reg_rd_data,

    // Access-filter feedback.
    input  wire                     security_violation_set,
    output wire                     key_lock,

    // Command FIFO: PCLK -> crypto_clk.
    output wire [255:0]             cmd_fifo_wr_data,
    output reg                      cmd_fifo_wr_en,
    input  wire                     cmd_fifo_full,

    // Response FIFO: crypto_clk -> PCLK.
    input  wire [127:0]             resp_fifo_rd_data,
    input  wire                     resp_fifo_empty,
    output reg                      resp_fifo_rd_en,

    // Software zeroize event.
    output wire                     zeroize_pulse,
    output reg                      zeroize_toggle
);

    // =====================================================================
    // APB-visible register storage
    // =====================================================================
    reg [31:0] key0_reg, key1_reg, key2_reg, key3_reg;
    reg [31:0] pt0_reg,  pt1_reg,  pt2_reg,  pt3_reg;
    reg [31:0] ct0_reg,  ct1_reg,  ct2_reg,  ct3_reg;

    reg done_reg;
    reg busy_reg;
    reg key_lock_reg;
    reg security_violation_reg;

    // =====================================================================
    // Response/transaction state
    // =====================================================================
    reg [OUTSTANDING_WIDTH-1:0] outstanding_count;
    reg ct_valid_reg;
    reg [3:0] ct_read_mask;
    reg ct_consume_pending;

    localparam RESP_IDLE    = 2'd0;
    localparam RESP_READ    = 2'd1;
    localparam RESP_WAIT    = 2'd2;
    localparam RESP_CAPTURE = 2'd3;

    reg [1:0] resp_state;
    reg [1:0] resp_state_next;

    // =====================================================================
    // Next-state signals
    // Every sequential register has exactly one procedural owner below.
    // =====================================================================
    reg [31:0] key0_next, key1_next, key2_next, key3_next;
    reg [31:0] pt0_next,  pt1_next,  pt2_next,  pt3_next;
    reg [31:0] ct0_next,  ct1_next,  ct2_next,  ct3_next;

    reg done_next;
    reg busy_next;
    reg key_lock_next;
    reg security_violation_next;

    reg [OUTSTANDING_WIDTH-1:0] outstanding_count_next;
    reg ct_valid_next;
    reg [3:0] ct_read_mask_next;
    reg ct_consume_pending_next;

    reg cmd_fifo_wr_en_next;
    reg resp_fifo_rd_en_next;
    reg zeroize_toggle_next;

    // =====================================================================
    // Events
    // =====================================================================
    wire start_accept;
    wire zeroize_cmd;
    wire ct_read_access;
    wire response_capture_event;

    assign key_lock = key_lock_reg;

    assign cmd_fifo_wr_data = {
        key3_reg, key2_reg, key1_reg, key0_reg,
        pt3_reg,  pt2_reg,  pt1_reg,  pt0_reg
    };

    // CTRL register: bit 0 = START.
    assign start_accept =
        reg_wr_en &&
        (reg_wr_addr == 4'd12) &&
        reg_wr_strb[0] &&
        reg_wr_data[0] &&
        !cmd_fifo_full;

    // SECURITY CONTROL register: bit 1 = ZEROIZE.
    assign zeroize_cmd =
        reg_wr_en &&
        (reg_wr_addr == 4'd14) &&
        reg_wr_strb[0] &&
        reg_wr_data[1];

    assign zeroize_pulse = zeroize_cmd;

    assign ct_read_access =
        reg_rd_en && ct_valid_reg &&
        (reg_rd_addr >= 4'd8) &&
        (reg_rd_addr <= 4'd11);

    // The response data is captured in RESP_CAPTURE after the FIFO read
    // request has had time to propagate through the asynchronous FIFO.
    assign response_capture_event =
        (resp_state == RESP_CAPTURE) &&
        (outstanding_count != 0) &&
        !ct_valid_reg;

    // =====================================================================
    // APB read mux
    // =====================================================================
    always @(*) begin
        case (reg_rd_en ? reg_rd_addr : 4'hf)
            4'd0, 4'd1, 4'd2, 4'd3,
            4'd4, 4'd5, 4'd6, 4'd7,
            4'd12: reg_rd_data = 32'h00000000;

            4'd8:  reg_rd_data = ct_valid_reg ? ct0_reg : 32'h00000000;
            4'd9:  reg_rd_data = ct_valid_reg ? ct1_reg : 32'h00000000;
            4'd10: reg_rd_data = ct_valid_reg ? ct2_reg : 32'h00000000;
            4'd11: reg_rd_data = ct_valid_reg ? ct3_reg : 32'h00000000;

            4'd13: reg_rd_data = {29'h0, security_violation_reg, busy_reg, done_reg};
            4'd14: reg_rd_data = {31'h0, key_lock_reg};

            default: reg_rd_data = 32'h00000000;
        endcase
    end

    // =====================================================================
    // Write-data helper.  A single assignment avoids multiple procedural
    // assignments to individual bits of a next-state signal.
    // =====================================================================
    function automatic [31:0] merge_wstrb;
        input [31:0] old_data;
        input [31:0] wr_data;
        input [3:0]  wr_strb;
        reg [31:0] mask;
        begin
            mask = { {8{wr_strb[3]}}, {8{wr_strb[2]}},
                     {8{wr_strb[1]}}, {8{wr_strb[0]}} };
            merge_wstrb = (old_data & ~mask) | (wr_data & mask);
        end
    endfunction

    // =====================================================================
    // Register next-state blocks.
    // Each next-state signal has one procedural assignment in one block.
    // =====================================================================
    always @(*) begin
        key0_next = zeroize_cmd ? 32'h0 :
                    ((reg_wr_en && (reg_wr_addr == 4'd0)) ?
                     merge_wstrb(key0_reg, reg_wr_data, reg_wr_strb) : key0_reg);
    end

    always @(*) begin
        key1_next = zeroize_cmd ? 32'h0 :
                    ((reg_wr_en && (reg_wr_addr == 4'd1)) ?
                     merge_wstrb(key1_reg, reg_wr_data, reg_wr_strb) : key1_reg);
    end

    always @(*) begin
        key2_next = zeroize_cmd ? 32'h0 :
                    ((reg_wr_en && (reg_wr_addr == 4'd2)) ?
                     merge_wstrb(key2_reg, reg_wr_data, reg_wr_strb) : key2_reg);
    end

    always @(*) begin
        key3_next = zeroize_cmd ? 32'h0 :
                    ((reg_wr_en && (reg_wr_addr == 4'd3)) ?
                     merge_wstrb(key3_reg, reg_wr_data, reg_wr_strb) : key3_reg);
    end

    always @(*) begin
        pt0_next = zeroize_cmd ? 32'h0 :
                   ((reg_wr_en && (reg_wr_addr == 4'd4)) ?
                    merge_wstrb(pt0_reg, reg_wr_data, reg_wr_strb) : pt0_reg);
    end

    always @(*) begin
        pt1_next = zeroize_cmd ? 32'h0 :
                   ((reg_wr_en && (reg_wr_addr == 4'd5)) ?
                    merge_wstrb(pt1_reg, reg_wr_data, reg_wr_strb) : pt1_reg);
    end

    always @(*) begin
        pt2_next = zeroize_cmd ? 32'h0 :
                   ((reg_wr_en && (reg_wr_addr == 4'd6)) ?
                    merge_wstrb(pt2_reg, reg_wr_data, reg_wr_strb) : pt2_reg);
    end

    always @(*) begin
        pt3_next = zeroize_cmd ? 32'h0 :
                   ((reg_wr_en && (reg_wr_addr == 4'd7)) ?
                    merge_wstrb(pt3_reg, reg_wr_data, reg_wr_strb) : pt3_reg);
    end

    // Ciphertext registers are loaded only by the response FIFO capture.
    always @(*) begin
        ct0_next = zeroize_cmd ? 32'h0 :
                   (response_capture_event ? resp_fifo_rd_data[31:0] : ct0_reg);
    end

    always @(*) begin
        ct1_next = zeroize_cmd ? 32'h0 :
                   (response_capture_event ? resp_fifo_rd_data[63:32] : ct1_reg);
    end

    always @(*) begin
        ct2_next = zeroize_cmd ? 32'h0 :
                   (response_capture_event ? resp_fifo_rd_data[95:64] : ct2_reg);
    end

    always @(*) begin
        ct3_next = zeroize_cmd ? 32'h0 :
                   (response_capture_event ? resp_fifo_rd_data[127:96] : ct3_reg);
    end

    // Sticky security violation.
    always @(*) begin
        security_violation_next = security_violation_set ? 1'b1 :
                                   security_violation_reg;
    end

    // Sticky key lock. Zeroize deliberately does not clear the lock.
    always @(*) begin
        key_lock_next = (reg_wr_en && (reg_wr_addr == 4'd14) &&
                         reg_wr_strb[0] && reg_wr_data[0]) ? 1'b1 :
                        key_lock_reg;
    end

    // Command FIFO write strobe is a one-cycle event.
    always @(*) begin
        cmd_fifo_wr_en_next = (!zeroize_cmd && start_accept) ? 1'b1 : 1'b0;
    end

    // Response FIFO read strobe is generated only in RESP_READ.
    always @(*) begin
        resp_fifo_rd_en_next = (!zeroize_cmd && (resp_state == RESP_READ)) ?
                                1'b1 : 1'b0;
    end

    // Response FSM next state.  This is deliberately expressed as one
    // combinational assignment, eliminating multiple assignments to the
    // same next-state signal in one always block.
    always @(*) begin
        if (zeroize_cmd) begin
            resp_state_next = RESP_IDLE;
        end
        else if (ct_consume_pending) begin
            if (outstanding_count != 0)
                resp_state_next = !resp_fifo_empty ? RESP_READ : RESP_IDLE;
            else
                resp_state_next = RESP_IDLE;
        end
        else begin
            case (resp_state)
                RESP_IDLE: begin
                    resp_state_next = ((outstanding_count != 0) &&
                                       !ct_valid_reg &&
                                       !ct_consume_pending &&
                                       !resp_fifo_empty) ? RESP_READ : RESP_IDLE;
                end

                RESP_READ:    resp_state_next = RESP_WAIT;
                RESP_WAIT:   resp_state_next = RESP_CAPTURE;
                RESP_CAPTURE: resp_state_next = RESP_IDLE;
                default:      resp_state_next = RESP_IDLE;
            endcase
        end
    end

    // Outstanding transaction counter.
    always @(*) begin
        if (zeroize_cmd)
            outstanding_count_next = {OUTSTANDING_WIDTH{1'b0}};
        else if (start_accept && !response_capture_event)
            outstanding_count_next = outstanding_count + 1'b1;
        else if (!start_accept && response_capture_event)
            outstanding_count_next = outstanding_count - 1'b1;
        else
            outstanding_count_next = outstanding_count;
    end

    // Ciphertext valid flag.
    always @(*) begin
        if (zeroize_cmd)
            ct_valid_next = 1'b0;
        else if (ct_consume_pending)
            ct_valid_next = 1'b0;
        else if (response_capture_event)
            ct_valid_next = 1'b1;
        else
            ct_valid_next = ct_valid_reg;
    end

    // DONE status.
    always @(*) begin
        if (zeroize_cmd)
            done_next = 1'b0;
        else if (ct_consume_pending)
            done_next = 1'b0;
        else if (response_capture_event)
            done_next = 1'b1;
        else if (start_accept && !ct_valid_reg)
            done_next = 1'b0;
        else
            done_next = done_reg;
    end

    // BUSY status.  Response consumption has priority over a simultaneous
    // start, matching the original sequential priority.
    always @(*) begin
        if (zeroize_cmd)
            busy_next = 1'b0;
        else if (ct_consume_pending)
            busy_next = (outstanding_count != 0);
        else if (response_capture_event)
            busy_next = ((outstanding_count > 1) || start_accept);
        else if (start_accept)
            busy_next = 1'b1;
        else
            busy_next = busy_reg;
    end

    // Read-mask helper conditions.
    wire ct_read_last;
    assign ct_read_last =
        ct_read_access &&
        ((reg_rd_addr == 4'd8) ? (ct_read_mask[3] && ct_read_mask[2] && ct_read_mask[1]) :
         (reg_rd_addr == 4'd9) ? (ct_read_mask[3] && ct_read_mask[2] && ct_read_mask[0]) :
         (reg_rd_addr == 4'd10) ? (ct_read_mask[3] && ct_read_mask[1] && ct_read_mask[0]) :
         (reg_rd_addr == 4'd11) ? (ct_read_mask[2] && ct_read_mask[1] && ct_read_mask[0]) :
         1'b0);

    // Next ciphertext-read mask. Re-reading a word leaves the mask unchanged.
    always @(*) begin
        if (zeroize_cmd)
            ct_read_mask_next = 4'b0000;
        else if (ct_consume_pending)
            ct_read_mask_next = 4'b0000;
        else if (ct_read_access && !ct_read_last)
            case (reg_rd_addr)
                4'd8:  ct_read_mask_next = ct_read_mask | 4'b0001;
                4'd9:  ct_read_mask_next = ct_read_mask | 4'b0010;
                4'd10: ct_read_mask_next = ct_read_mask | 4'b0100;
                4'd11: ct_read_mask_next = ct_read_mask | 4'b1000;
                default: ct_read_mask_next = ct_read_mask;
            endcase
        else
            ct_read_mask_next = ct_read_mask;
    end

    // Once all four words have been accessed, request consumption on the
    // following cycle. This retains the original one-cycle consume behavior.
    always @(*) begin
        if (zeroize_cmd)
            ct_consume_pending_next = 1'b0;
        else if (ct_consume_pending)
            ct_consume_pending_next = 1'b0;
        else if (ct_read_last)
            ct_consume_pending_next = 1'b1;
        else
            ct_consume_pending_next = ct_consume_pending;
    end

    // Software zeroize is represented by a toggle crossing the CDC boundary.
    always @(*) begin
        zeroize_toggle_next = zeroize_cmd ? ~zeroize_toggle : zeroize_toggle;
    end

    // =====================================================================
    // Single sequential owner for every register.
    // =====================================================================
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            key0_reg <= 32'h00000000;
            key1_reg <= 32'h00000000;
            key2_reg <= 32'h00000000;
            key3_reg <= 32'h00000000;

            pt0_reg <= 32'h00000000;
            pt1_reg <= 32'h00000000;
            pt2_reg <= 32'h00000000;
            pt3_reg <= 32'h00000000;

            ct0_reg <= 32'h00000000;
            ct1_reg <= 32'h00000000;
            ct2_reg <= 32'h00000000;
            ct3_reg <= 32'h00000000;

            done_reg <= 1'b0;
            busy_reg <= 1'b0;
            key_lock_reg <= 1'b0;
            security_violation_reg <= 1'b0;

            outstanding_count <= {OUTSTANDING_WIDTH{1'b0}};
            ct_valid_reg <= 1'b0;
            ct_read_mask <= 4'b0000;
            ct_consume_pending <= 1'b0;

            resp_state <= RESP_IDLE;
            cmd_fifo_wr_en <= 1'b0;
            resp_fifo_rd_en <= 1'b0;
            zeroize_toggle <= 1'b0;
        end
        else begin
            key0_reg <= key0_next;
            key1_reg <= key1_next;
            key2_reg <= key2_next;
            key3_reg <= key3_next;

            pt0_reg <= pt0_next;
            pt1_reg <= pt1_next;
            pt2_reg <= pt2_next;
            pt3_reg <= pt3_next;

            ct0_reg <= ct0_next;
            ct1_reg <= ct1_next;
            ct2_reg <= ct2_next;
            ct3_reg <= ct3_next;

            done_reg <= done_next;
            busy_reg <= busy_next;
            key_lock_reg <= key_lock_next;
            security_violation_reg <= security_violation_next;

            outstanding_count <= outstanding_count_next;
            ct_valid_reg <= ct_valid_next;
            ct_read_mask <= ct_read_mask_next;
            ct_consume_pending <= ct_consume_pending_next;

            resp_state <= resp_state_next;
            cmd_fifo_wr_en <= cmd_fifo_wr_en_next;
            resp_fifo_rd_en <= resp_fifo_rd_en_next;
            zeroize_toggle <= zeroize_toggle_next;
        end
    end

endmodule
