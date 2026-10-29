module shiftrows (
    input  wire [127:0] din,
    output wire [127:0] dout
);

    genvar r, c;
    
    generate
        for (c = 0; c < 4; c = c + 1) begin : gen_col
            for (r = 0; r < 4; r = r + 1) begin : gen_row
                // dst byte index = r + 4c
                // src byte index = r + 4*((c+r) mod 4) where source column = (c+r) mod 4
                assign dout[127-(8*(r+4*c)) -: 8] = din[127-(8*(r+4*((c+r)%4))) -: 8];
            end
        end
    endgenerate

endmodule