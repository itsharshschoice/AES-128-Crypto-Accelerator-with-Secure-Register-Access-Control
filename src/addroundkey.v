module addroundkey (
    input  wire [127:0] din,
    input  wire [127:0] round_key,
    output wire [127:0] dout
);

    assign dout = din ^ round_key;

endmodule