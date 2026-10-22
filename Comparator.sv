module comparator (
    input  logic [31:0] i_op_a,
    input  logic [31:0] i_op_b,
    input  logic        i_signed, // 0: Unsigned (SLTU), 1: Signed (SLT)
    output logic        o_less    // 1 nếu i_op_a < i_op_b, ngược lại 0
);

    // So sánh từng bit (không dùng toán tử < hay >):
    // eq_s0[i] = 1 khi bit thứ i của a và b bằng nhau
    // lt_s0[i] = 1 khi a[i] == 0 và b[i] == 1
    logic [31:0] eq_s0, lt_s0;
    assign eq_s0 = ~(i_op_a ^ i_op_b);
    assign lt_s0 = ~i_op_a & i_op_b;

    // Cây gộp nhị phân 5 tầng (Binary Reduction Tree) để tính Unsigned Less Than (ult)
    logic [15:0] eq_s1, lt_s1;
    logic [7:0]  eq_s2, lt_s2;
    logic [3:0]  eq_s3, lt_s3;
    logic [1:0]  eq_s4, lt_s4;
    logic        ult;

    genvar i;
    generate
        for (i = 0; i < 16; i++) begin : gen_stage1
            assign eq_s1[i] = eq_s0[2*i+1] & eq_s0[2*i];
            assign lt_s1[i] = lt_s0[2*i+1] | (eq_s0[2*i+1] & lt_s0[2*i]);
        end
        for (i = 0; i < 8; i++) begin : gen_stage2
            assign eq_s2[i] = eq_s1[2*i+1] & eq_s1[2*i];
            assign lt_s2[i] = lt_s1[2*i+1] | (eq_s1[2*i+1] & lt_s1[2*i]);
        end
        for (i = 0; i < 4; i++) begin : gen_stage3
            assign eq_s3[i] = eq_s2[2*i+1] & eq_s2[2*i];
            assign lt_s3[i] = lt_s2[2*i+1] | (eq_s2[2*i+1] & lt_s2[2*i]);
        end
        for (i = 0; i < 2; i++) begin : gen_stage4
            assign eq_s4[i] = eq_s3[2*i+1] & eq_s3[2*i];
            assign lt_s4[i] = lt_s3[2*i+1] | (eq_s3[2*i+1] & lt_s3[2*i]);
        end
    endgenerate

    assign ult = lt_s4[1] | (eq_s4[1] & lt_s4[0]);

    // Xử lý dấu khi i_signed = 1 (bù 2):
    // - Nếu 2 số khác dấu (i_op_a[31] ^ i_op_b[31] == 1): số âm (bit 31 = 1) luôn nhỏ hơn số dương
    // - Nếu 2 số cùng dấu hoặc so sánh không dấu: kết quả chính là ult
    logic diff_sign;
    assign diff_sign = i_op_a[31] ^ i_op_b[31];
    assign o_less    = (i_signed & diff_sign) ? i_op_a[31] : ult;

endmodule
