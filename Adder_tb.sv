`timescale 1ns/1ps

module tb_adder;
    logic [31:0] i_op_a;
    logic [31:0] i_op_b;
    logic        i_sub;
    logic [31:0] o_sum;
    logic        o_cout;

    logic [31:0] exp_sum;
    logic        exp_cout;

    // Khởi tạo DUT (Design Under Test)
    adder dut (
        .i_op_a (i_op_a),
        .i_op_b (i_op_b),
        .i_sub  (i_sub),
        .o_sum  (o_sum),
        .o_cout (o_cout)
    );

    // Golden Reference Model (dùng toán tử + và - của SystemVerilog)
    always_comb begin
        if (i_sub == 1'b0) begin
            exp_sum  = i_op_a + i_op_b;
            exp_cout = ({1'b0, i_op_a} + {1'b0, i_op_b}) >> 32;
        end else if (i_sub == 1'b1) begin
            exp_sum  = i_op_a - i_op_b;
            exp_cout = ({1'b0, i_op_a} + {1'b0, ~i_op_b} + 33'd1) >> 32;
        end else begin
            exp_sum  = 32'dx;
            exp_cout = 1'bx;
        end
    end

    // =========================================================================
    // BỘ THEO DÕI FUNCTIONAL & TOGGLE COVERAGE TỰ ĐỘNG
    // =========================================================================
    int total_tests = 0;
    int error_count = 0;

    // 1. Mode x Carry-out coverage: i_sub (0: ADD, 1: SUB) x o_cout (0, 1) = 4 bins
    bit cov_mode_cout [0:1][0:1];

    // 2. Corner arithmetic conditions:
    //    [0] ADD: 0 + 0 = 0
    //    [1] ADD: Unsigned overflow (cout = 1)
    //    [2] ADD: Signed positive overflow (pos + pos = neg)
    //    [3] ADD: Signed negative overflow (neg + neg = pos)
    //    [4] SUB: a == b (kết quả bằng 0, cout = 1)
    //    [5] SUB: a < b unsigned (mượn bit / cout = 0)
    //    [6] SUB: Signed overflow (pos - neg = neg)
    //    [7] SUB: Signed underflow (neg - pos = pos)
    bit cov_arith_cases [0:7];

    // 3. Toggle coverage cho o_sum (32 bit) và o_cout (1 bit)
    logic [31:0] prev_o_sum   = 32'h0;
    logic [31:0] toggle_0to1  = 32'h0;
    logic [31:0] toggle_1to0  = 32'h0;
    logic        prev_o_cout  = 1'b0;
    logic [1:0]  cout_toggles = 2'b00; // [0]: 0->1, [1]: 1->0
    bit          first_sample = 1;

    task automatic apply_and_check(
        input logic [31:0] a,
        input logic [31:0] b,
        input logic        sub,
        input string       tag
    );
        i_op_a = a;
        i_op_b = b;
        i_sub  = sub;
        #1;
        total_tests++;

        // Thu thập Mode x Cout Coverage
        if (!$isunknown(sub) && !$isunknown(o_cout)) begin
            cov_mode_cout[sub][o_cout] = 1'b1;
        end

        // Thu thập Arithmetic Corner Coverage
        if (!$isunknown(a) && !$isunknown(b) && !$isunknown(sub)) begin
            if (sub == 1'b0) begin
                if (a == 32'h0 && b == 32'h0)                               cov_arith_cases[0] = 1'b1;
                if (o_cout == 1'b1)                                         cov_arith_cases[1] = 1'b1;
                if (!a[31] && !b[31] &&  o_sum[31])                         cov_arith_cases[2] = 1'b1;
                if ( a[31] &&  b[31] && !o_sum[31])                         cov_arith_cases[3] = 1'b1;
            end else begin
                if (a == b)                                                 cov_arith_cases[4] = 1'b1;
                if (a < b)                                                  cov_arith_cases[5] = 1'b1;
                if (!a[31] &&  b[31] &&  o_sum[31])                         cov_arith_cases[6] = 1'b1;
                if ( a[31] && !b[31] && !o_sum[31])                         cov_arith_cases[7] = 1'b1;
            end
        end

        // Thu thập Toggle Coverage
        if (!$isunknown(o_sum) && !$isunknown(o_cout)) begin
            if (!first_sample) begin
                toggle_0to1 |= (~prev_o_sum &  o_sum);
                toggle_1to0 |= ( prev_o_sum & ~o_sum);
                if (!prev_o_cout &&  o_cout) cout_toggles[0] = 1'b1;
                if ( prev_o_cout && !o_cout) cout_toggles[1] = 1'b1;
            end
            prev_o_sum   = o_sum;
            prev_o_cout  = o_cout;
            first_sample = 0;
        end

        // Self-check kết quả với Golden Reference
        if (o_sum !== exp_sum || o_cout !== exp_cout) begin
            $display("[ERROR - %s] sub=%b | a=%h, b=%h | Got sum=%h cout=%b | Exp sum=%h cout=%b",
                     tag, i_sub, i_op_a, i_op_b, o_sum, o_cout, exp_sum, exp_cout);
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
        // 1. Direct Test: Quét ma trận (10x10 Corner Vectors) x 2 chế độ (ADD/SUB)
        // ---------------------------------------------------------------------
        for (int sub = 0; sub < 2; sub++) begin
            foreach (corner_vals[i]) begin
                foreach (corner_vals[j]) begin
                    apply_and_check(corner_vals[i], corner_vals[j], sub[0], "DIRECT_CORNER");
                end
            end
        end

        // ---------------------------------------------------------------------
        // 2. Direct Test: Walking 1s & Walking 0s (Kiểm tra dây chuyền nhớ 32 tầng)
        // Kiểm tra lan truyền carry/borrow xuyên qua từng Full Adder từ bit 0..31
        // ---------------------------------------------------------------------
        for (int b = 0; b < 32; b++) begin
            automatic logic [31:0] walk1 = (32'h1 << b);
            automatic logic [31:0] walk0 = ~(32'h1 << b);

            // ADD: kiểm tra cộng tại từng bit và truyền nhớ liên hoàn
            apply_and_check(walk1, walk1,          1'b0, "WALK_ADD_SELF");
            apply_and_check(walk0, 32'h0000_0001,  1'b0, "WALK_ADD_RIPPLE");
            apply_and_check(walk0, walk1,          1'b0, "WALK_ADD_COMPLEMENT");

            // SUB: kiểm tra trừ tại từng bit và mượn nhớ liên hoàn
            apply_and_check(walk1, walk1,          1'b1, "WALK_SUB_EQUAL");
            apply_and_check(walk1, 32'h0000_0001,  1'b1, "WALK_SUB_BORROW");
            apply_and_check(32'h0000_0000, walk1,  1'b1, "WALK_SUB_NEGATE");
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
            automatic int mode_cout_hit   = 0;
            automatic int arith_hit       = 0;
            automatic int toggle01_hit    = $countones(toggle_0to1);
            automatic int toggle10_hit    = $countones(toggle_1to0);
            automatic int cout_toggle_hit = $countones(cout_toggles);

            for (int s = 0; s < 2; s++)
                for (int c = 0; c < 2; c++)
                    if (cov_mode_cout[s][c]) mode_cout_hit++;

            for (int i = 0; i < 8; i++)
                if (cov_arith_cases[i]) arith_hit++;

            $display("================================================================");
            $display("             BAO CAO KIEM THU & COVERAGE BO ADDER               ");
            $display("================================================================");
            $display("  Tong so vector kiem thu        : %0d", total_tests);
            $display("  Mode x Cout Cross Coverage     : %0d / 4  bins (%0.2f%%)",
                     mode_cout_hit, (mode_cout_hit * 100.0) / 4.0);
            $display("  Arithmetic Corner Conditions   : %0d / 8  bins (%0.2f%%)",
                     arith_hit, (arith_hit * 100.0) / 8.0);
            $display("  Sum Output Toggle (0 -> 1)     : %0d / 32 bits (%0.2f%%)",
                     toggle01_hit, (toggle01_hit * 100.0) / 32.0);
            $display("  Sum Output Toggle (1 -> 0)     : %0d / 32 bits (%0.2f%%)",
                     toggle10_hit, (toggle10_hit * 100.0) / 32.0);
            $display("  Cout Toggle (0->1 & 1->0)      : %0d / 2  ways (%0.2f%%)",
                     cout_toggle_hit, (cout_toggle_hit * 100.0) / 2.0);
            $display("----------------------------------------------------------------");
            if (error_count == 0)
                $display("  KET QUA: === ADDER TEST PASSED! Tat ca %0d truong hop chinh xac! ===", total_tests);
            else
                $display("  KET QUA: === ADDER TEST FAILED voi %0d loi! ===", error_count);
            $display("================================================================");
        end

        $finish;
    end
endmodule
