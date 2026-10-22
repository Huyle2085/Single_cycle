`timescale 1ns/1ps

module tb_shifter;
    logic [31:0] i_data;
    logic [4:0]  i_shamt;
    logic [1:0]  i_mode;
    logic [31:0] o_data;
    logic [31:0] expected;

    // Khởi tạo DUT (Design Under Test)
    shifter dut (
        .i_data  (i_data),
        .i_shamt (i_shamt),
        .i_mode  (i_mode),
        .o_data  (o_data)
    );

    // Tính kết quả chuẩn (Golden Reference) trong Testbench
    always_comb begin
        case (i_mode)
            2'b00:   expected = i_data >> i_shamt;               // SRL
            2'b01:   expected = i_data << i_shamt;               // SLL
            2'b10:   expected = $signed(i_data) >>> i_shamt;     // SRA
            2'b11:   expected = 32'b0;                           // Reserved
            default: expected = 32'b0;                           // X/Z safe fallback
        endcase
    end

    // =========================================================================
    // BỘ THEO DÕI FUNCTIONAL & TOGGLE COVERAGE TỰ ĐỘNG
    // =========================================================================
    int total_tests = 0;
    int error_count = 0;

    // Cross-coverage bins: mode (4) x shamt (32) x sign_bit (2) = 256 bins
    bit cov_mode_shamt_sign [0:3][0:31][0:1];
    // Data pattern bins: All-0, All-1, MSB-only, LSB-only, Pos, Neg
    bit cov_data_pattern [0:5];
    // Default branch coverage (X/Z input on i_mode)
    bit cov_default_branch = 0;

    // Toggle coverage trackers cho o_data (0->1 và 1->0 cho 32 bit)
    logic [31:0] prev_o_data = 32'h0;
    logic [31:0] toggle_0to1 = 32'h0;
    logic [31:0] toggle_1to0 = 32'h0;
    bit          first_sample = 1;

    // Task chạy 1 vector kiểm thử, tự động thu thập coverage và so sánh kết quả
    task automatic apply_and_check(
        input logic [31:0] data,
        input logic [4:0]  shamt,
        input logic [1:0]  mode,
        input string       test_name
    );
        i_data  = data;
        i_shamt = shamt;
        i_mode  = mode;
        #1; // Đợi mạch tổ hợp ổn định
        total_tests++;

        // 1. Thu thập Cross Coverage (chỉ tính khi mode và shamt không chứa X/Z)
        if (!$isunknown(mode) && !$isunknown(shamt) && !$isunknown(data[31])) begin
            cov_mode_shamt_sign[mode][shamt][data[31]] = 1'b1;
        end else begin
            cov_default_branch = 1'b1;
        end

        // 2. Thu thập Data Pattern Coverage
        if (!$isunknown(data)) begin
            if (data == 32'h0000_0000) cov_data_pattern[0] = 1'b1;
            if (data == 32'hFFFF_FFFF) cov_data_pattern[1] = 1'b1;
            if (data == 32'h8000_0000) cov_data_pattern[2] = 1'b1;
            if (data == 32'h0000_0001) cov_data_pattern[3] = 1'b1;
            if (data[31] == 1'b0 && data != 0) cov_data_pattern[4] = 1'b1;
            if (data[31] == 1'b1 && data != 32'hFFFF_FFFF) cov_data_pattern[5] = 1'b1;
        end

        // 3. Thu thập Toggle Coverage trên ngõ ra o_data
        if (!$isunknown(o_data)) begin
            if (!first_sample) begin
                toggle_0to1 |= (~prev_o_data &  o_data);
                toggle_1to0 |= ( prev_o_data & ~o_data);
            end
            prev_o_data  = o_data;
            first_sample = 0;
        end

        // 4. Kiểm tra kết quả với Golden Reference
        if (o_data !== expected) begin
            $display("[ERROR - %s] mode=%b, data=%h, shamt=%0d | Got=%h, Exp=%h",
                     test_name, i_mode, i_data, i_shamt, o_data, expected);
            error_count++;
        end
    endtask

    // =========================================================================
    // KỊCH BẢN KIỂM THỬ (TEST SCENARIOS)
    // =========================================================================
    initial begin
        // ---------------------------------------------------------------------
        // 1. Corner Cases mở rộng (Biên toàn 0, toàn 1, cực trị âm/dương, xen kẽ)
        // ---------------------------------------------------------------------
        automatic logic [31:0] corner_vectors [10] = '{
            32'h0000_0000, // Toàn bit 0
            32'hFFFF_FFFF, // Toàn bit 1 (-1)
            32'h8000_0000, // Số âm nhỏ nhất (chỉ MSB = 1)
            32'h7FFF_FFFF, // Số dương lớn nhất (MSB = 0, còn lại = 1)
            32'h0000_0001, // Chỉ LSB = 1
            32'h8000_0001, // Biên MSB và LSB đều bằng 1
            32'h5555_5555, // Xen kẽ 0101...
            32'hAAAA_AAAA, // Xen kẽ 1010...
            32'hA5A5_5A5A, // Mẫu đối xứng byte
            32'hFFFF_0000  // Nửa cao = 1, nửa thấp = 0
        };

        foreach (corner_vectors[idx]) begin
            for (int m = 0; m < 4; m++) begin
                for (int s = 0; s < 32; s++) begin
                    apply_and_check(corner_vectors[idx], s[4:0], m[1:0], "CORNER");
                end
            end
        end

        // ---------------------------------------------------------------------
        // 2. Walking 1s & Walking 0s trên i_data
        // Đảm bảo từng đường dây trong 5 tầng mux (stage0..stage4) đều được kiểm tra
        // và mọi bit của o_data đều lật 0->1 và 1->0
        // ---------------------------------------------------------------------
        for (int b = 0; b < 32; b++) begin
            automatic logic [31:0] walk_one  = (32'h1 << b);
            automatic logic [31:0] walk_zero = ~(32'h1 << b);
            for (int m = 0; m < 4; m++) begin
                for (int s = 0; s < 32; s++) begin
                    apply_and_check(walk_one,  s[4:0], m[1:0], "WALK_1");
                    apply_and_check(walk_zero, s[4:0], m[1:0], "WALK_0");
                end
            end
        end

        // ---------------------------------------------------------------------
        // 3. Kiểm tra cô lập từng tầng dịch (Single-Stage & Multi-Stage Isolation)
        // Kiểm tra dịch 1, 2, 4, 8, 16 và tổ hợp chuyển tiếp nhanh 0 <-> 31
        // ---------------------------------------------------------------------
        for (int m = 0; m < 4; m++) begin
            for (int stage = 0; stage < 5; stage++) begin
                automatic logic [4:0] one_hot_shamt = (5'b00001 << stage);
                apply_and_check(32'hF0F0_0F0F, one_hot_shamt,  m[1:0], "STAGE_ISOLATION");
                apply_and_check(32'h0F0F_F0F0, ~one_hot_shamt, m[1:0], "STAGE_INV_ISOLATION");
            end
            // Kiểm tra chuyển trạng thái biên đột ngột (0 -> 31 -> 0)
            apply_and_check(32'hFFFF_FFFF, 5'd0,  m[1:0], "TRANSITION_0_31");
            apply_and_check(32'h0000_0000, 5'd31, m[1:0], "TRANSITION_0_31");
            apply_and_check(32'hFFFF_FFFF, 5'd31, m[1:0], "TRANSITION_0_31");
            apply_and_check(32'h0000_0000, 5'd0,  m[1:0], "TRANSITION_0_31");
        end

        // ---------------------------------------------------------------------
        // 4. Kiểm tra nhánh default (X / Z trên i_mode) để đạt 100% Branch Coverage
        // ---------------------------------------------------------------------
        apply_and_check(32'hDEAD_BEEF, 5'd4, 2'bxx, "DEFAULT_X_MODE");
        apply_and_check(32'hDEAD_BEEF, 5'd8, 2'bzz, "DEFAULT_Z_MODE");
        apply_and_check(32'hDEAD_BEEF, 5'd2, 2'b0x, "DEFAULT_0X_MODE");

        // ---------------------------------------------------------------------
        // 5. Kiểm tra ngẫu nhiên (Constrained / Directed Random) 2000 trường hợp
        // ---------------------------------------------------------------------
        for (int i = 0; i < 2000; i++) begin
            apply_and_check(
                $urandom(),
                $urandom_range(0, 31),
                $urandom_range(0, 3),
                "RANDOM"
            );
        end

        // =====================================================================
        // BÁO CÁO KẾT QUẢ VÀ ĐỘ PHỦ (COVERAGE REPORT)
        // =====================================================================
        begin
            automatic int cross_hit = 0;
            automatic int pattern_hit = 0;
            automatic int toggle_01_hit = $countones(toggle_0to1);
            automatic int toggle_10_hit = $countones(toggle_1to0);

            for (int m = 0; m < 4; m++)
                for (int s = 0; s < 32; s++)
                    for (int sg = 0; sg < 2; sg++)
                        if (cov_mode_shamt_sign[m][s][sg]) cross_hit++;

            for (int p = 0; p < 6; p++)
                if (cov_data_pattern[p]) pattern_hit++;

            $display("================================================================");
            $display("                BAO CAO KIEM THU & COVERAGE                     ");
            $display("================================================================");
            $display("  Tong so vector kiem thu : %0d", total_tests);
            $display("  Cross (mode x shamt x sign): %0d / 256 bins (%0.2f%%)",
                     cross_hit, (cross_hit * 100.0) / 256.0);
            $display("  Data Corner Patterns       : %0d / 6   bins (%0.2f%%)",
                     pattern_hit, (pattern_hit * 100.0) / 6.0);
            $display("  Default Branch (X/Z mode)  : %s",
                     cov_default_branch ? "HIT (100.00%)" : "MISSED (0.00%)");
            $display("  Output Toggle (0 -> 1)     : %0d / 32  bits (%0.2f%%)",
                     toggle_01_hit, (toggle_01_hit * 100.0) / 32.0);
            $display("  Output Toggle (1 -> 0)     : %0d / 32  bits (%0.2f%%)",
                     toggle_10_hit, (toggle_10_hit * 100.0) / 32.0);
            $display("----------------------------------------------------------------");
            if (error_count == 0)
                $display("  KET QUA: === TEST PASSED! Tat ca %0d truong hop deu chinh xac! ===", total_tests);
            else
                $display("  KET QUA: === TEST FAILED voi %0d loi! ===", error_count);
            $display("================================================================");
        end

        $finish;
    end
endmodule
