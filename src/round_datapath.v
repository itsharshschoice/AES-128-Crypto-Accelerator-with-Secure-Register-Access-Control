module round_datapath (
    input  wire [127:0] round_in,
    input  wire [127:0] round_key,
    input  wire mix_en,
    output wire [127:0] round_out
);

    wire [127:0] sub_out, shift_out, mix_out;
    wire [127:0] mixed_or_shifted;

    subbytes    u_subbytes  (.din(round_in),  .dout(sub_out));
    shiftrows   u_shiftrows (.din(sub_out),   .dout(shift_out));
    mixcolumns  u_mixcols   (.din(shift_out), .dout(mix_out));

    assign mixed_or_shifted = mix_en ? mix_out : shift_out;

    addroundkey u_addkey (.din(mixed_or_shifted), .round_key(round_key), .dout(round_out));

endmodule