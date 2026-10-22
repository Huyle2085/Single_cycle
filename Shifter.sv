module shifter (
    input  logic [31:0] i_data,
    input  logic [4:0]  i_shamt,
    input  logic [1:0]  i_mode,
    output logic [31:0] o_data
);

    // Bit điền vào cho phép dịch phải (0 cho SRL, i_data[31] cho SRA)
    logic fill_bit;
    assign fill_bit = (i_mode == 2'b10) ? i_data[31] : 1'b0;

    // --- NHÁNH DỊCH PHẢI (SRL & SRA) ---
    logic [31:0] r_stage0, r_stage1, r_stage2, r_stage3, r_stage4;

    assign r_stage0 = i_shamt[0] ? {fill_bit,       i_data[31:1]}    : i_data;
    assign r_stage1 = i_shamt[1] ? {{2{fill_bit}},  r_stage0[31:2]}  : r_stage0;
    assign r_stage2 = i_shamt[2] ? {{4{fill_bit}},  r_stage1[31:4]}  : r_stage1;
    assign r_stage3 = i_shamt[3] ? {{8{fill_bit}},  r_stage2[31:8]}  : r_stage2;
    assign r_stage4 = i_shamt[4] ? {{16{fill_bit}}, r_stage3[31:16]} : r_stage3;

    // --- NHÁNH DỊCH TRÁI (SLL) ---
    logic [31:0] l_stage0, l_stage1, l_stage2, l_stage3, l_stage4;

    assign l_stage0 = i_shamt[0] ? {i_data[30:0],   1'b0}  : i_data;
    assign l_stage1 = i_shamt[1] ? {l_stage0[29:0], 2'b0}  : l_stage0;
    assign l_stage2 = i_shamt[2] ? {l_stage1[27:0], 4'b0}  : l_stage1;
    assign l_stage3 = i_shamt[3] ? {l_stage2[23:0], 8'b0}  : l_stage2;
    assign l_stage4 = i_shamt[4] ? {l_stage3[15:0], 16'b0} : l_stage3;

    // --- CHỌN NGÕ RA THEO i_mode ---
    always_comb begin
        case (i_mode)
            2'b00:   o_data = r_stage4; // Logical right shift
            2'b01:   o_data = l_stage4; // Logical left shift
            2'b10:   o_data = r_stage4; // Arithmetic right shift
            2'b11:   o_data = 32'b0;    // Reserved (safe value)
            default: o_data = 32'b0;
        endcase
    end

endmodule