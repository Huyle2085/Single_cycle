`timescale 1ns/1ps

module tb_comparator;
    logic [31:0] i_op_a;
    logic [31:0] i_op_b;
    logic        i_signed;
    logic        o_less;
    logic        expected;

    // Khởi tạo DUT (Design Under Test)
    comparator dut (
        .i_op_a   (i_op_a),
        .i_op_b   (i_op_b),
        .i_signed (i_signed),
        .o_less   (o_less)
    );

    // Golden Reference Model (dùng toán tử < và $signed() của SystemVerilog)
    always_comb begin
        if (i_signed == 1'b1)
            expected = ($signed(i_op_a) < $signed(i_op_b)) ? 1'b1 : 1'b0;
        else if (i_signed == 1'b0)
            expected = (i_op_a < i_op_b) ? 1'b1 : 1'b0;
        else
            expected = 1'bx;
    end

    // =========================================================================
    // BỘ THEO DÕI FUNCTIONAL & TOGGLE COVERAGE TỰ ĐỘNG
    // =========================================================================
    int total_tests = 0;
    int error_count = 0;

    // 1. Comparison condition coverage (8 trường hợp biên):
    //    Signed (i_signed = 1):
    //      [0] a < b (cùng dấu dương/âm)
    //      [1] a < b (khác dấu: a âm, b dương)
    //      [2] a == b
    //      [3] a > b (khác dấu: a dương, b âm)
    //      [4] a > b (cùng dấu dương/âm)
    //    Unsigned (i_signed = 0):
    //      [5] a < b
    //      [6] a == b
    //      [7] a > b
    bit cov_cmp_cases [0:7];

    // 2. Bit-position difference coverage (32 vị trí bit từ 0..31):
    //    Đánh dấu khi a và b chỉ khác nhau duy nhất tại bit thứ k (kiểm tra cây so sánh)
    bit cov_bit_diff [0:31];

    // 3. Toggle coverage cho o_less (0->1 và 1->0)
    logic       prev_o_less  = 1'b0;
    logic [1:0] less_toggles = 2'b00; // [0]: 0->1, [1]: 1->0
    bit         first_sample = 1;

    task automatic apply_and_check(
        input logic [31:0] a,
        input logic [31:0] b,
        input logic        is_signed,
        input string       tag
    );
        i_op_a   = a;
        i_op_b   = b;
        i_signed = is_signed;
        #1;
        total_tests++;

        // Thu thập Comparison Condition Coverage
        if (!$isunknown(a) && !$isunknown(b) && !$isunknown(is_signed)) begin
            if (is_signed == 1'b1) begin
                if ($signed(a) < $signed(b) && (a[31] == b[31])) cov_cmp_cases[0] = 1'b1;
                if ($signed(a) < $signed(b) && (a[31] != b[31])) cov_cmp_cases[1] = 1'b1;
                if (a == b)                                      cov_cmp_cases[2] = 1'b1;
                if ($signed(a) > $signed(b) && (a[31] != b[31])) cov_cmp_cases[3] = 1'b1;
                if ($signed(a) > $signed(b) && (a[31] == b[31])) cov_cmp_cases[4] = 1'b1;
            end else begin
                if (a < b)  cov_cmp_cases[5] = 1'b1;
                if (a == b) cov_cmp_cases[6] = 1'b1;
                if (a > b)  cov_cmp_cases[7] = 1'b1;
            end

            // Kiểm tra nếu a và b chỉ lệch nhau đúng 1 bit
            begin
                automatic logic [31:0] diff = a ^ b;
                if ($onehot(diff)) begin
                    for (int k = 0; k < 32; k++)
                        if (diff[k]) cov_bit_diff[k] = 1'b1;
                end
            end
        end

        // Thu thập Toggle Coverage trên o_less
        if (!$isunknown(o_less)) begin
            if (!first_sample) begin
                if (!prev_o_less &&  o_less) less_toggles[0] = 1'b1;
                if ( prev_o_less && !o_less) less_toggles[1] = 1'b1;
            end
            prev_o_less  = o_less;
            first_sample = 0;
        end

        // Self-check kết quả với Golden Reference
        if (o_less !== expected) begin
            $display("[ERROR - %s] signed=%b | a=%h, b=%h | Got=%b, Exp=%b",
                     tag, i_signed, i_op_a, i_op_b, o_less, expected);
            error_count++;
        end
    endtask

    // =========================================================================
    // KỊCH BẢN KIỂM THỬ (DIRECT TEST + RANDOM TEST & SELF-CHECK)
    // =========================================================================
    initial begin
        // Danh sách 10 vector biên đặc biệt cho toán hạng A và B
        automatic logic [31:0] corner_vals [10] = '{
            32'h0000_0000, // 0
            32'hFFFF_FFFF, // -1 (Signed) / MAX_UINT (Unsigned)
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
        // 1. Direct Test: Quét ma trận (10x10 Corner Vectors) x 2 chế độ (Signed/Unsigned)
        // ---------------------------------------------------------------------
        for (int sg = 0; sg < 2; sg++) begin
            foreach (corner_vals[i]) begin
                foreach (corner_vals[j]) begin
                    apply_and_check(corner_vals[i], corner_vals[j], sg[0], "DIRECT_CORNER");
                end
            end
        end

        // ---------------------------------------------------------------------
        // 2. Direct Test: Walking 1s & Walking 0s (Kiểm tra từng nút cây so sánh 5 tầng)
        // Lệch nhau đúng 1 bit tại từng vị trí bit b = 0..31 trên nền toàn 0 và nền toàn 1
        // ---------------------------------------------------------------------
        for (int b = 0; b < 32; b++) begin
            automatic logic [31:0] walk1 = (32'h1 << b);
            automatic logic [31:0] walk0 = ~(32'h1 << b);

            for (int sg = 0; sg < 2; sg++) begin
                // Lệch 1 bit trên nền 0
                apply_and_check(32'h0000_0000, walk1, sg[0], "WALK_DIFF_BASE0");
                apply_and_check(walk1, 32'h0000_0000, sg[0], "WALK_DIFF_BASE0");

                // Lệch 1 bit trên nền 1
                apply_and_check(walk0, 32'hFFFF_FFFF, sg[0], "WALK_DIFF_BASE1");
                apply_and_check(32'hFFFF_FFFF, walk0, sg[0], "WALK_DIFF_BASE1");

                // Hai số bằng nhau tại mọi mẫu walk
                apply_and_check(walk1, walk1,         sg[0], "WALK_EQUAL");
                apply_and_check(walk0, walk0,         sg[0], "WALK_EQUAL");
            end
        end

        // ---------------------------------------------------------------------
        // 3. Random Test + Self-Check: 2000 testcase ngẫu nhiên
        // ---------------------------------------------------------------------
        for (int k = 0; k < 2000; k++) begin
            apply_and_check(
                $urandom(),
                $urandom(),
                $urandom_range(0, 1),
                "RANDOM"
            );
        end

        // =====================================================================
        // IN BÁO CÁO ĐỘ PHỦ (COVERAGE REPORT)
        // =====================================================================
        begin
            automatic int cmp_hit         = 0;
            automatic int diff_hit        = 0;
            automatic int less_toggle_hit = $countones(less_toggles);

            for (int c = 0; c < 8; c++)
                if (cov_cmp_cases[c]) cmp_hit++;

            for (int k = 0; k < 32; k++)
                if (cov_bit_diff[k]) diff_hit++;

            $display("================================================================");
            $display("           BAO CAO KIEM THU & COVERAGE BO COMPARATOR            ");
            $display("================================================================");
            $display("  Tong so vector kiem thu        : %0d", total_tests);
            $display("  Comparator Corner Conditions   : %0d / 8  bins (%0.2f%%)",
                     cmp_hit, (cmp_hit * 100.0) / 8.0);
            $display("  Single-Bit Diff Positions      : %0d / 32 bits (%0.2f%%)",
                     diff_hit, (diff_hit * 100.0) / 32.0);
            $display("  o_less Toggle (0->1 & 1->0)    : %0d / 2  ways (%0.2f%%)",
                     less_toggle_hit, (less_toggle_hit * 100.0) / 2.0);
            $display("----------------------------------------------------------------");
            if (error_count == 0)
                $display("  KET QUA: === COMPARATOR TEST PASSED! Tat ca %0d truong hop chinh xac! ===", total_tests);
            else
                $display("  KET QUA: === COMPARATOR TEST FAILED voi %0d loi! ===", error_count);
            $display("================================================================");
        end

        $finish;
    end
endmodule
