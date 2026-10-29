module aes128_core (
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire [127:0] plaintext,
    input  wire [127:0] key,
    input  wire zeroize,
    output reg [127:0] ciphertext,
    output reg done
);

    // AES core control states.
    localparam IDLE = 2'd0, RUN = 2'd1, DONE = 2'd2;
    reg [1:0] PS, NS;

    // Stores the current AES round and intermediate state.
    reg [3:0] round_cnt;
    reg [127:0] round_in;

    // Next-state values for the sequential registers.
    reg [3:0] round_cnt_next;
    reg [127:0] round_in_next;
    reg [127:0] ciphertext_next;
    reg done_next;


    // Start the key expansion with a new AES transaction.
    // After that, generate the next round key as the rounds advance.
    wire start_key = (PS == IDLE) && start;
    wire advance_key = (PS == RUN) && (round_cnt != 4'd10);
    wire [127:0] round_key;

    key_expansion key_exp_otf (
        .clk(clk), 
        .rst_n(rst_n), 
        .start(start_key), 
        .advance(advance_key),
        .key(key), 
        .zeroize(zeroize), 
        .round_key(round_key));


    // MixColumns is used in Rounds 1-9 and skipped in Round 10.
    wire mix_en = (round_cnt != 4'd10);
    wire [127:0] round_out;
    
    round_datapath round_datapath (
        .round_in(round_in),
        .round_key(round_key),
        .mix_en(mix_en),
        .round_out(round_out)
    );


    // Store the current FSM state, AES state, round count and output.
    // Zeroize clears all core state and returns the FSM to IDLE.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            PS <= IDLE;
            round_cnt <= 4'd0;
            round_in <= 128'h0;
            ciphertext <= 128'h0;
            done <= 1'b0;
        end else if (zeroize) begin
            PS <= IDLE;
            round_cnt <= 4'd0;
            round_in <= 128'h0;
            ciphertext <= 128'h0;
            done <= 1'b0;
        end else begin
            PS <= NS;
            round_cnt <= round_cnt_next;
            round_in <= round_in_next;
            ciphertext <= ciphertext_next;
            done <= done_next;
        end
    end


    // Combinational next-state and datapath control logic.
    always @(*) begin
        NS = PS;
        round_cnt_next = round_cnt;
        round_in_next = round_in;
        ciphertext_next = ciphertext;
        done_next = done;

        case (PS)

            IDLE: begin
                done_next = 1'b0;

                if (start) begin
                    // Initial AddRoundKey is done before Round 1.
                    round_in_next = plaintext ^ key;
                    round_cnt_next = 4'd1;
                    NS = RUN;
                end
            end

            RUN: begin
                // Store the result of the current AES round.
                round_in_next = round_out;

                if (round_cnt == 4'd10) begin
                    // Round 10 is the final round, so capture the ciphertext.
                    ciphertext_next = round_out;
                    done_next = 1'b1;
                    NS = DONE;
                end else begin
                    round_cnt_next = round_cnt + 4'd1;
                end
            end

            DONE: begin
                // Return to IDLE after reporting completion.
                NS = IDLE;
            end

            default: NS = IDLE;

        endcase
    end

endmodule