module mixcolumns (
    input  wire [127:0] din,
    output wire [127:0] dout
);

    function automatic [7:0] xtime;
        input [7:0] b;
        begin
            xtime = b[7] ? ({b[6:0],1'b0} ^ 8'h1b) : {b[6:0],1'b0};
        end
    endfunction

    function automatic [7:0] gmul2; 
        input [7:0] b; 
        begin 
            gmul2 = xtime(b); 
        end 
    endfunction
    
    function automatic [7:0] gmul3; 
        input [7:0] b; 
        begin 
            gmul3 = xtime(b) ^ b; 
        end 
    endfunction

    genvar c;
    generate
        for (c = 0; c < 4; c = c + 1) begin : gen_col
            wire [7:0] a0 = din[127-8*(4*c+0) -: 8]; // s0,c
            wire [7:0] a1 = din[127-8*(4*c+1) -: 8]; // s1,c
            wire [7:0] a2 = din[127-8*(4*c+2) -: 8]; // s2,c
            wire [7:0] a3 = din[127-8*(4*c+3) -: 8]; // s3,c

            assign dout[127-8*(4*c+0) -: 8] = gmul2(a0) ^ gmul3(a1) ^ a2        ^ a3;
            assign dout[127-8*(4*c+1) -: 8] = a0        ^ gmul2(a1) ^ gmul3(a2) ^ a3;
            assign dout[127-8*(4*c+2) -: 8] = a0        ^ a1        ^ gmul2(a2) ^ gmul3(a3);
            assign dout[127-8*(4*c+3) -: 8] = gmul3(a0) ^ a1        ^ a2        ^ gmul2(a3);
        end
    endgenerate

endmodule