module adder (
    input  logic [31:0] i_op_a,
    input  logic [31:0] i_op_b,
    input  logic        i_sub,   // 0: ADD (a + b), 1: SUB (a - b)
    output logic [31:0] o_sum,
    output logic        o_cout
);

    // Đảo bit toán hạng B khi thực hiện phép trừ (bù 2: a - b = a + ~b + 1)
    logic [31:0] b_mod;
    logic [32:0] carry;

    assign b_mod    = i_op_b ^ {32{i_sub}};
    assign carry[0] = i_sub;

    // Thiết kế bộ cộng 32-bit theo cấu trúc Full Adder (không dùng toán tử + / -)
    genvar i;
    generate
        for (i = 0; i < 32; i++) begin : gen_full_adder
            assign o_sum[i]   = i_op_a[i] ^ b_mod[i] ^ carry[i];
            assign carry[i+1] = (i_op_a[i] & b_mod[i]) |
                                (i_op_a[i] & carry[i]) |
                                (b_mod[i]  & carry[i]);
        end
    endgenerate

    assign o_cout = carry[32];

endmodule
