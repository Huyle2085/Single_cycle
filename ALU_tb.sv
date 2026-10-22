`timescale 1ns/1ps

module tb_alu;
    logic [31:0] i_op_a;
    logic [31:0] i_op_b;
    logic [3:0]  i_alu_op;
    logic [31:0] o_alu_data;
    logic [31:0] expected;

    // Mã lệnh ALU 4-bit theo chuẩn RISC-V
    localparam logic [3:0] ALU_ADD  = 4'b0000;
    localparam logic [3:0] ALU_SUB  = 4'b1000;
    localparam logic [3:0] ALU_SLL  = 4'b0001;
    localparam logic [3:0] ALU_SLT  = 4'b0010;
    localparam logic [3:0] ALU_SLTU = 4'b0011;
    localparam logic [3:0] ALU_XOR  = 4'b0100;
    localparam logic [3:0] ALU_SRL  = 4'b0101;
    localparam logic [3:0] ALU_SRA  = 4'b1101;
    localparam logic [3:0] ALU_OR   = 4'b0110;
    localparam logic [3:0] ALU_AND  = 4'b0111;

    // Khởi tạo DUT (Design Under Test)
    alu dut (
        .i_op_a     (i_op_a),
        .i_op_b     (i_op_b),
        .i_alu_op   (i_alu_op),
        .o_alu_data (o_alu_data)
    );

    // Golden Reference Model
    always_comb begin
        case (i_alu_op)
            ALU_ADD:  expected = i_op_a + i_op_b;
            ALU_SUB:  expected = i_op_a - i_op_b;
            ALU_SLT:  expected = ($signed(i_op_a) < $signed(i_op_b)) ? 32'd1 : 32'd0;
            ALU_SLTU: expected = (i_op_a < i_op_b) ? 32'd1 : 32'd0;
            ALU_XOR:  expected = i_op_a ^ i_op_b;
            ALU_OR:   expected = i_op_a | i_op_b;
            ALU_AND:  expected = i_op_a & i_op_b;
            ALU_SLL:  expected = i_op_a << i_op_b[4:0];
            ALU_SRL:  expected = i_op_a >> i_op_b[4:0];
            ALU_SRA:  expected = $signed(i_op_a) >>> i_op_b[4:0];
            default:  expected = 32'd0; // Các mã không dùng trả về 0
        endcase
    end

    // =========================================================================
    // BỘ THEO DÕI FUNCTIONAL & TOGGLE COVERAGE TỰ ĐỘNG
    // =========================================================================
    int total_tests = 0;
    int error_count = 0;

    // 1. Opcode coverage: toàn bộ 16 mã 4-bit (10 hợp lệ + 6 dự phòng)
    bit cov_opcode [0:15];
    bit cov_xz_opcode = 0;

    // 2. Shift cross coverage: 3 phép dịch (SLL=0, SRL=1, SRA=2) x 32 shamt
    bit cov_shift_shamt [0:2][0:31];

    // 3. Comparison condition coverage:
    //    SLT  : [0] a<b (cùng dấu), [1] a<b (khác dấu), [2] a==b, [3] a>b (khác dấu), [4] a>b (cùng dấu)
    //    SLTU : [5] a<b, [6] a==b, [7] a>b
    bit cov_cmp_cases [0:7];

    // 4. Toggle coverage cho o_alu_data (32 bit)
    logic [31:0] prev_o_data  = 32'h0;
    logic [31:0] toggle_0to1  = 32'h0;
    logic [31:0] toggle_1to0  = 32'h0;
    bit          first_sample = 1;

    task automatic apply_and_check(
        input logic [31:0] a,
        input logic [31:0] b,
        input logic [3:0]  op,
        input string       tag
    );
        i_op_a   = a;
        i_op_b   = b;
        i_alu_op = op;
        #1;
        total_tests++;

        // Thu thập Opcode Coverage
        if (!$isunknown(op)) begin
            cov_opcode[op] = 1'b1;
        end else begin
            cov_xz_opcode = 1'b1;
        end

        // Thu thập Shift Cross Coverage
        if (!$isunknown(op) && !$isunknown(b[4:0])) begin
            if (op == ALU_SLL) cov_shift_shamt[0][b[4:0]] = 1'b1;
            if (op == ALU_SRL) cov_shift_shamt[1][b[4:0]] = 1'b1;
            if (op == ALU_SRA) cov_shift_shamt[2][b[4:0]] = 1'b1;
        end

        // Thu thập Comparison Coverage
        if (!$isunknown(a) && !$isunknown(b)) begin
            if (op == ALU_SLT) begin
                if ($signed(a) < $signed(b) && (a[31] == b[31])) cov_cmp_cases[0] = 1'b1;
                if ($signed(a) < $signed(b) && (a[31] != b[31])) cov_cmp_cases[1] = 1'b1;
                if (a == b)                                      cov_cmp_cases[2] = 1'b1;
                if ($signed(a) > $signed(b) && (a[31] != b[31])) cov_cmp_cases[3] = 1'b1;
                if ($signed(a) > $signed(b) && (a[31] == b[31])) cov_cmp_cases[4] = 1'b1;
            end
            if (op == ALU_SLTU) begin
                if (a < b)  cov_cmp_cases[5] = 1'b1;
                if (a == b) cov_cmp_cases[6] = 1'b1;
                if (a > b)  cov_cmp_cases[7] = 1'b1;
            end
        end

        // Thu thập Toggle Coverage trên o_alu_data
        if (!$isunknown(o_alu_data)) begin
            if (!first_sample) begin
                toggle_0to1 |= (~prev_o_data &  o_alu_data);
                toggle_1to0 |= ( prev_o_data & ~o_alu_data);
            end
            prev_o_data  = o_alu_data;
            first_sample = 0;
        end

        // Kiểm tra kết quả
        if (o_alu_data !== expected) begin
            $display("[ERROR - %s] op=%b | a=%h, b=%h | Got=%h, Exp=%h",
                     tag, i_alu_op, i_op_a, i_op_b, o_alu_data, expected);
            error_count++;
        end
    endtask

    // =========================================================================
    // KỊCH BẢN KIỂM THỬ (TEST SCENARIOS)
    // =========================================================================
    initial begin
        // Danh sách 10 vector biên đặc biệt cho toán hạng A và B
        automatic logic [31:0] corner_vals [10] = '{
            32'h0000_0000, // 0
            32'hFFFF_FFFF, // -1 (All 1s)
            32'h8000_0000, // MIN_INT (-2^31)
            32'h7FFF_FFFF, // MAX_INT (2^31 - 1)
            32'h0000_0001, // +1 (LSB only)
            32'h8000_0001, // -2^31 + 1
            32'h5555_5555, // Alternating 0101
            32'hAAAA_AAAA, // Alternating 1010
            32'hFFFF_0000, // Upper half 1s
            32'h0000_FFFF  // Lower half 1s
        };

        // ---------------------------------------------------------------------
        // 1. Quét toàn bộ tổ hợp (10x10 Corner Vectors) x (16 mã lệnh i_alu_op)
        // Kiểm tra cả 10 lệnh hợp lệ và 6 mã lệnh không dùng (unused encodings)
        // ---------------------------------------------------------------------
        for (int op = 0; op < 16; op++) begin
            foreach (corner_vals[i]) begin
                foreach (corner_vals[j]) begin
                    apply_and_check(corner_vals[i], corner_vals[j], op[3:0], "CORNER_MATRIX");
                end
            end
        end

        // ---------------------------------------------------------------------
        // 2. Kiểm tra chuyên sâu khối Shifter trong ALU (SLL, SRL, SRA)
        // Quét đủ shamt = 0..31 kèm các bit cao b[31:5] khác 0 để đảm bảo ALU
        // chỉ trích xuất đúng b[4:0] theo yêu cầu bảng 6
        // ---------------------------------------------------------------------
        foreach (corner_vals[i]) begin
            for (int s = 0; s < 32; s++) begin
                automatic logic [31:0] b_with_upper_noise = {27'h7FF_FFFF, s[4:0]};
                apply_and_check(corner_vals[i], b_with_upper_noise, ALU_SLL, "SHIFT_SLL");
                apply_and_check(corner_vals[i], b_with_upper_noise, ALU_SRL, "SHIFT_SRL");
                apply_and_check(corner_vals[i], b_with_upper_noise, ALU_SRA, "SHIFT_SRA");
            end
        end

        // ---------------------------------------------------------------------
        // 3. Walking 1s & Walking 0s cho ADD, SUB, SLT, SLTU, XOR, OR, AND
        // Đảm bảo kiểm tra từng bit dây truyền nhớ (Carry chain), cây so sánh
        // và lật đủ 32 bit ngõ ra (Toggle 0->1 và 1->0)
        // ---------------------------------------------------------------------
        for (int b = 0; b < 32; b++) begin
            automatic logic [31:0] walk1 = (32'h1 << b);
            automatic logic [31:0] walk0 = ~(32'h1 << b);

            // Kiểm tra truyền nhớ dây chuyền (Ripple-carry propagation)
            apply_and_check(walk0, 32'h0000_0001, ALU_ADD,  "WALK_ADD_CARRY");
            apply_and_check(walk1, 32'h0000_0001, ALU_SUB,  "WALK_SUB_BORROW");

            // Kiểm tra so sánh lệch nhau đúng 1 bit tại mọi vị trí bit b
            apply_and_check(walk1, 32'h0000_0000, ALU_SLT,  "WALK_SLT");
            apply_and_check(32'h0000_0000, walk1, ALU_SLT,  "WALK_SLT");
            apply_and_check(walk1, walk0,         ALU_SLTU, "WALK_SLTU");
            apply_and_check(walk0, walk1,         ALU_SLTU, "WALK_SLTU");

            // Kiểm tra các cổng logic từng bit
            apply_and_check(walk1, walk0, ALU_XOR, "WALK_XOR");
            apply_and_check(walk1, walk0, ALU_OR,  "WALK_OR");
            apply_and_check(walk1, walk1, ALU_AND, "WALK_AND");
        end

        // ---------------------------------------------------------------------
        // 4. Kiểm tra nhánh default khi i_alu_op chứa X / Z
        // ---------------------------------------------------------------------
        apply_and_check(32'h1234_5678, 32'h8765_4321, 4'bxxxx, "DEFAULT_X");
        apply_and_check(32'h1234_5678, 32'h8765_4321, 4'bzzzz, "DEFAULT_Z");

        // ---------------------------------------------------------------------
        // 5. Kiểm tra ngẫu nhiên (Random Testing) 4000 trường hợp
        // ---------------------------------------------------------------------
        for (int k = 0; k < 4000; k++) begin
            apply_and_check(
                $urandom(),
                $urandom(),
                $urandom_range(0, 15),
                "RANDOM"
            );
        end

        // =====================================================================
        // IN BÁO CÁO ĐỘ PHỦ (COVERAGE REPORT)
        // =====================================================================
        begin
            automatic int op_hit       = 0;
            automatic int shift_hit    = 0;
            automatic int cmp_hit      = 0;
            automatic int toggle01_hit = $countones(toggle_0to1);
            automatic int toggle10_hit = $countones(toggle_1to0);

            for (int i = 0; i < 16; i++)
                if (cov_opcode[i]) op_hit++;

            for (int m = 0; m < 3; m++)
                for (int s = 0; s < 32; s++)
                    if (cov_shift_shamt[m][s]) shift_hit++;

            for (int c = 0; c < 8; c++)
                if (cov_cmp_cases[c]) cmp_hit++;

            $display("================================================================");
            $display("              BAO CAO KIEM THU & COVERAGE BO ALU                ");
            $display("================================================================");
            $display("  Tong so vector kiem thu        : %0d", total_tests);
            $display("  Opcode Coverage (10 valid+6 un): %0d / 16 bins (%0.2f%%)",
                     op_hit, (op_hit * 100.0) / 16.0);
            $display("  Shift Cross (3 ops x 32 shamt) : %0d / 96 bins (%0.2f%%)",
                     shift_hit, (shift_hit * 100.0) / 96.0);
            $display("  Comparator Corner Conditions   : %0d / 8  bins (%0.2f%%)",
                     cmp_hit, (cmp_hit * 100.0) / 8.0);
            $display("  Default X/Z Opcode Branch      : %s",
                     cov_xz_opcode ? "HIT (100.00%)" : "MISSED (0.00%)");
            $display("  Output Toggle (0 -> 1)         : %0d / 32 bits (%0.2f%%)",
                     toggle01_hit, (toggle01_hit * 100.0) / 32.0);
            $display("  Output Toggle (1 -> 0)         : %0d / 32 bits (%0.2f%%)",
                     toggle10_hit, (toggle10_hit * 100.0) / 32.0);
            $display("----------------------------------------------------------------");
            if (error_count == 0)
                $display("  KET QUA: === ALU TEST PASSED! Tat ca %0d truong hop chinh xac! ===", total_tests);
            else
                $display("  KET QUA: === ALU TEST FAILED voi %0d loi! ===", error_count);
            $display("================================================================");
        end

        $finish;
    end
endmodule
