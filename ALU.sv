module alu (
    input  logic [31:0] i_op_a,
    input  logic [31:0] i_op_b,
    input  logic [3:0]  i_alu_op,
    output logic [31:0] o_alu_data
);

    // =========================================================================
    // ĐỊNH NGHĨA MÃ PHÉP TOÁN 4-BIT (THEO CHUẨN RISC-V {funct7[5], funct3})
    // =========================================================================
    localparam logic [3:0] ALU_ADD  = 4'b0000; // Addition:                a + b
    localparam logic [3:0] ALU_SUB  = 4'b1000; // Subtraction:             a - b
    localparam logic [3:0] ALU_SLL  = 4'b0001; // Logical left shift:      a << b[4:0]
    localparam logic [3:0] ALU_SLT  = 4'b0010; // Signed less-than:        (a < b) ? 1 : 0
    localparam logic [3:0] ALU_SLTU = 4'b0011; // Unsigned less-than:      (a < b) ? 1 : 0
    localparam logic [3:0] ALU_XOR  = 4'b0100; // Bitwise XOR:             a ^ b
    localparam logic [3:0] ALU_SRL  = 4'b0101; // Logical right shift:     a >> b[4:0]
    localparam logic [3:0] ALU_SRA  = 4'b1101; // Arithmetic right shift:  a >>> b[4:0]
    localparam logic [3:0] ALU_OR   = 4'b0110; // Bitwise OR:              a | b
    localparam logic [3:0] ALU_AND  = 4'b0111; // Bitwise AND:             a & b

    // =========================================================================
    // 1. KHỐI ADDER / SUBTRACTOR (Dùng chung cho ADD và SUB)
    // =========================================================================
    logic        adder_sub;
    logic [31:0] adder_result;
    logic        adder_cout;

    assign adder_sub = (i_alu_op == ALU_SUB);

    adder u_adder (
        .i_op_a (i_op_a),
        .i_op_b (i_op_b),
        .i_sub  (adder_sub),
        .o_sum  (adder_result),
        .o_cout (adder_cout)
    );

    // =========================================================================
    // 2. KHỐI COMPARATOR (Dùng chung cho SLT và SLTU)
    // =========================================================================
    logic comp_signed;
    logic comp_less;

    assign comp_signed = (i_alu_op == ALU_SLT);

    comparator u_comparator (
        .i_op_a   (i_op_a),
        .i_op_b   (i_op_b),
        .i_signed (comp_signed),
        .o_less   (comp_less)
    );

    // =========================================================================
    // 3. KHỐI SHIFTER (Dùng chung cho SLL, SRL và SRA)
    // =========================================================================
    logic [1:0]  shift_mode;
    logic [31:0] shift_result;

    always_comb begin
        case (i_alu_op)
            ALU_SRL: shift_mode = 2'b00; // Logical right shift
            ALU_SLL: shift_mode = 2'b01; // Logical left shift
            ALU_SRA: shift_mode = 2'b10; // Arithmetic right shift
            default: shift_mode = 2'b11; // Safe / unused mode
        endcase
    end

    shifter u_shifter (
        .i_data  (i_op_a),
        .i_shamt (i_op_b[4:0]),
        .i_mode  (shift_mode),
        .o_data  (shift_result)
    );

    // =========================================================================
    // 4. CÁC PHÉP TOÁN LOGIC VÀ BỘ CHỌN KẾT QUẢ (RESULT MULTIPLEXER)
    // =========================================================================
    always_comb begin
        case (i_alu_op)
            ALU_ADD,
            ALU_SUB:  o_alu_data = adder_result;
            ALU_SLT,
            ALU_SLTU: o_alu_data = {31'b0, comp_less};
            ALU_XOR:  o_alu_data = i_op_a ^ i_op_b;
            ALU_OR:   o_alu_data = i_op_a | i_op_b;
            ALU_AND:  o_alu_data = i_op_a & i_op_b;
            ALU_SLL,
            ALU_SRL,
            ALU_SRA:  o_alu_data = shift_result;
            default:  o_alu_data = 32'b0; // Unused encodings -> safe value 0
        endcase
    end

endmodule
