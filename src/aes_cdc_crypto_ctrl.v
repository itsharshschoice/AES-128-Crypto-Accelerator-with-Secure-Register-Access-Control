module aes_cdc_crypto_ctrl (
    input wire         crypto_clk,
    input wire         crypto_rst_n,
    input wire [255:0] cmd_fifo_rdata,
    input wire         cmd_fifo_empty,
    output reg         cmd_fifo_rd_en,
    output reg         aes_start,
    output reg [127:0] aes_key,
    output reg [127:0] aes_plaintext,
    input wire [127:0] aes_ciphertext,
    input wire         aes_done,
    output reg [127:0] resp_fifo_wdata,
    output reg         resp_fifo_wr_en,
    input wire         resp_fifo_full,
    input wire         zeroize
);
    localparam STATE_IDLE=3'd0, STATE_READ_CMD=3'd1, STATE_WAIT_CMD=3'd2,
               STATE_LOAD_CMD=3'd3, STATE_START_AES=3'd4, STATE_WAIT_AES=3'd5,
               STATE_CAPTURE=3'd6, STATE_WRITE_RESP=3'd7;
    reg [2:0] state, state_next;


    always @(*) begin
    if (zeroize) begin
        state_next = STATE_IDLE;
    end else begin
        case (state)
            STATE_IDLE: begin
                if (!cmd_fifo_empty)
                    state_next = STATE_READ_CMD;
                else
                    state_next = STATE_IDLE;
            end

            STATE_READ_CMD: begin
                state_next = STATE_WAIT_CMD;
            end

            STATE_WAIT_CMD: begin
                state_next = STATE_LOAD_CMD;
            end

            STATE_LOAD_CMD: begin
                state_next = STATE_START_AES;
            end

            STATE_START_AES: begin
                state_next = STATE_WAIT_AES;
            end

            STATE_WAIT_AES: begin
                if (aes_done)
                    state_next = STATE_CAPTURE;
                else
                    state_next = STATE_WAIT_AES;
            end

            STATE_CAPTURE: begin
                state_next = STATE_WRITE_RESP;
            end

            STATE_WRITE_RESP: begin
                if (!resp_fifo_full)
                    state_next = STATE_IDLE;
                else
                    state_next = STATE_WRITE_RESP;
            end

            default: begin
                state_next = STATE_IDLE;
            end
        endcase
    end
end

    always @(posedge crypto_clk or negedge crypto_rst_n) begin
        if (!crypto_rst_n) begin
            state <= STATE_IDLE;
            cmd_fifo_rd_en <= 1'b0;
            aes_start <= 1'b0;
            aes_key <= 128'h0;
            aes_plaintext <= 128'h0;
            resp_fifo_wdata <= 128'h0;
            resp_fifo_wr_en <= 1'b0;
        end else begin
            state <= state_next;
            cmd_fifo_rd_en <= 1'b0;
            aes_start <= 1'b0;
            resp_fifo_wr_en <= 1'b0;
            if (zeroize) begin
                aes_key <= 128'h0;
                aes_plaintext <= 128'h0;
                resp_fifo_wdata <= 128'h0;
            end else begin
                if (state == STATE_READ_CMD) cmd_fifo_rd_en <= 1'b1;
                if (state == STATE_LOAD_CMD) begin
                    aes_key <= cmd_fifo_rdata[255:128];
                    aes_plaintext <= cmd_fifo_rdata[127:0];
                end
                if (state == STATE_START_AES) aes_start <= 1'b1;
                if (state == STATE_CAPTURE) resp_fifo_wdata <= aes_ciphertext;
                if ((state == STATE_WRITE_RESP) && !resp_fifo_full)
                    resp_fifo_wr_en <= 1'b1;
            end
        end
    end
endmodule
