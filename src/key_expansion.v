module key_expansion (
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire advance, 
    input  wire [127:0] key,
    input  wire zeroize,
    output reg [127:0] round_key // Present round key
);

    function automatic [7:0] round_constant;
        input [3:0] index;
        begin
            case (index)
                4'd1:  round_constant = 8'h01;
                4'd2:  round_constant = 8'h02;
                4'd3:  round_constant = 8'h04;
                4'd4:  round_constant = 8'h08;
                4'd5:  round_constant = 8'h10;
                4'd6:  round_constant = 8'h20;
                4'd7:  round_constant = 8'h40;
                4'd8:  round_constant = 8'h80;
                4'd9:  round_constant = 8'h1b;
                4'd10: round_constant = 8'h36;
                default: round_constant = 8'h00;
            endcase
        end

    endfunction

    reg [3:0] next_round_index;

    wire [127:0] base = start ? key : round_key;

    wire [31:0] w0 = base[127:96];
    wire [31:0] w1 = base[95:64];
    wire [31:0] w2 = base[63:32];
    wire [31:0] w3 = base[31:0];
   
   // ROTWORD()
    wire [31:0] rotword = {w3[23:0], w3[31:24]};
   
   //SUBWORD()
    wire [7:0] sub_b0, sub_b1, sub_b2, sub_b3;
    sbox sbox0 (.din(rotword[31:24]), .dout(sub_b0));
    sbox sbox1 (.din(rotword[23:16]), .dout(sub_b1));
    sbox sbox2 (.din(rotword[15:8]),  .dout(sub_b2));
    sbox sbox3 (.din(rotword[7:0]),   .dout(sub_b3));
    wire [31:0] subword = {sub_b0, sub_b1, sub_b2, sub_b3};

    // XOR with round constant 
    wire [3:0] rcon_index = start ? 4'd1 : next_round_index;
    wire [31:0] temp = subword ^ {round_constant(rcon_index), 24'h000000};
   
   // Next round key
    wire [31:0] w0_next = w0 ^ temp;
    wire [31:0] w1_next = w1 ^ w0_next;
    wire [31:0] w2_next = w2 ^ w1_next;
    wire [31:0] w3_next = w3 ^ w2_next;
    wire [127:0] key_next = {w0_next, w1_next, w2_next, w3_next};


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            round_key  <= 128'h0;
            next_round_index <= 4'd1;
        end else if (zeroize) begin
            round_key  <= 128'h0;
            next_round_index <= 4'd1;
        end else if (start) begin
            round_key  <= key_next; 
            next_round_index <= 4'd2;
        end else if (advance) begin
            round_key  <= key_next; 
            next_round_index <= next_round_index + 4'd1;
        end
    end

endmodule
