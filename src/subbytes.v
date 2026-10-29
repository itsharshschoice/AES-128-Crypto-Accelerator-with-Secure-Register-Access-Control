module subbytes (
    input  wire [127:0] din,
    output wire [127:0] dout
);

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : gen_sbox
        // byte 0 is MSB and byte 15 is LSB
            sbox u_sbox (
                .din  (din [127-8*i -: 8]),
                .dout (dout[127-8*i -: 8])
            );
        end
    endgenerate

endmodule