`timescale 1ns/1ps

module tb_regfile;
    logic        i_clk;
    logic        i_rstn;
    logic [4:0]  i_rs1_addr;
    logic [4:0]  i_rs2_addr;
    logic [4:0]  i_rd_addr;
    logic [31:0] i_rd_data;
    logic        i_rd_wren;
    logic [31:0] o_rs1_data;
    logic [31:0] o_rs2_data;

    // Mô hình chuẩn (Golden Reference Model) trong Testbench
    logic [31:0] ref_regs [0:31];
    logic [31:0] exp_rs1_data;
    logic [31:0] exp_rs2_data;

    // Khởi tạo DUT (Design Under Test)
    regfile dut (
        .i_clk      (i_clk),
        .i_rstn     (i_rstn),
        .i_rs1_addr (i_rs1_addr),
        .i_rs2_addr (i_rs2_addr),
        .i_rd_addr  (i_rd_addr),
        .i_rd_data  (i_rd_data),
        .i_rd_wren  (i_rd_wren),
        .o_rs1_data (o_rs1_data),
        .o_rs2_data (o_rs2_data)
    );

    // Tạo xung nhịp Clock chu kỳ 10ns (T = 10ns, f = 100MHz)
    initial begin
        i_clk = 1'b0;
        forever #5 i_clk = ~i_clk;
    end

    // Đọc bất đồng bộ từ mô hình chuẩn
    assign exp_rs1_data = (i_rs1_addr == 5'd0) ? 32'b0 : ref_regs[i_rs1_addr];
    assign exp_rs2_data = (i_rs2_addr == 5'd0) ? 32'b0 : ref_regs[i_rs2_addr];

    // =========================================================================
    // BỘ THEO DÕI FUNCTIONAL & TOGGLE COVERAGE TỰ ĐỘNG
    // (Chỉ ghi nhận Coverage khi kết quả kiểm tra DUT hoàn toàn chính xác)
    // =========================================================================
    int total_checks = 0;
    int error_count  = 0;

    // 1. Address Coverage cho rs1, rs2, và rd (khi wren=1 và wren=0)
    bit cov_rs1_addr   [0:31];
    bit cov_rs2_addr   [0:31];
    bit cov_rd_write   [0:31]; // Ghi thành công khi i_rd_wren = 1
    bit cov_rd_nowrite [0:31]; // Chặn ghi thành công khi i_rd_wren = 0

    // 2. Functional Corner Cases Coverage:
    //    [0] Reset bất đồng bộ xóa đúng toàn bộ 32 thanh ghi về 0
    //    [1] Ghi vào x0 bị bỏ qua (x0 luôn bằng 0)
    //    [2] Đọc đồng thời cùng 1 thanh ghi (khác x0) trên cả 2 cổng (rs1 == rs2)
    //    [3] Đọc cùng địa chỉ đang được ghi (Read-during-Write: rs1/rs2 == rd)
    //    [4] Chặn ghi khi i_rd_wren = 0 (dữ liệu cũ được bảo toàn khi i_rd_data khác dữ liệu cũ)
    bit cov_func_cases [0:4];

    // 3. Toggle Coverage trên o_rs1_data và o_rs2_data (32 bit)
    logic [31:0] prev_rs1      = 32'h0;
    logic [31:0] prev_rs2      = 32'h0;
    logic [31:0] rs1_toggle_01 = 32'h0;
    logic [31:0] rs1_toggle_10 = 32'h0;
    logic [31:0] rs2_toggle_01 = 32'h0;
    logic [31:0] rs2_toggle_10 = 32'h0;
    bit          first_sample  = 1;

    // Hàm đếm số bit 1 tương thích với mọi trình mô phỏng (thay cho $countones)
    function automatic int count_ones32(input logic [31:0] val);
        int cnt;
        cnt = 0;
        for (int i = 0; i < 32; i++) begin
            if (val[i] === 1'b1) cnt++;
        end
        return cnt;
    endfunction

    // -------------------------------------------------------------------------
    // Task kiểm tra ngõ ra với Golden Reference:
    // - Báo lỗi chi tiết bằng $error nếu thất bại
    // - Chỉ cập nhật Coverage khi DUT trả về kết quả ĐÚNG (pass == 1)
    // -------------------------------------------------------------------------
    task automatic check_outputs(
        input  string tag,
        input  string phase,
        input  bit    record_read_cov,
        output bit    pass
    );
        bit rs1_ok;
        bit rs2_ok;

        #0.1; // Đợi mạch tổ hợp và vùng NBA ổn định (100ps, tránh race condition)
        total_checks++;

        rs1_ok = (o_rs1_data === exp_rs1_data) && !$isunknown(o_rs1_data);
        rs2_ok = (o_rs2_data === exp_rs2_data) && !$isunknown(o_rs2_data);
        pass   = rs1_ok && rs2_ok;

        if (!pass) begin
            error_count++;
            $display("----------------------------------------------------------------");
            $error("[FAIL #%0d] Test: %s (%s) | Time: %0t",
                   error_count, tag, phase, $time);
            $display("  Control : i_rstn=%b | i_rd_wren=%b | i_rd_addr=x%0d (0x%02h) | i_rd_data=0x%08h",
                     i_rstn, i_rd_wren, i_rd_addr, i_rd_addr, i_rd_data);
            if (!rs1_ok) begin
                $display("  Port RS1: addr=x%0d | GOT=0x%08h | EXP=0x%08h | DIFF_MASK=0x%08h",
                         i_rs1_addr, o_rs1_data, exp_rs1_data, (o_rs1_data ^ exp_rs1_data));
            end
            if (!rs2_ok) begin
                $display("  Port RS2: addr=x%0d | GOT=0x%08h | EXP=0x%08h | DIFF_MASK=0x%08h",
                         i_rs2_addr, o_rs2_data, exp_rs2_data, (o_rs2_data ^ exp_rs2_data));
            end
            $display("----------------------------------------------------------------");
        end else if (record_read_cov) begin
            // CHỈ cập nhật Read & Toggle Coverage khi kết quả của DUT hoàn toàn chính xác
            if (!$isunknown(i_rs1_addr)) cov_rs1_addr[i_rs1_addr] = 1'b1;
            if (!$isunknown(i_rs2_addr)) cov_rs2_addr[i_rs2_addr] = 1'b1;
            if ((i_rs1_addr == i_rs2_addr) && (i_rs1_addr != 5'd0)) begin
                cov_func_cases[2] = 1'b1;
            end

            if (!first_sample) begin
                rs1_toggle_01 |= (~prev_rs1 &  o_rs1_data);
                rs1_toggle_10 |= ( prev_rs1 & ~o_rs1_data);
                rs2_toggle_01 |= (~prev_rs2 &  o_rs2_data);
                rs2_toggle_10 |= ( prev_rs2 & ~o_rs2_data);
            end
            prev_rs1     = o_rs1_data;
            prev_rs2     = o_rs2_data;
            first_sample = 0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Task thực hiện 1 chu kỳ ghi đồng bộ, tự động đọc xác nhận lại thanh ghi đích
    // và chỉ ghi nhận Write Coverage khi cả quá trình đọc/ghi đều PASS
    // -------------------------------------------------------------------------
    task automatic sync_write_and_check(
        input logic [4:0]  rd_addr,
        input logic [31:0] rd_data,
        input logic        wren,
        input logic [4:0]  rs1_addr,
        input logic [4:0]  rs2_addr,
        input string       tag
    );
        bit          pre_pass;
        bit          post_pass;
        bit          verify_rd_pass;
        logic [31:0] old_reg_val;
        logic [4:0]  saved_rs1_addr;

        @(negedge i_clk);
        old_reg_val = (rd_addr == 5'd0) ? 32'b0 : ref_regs[rd_addr];
        i_rd_addr   = rd_addr;
        i_rd_data   = rd_data;
        i_rd_wren   = wren;
        i_rs1_addr  = rs1_addr;
        i_rs2_addr  = rs2_addr;

        // 1. Kiểm tra đọc bất đồng bộ TRƯỚC cạnh lên xung nhịp
        check_outputs(tag, "PRE_CLK", 1'b1, pre_pass);

        // 2. Đợi cạnh lên i_clk (thời điểm ghi đồng bộ)
        @(posedge i_clk);
        if (wren && (rd_addr != 5'd0)) begin
            ref_regs[rd_addr] = rd_data;
        end

        // 3. Kiểm tra ngõ ra SAU cạnh lên xung nhịp tại (rs1_addr, rs2_addr)
        check_outputs(tag, "POST_CLK", 1'b1, post_pass);

        // 4. Đọc xác nhận trực tiếp thanh ghi đích rd_addr (nếu rs1 và rs2 chưa trỏ tới rd_addr)
        //    để đảm bảo thanh ghi rd_addr thực sự đã ghi (hoặc đã chặn ghi) đúng giá trị
        if ((rs1_addr != rd_addr) && (rs2_addr != rd_addr)) begin
            saved_rs1_addr = i_rs1_addr;
            i_rs1_addr     = rd_addr;
            check_outputs(tag, "VERIFY_RD_TARGET", 1'b0, verify_rd_pass);
            i_rs1_addr     = saved_rs1_addr;
        end else begin
            verify_rd_pass = post_pass;
        end

        // 5. CHỈ đánh dấu Write & Functional Coverage khi tất cả bước kiểm tra đều PASS
        if (pre_pass && post_pass && verify_rd_pass) begin
            if (wren) begin
                cov_rd_write[rd_addr] = 1'b1;
                if ((rd_addr == 5'd0) && (rd_data != 32'b0)) begin
                    cov_func_cases[1] = 1'b1; // Ghi khác 0 vào x0 nhưng x0 vẫn giữ 0
                end
                if (((rs1_addr == rd_addr) || (rs2_addr == rd_addr)) && (rd_addr != 5'd0)) begin
                    cov_func_cases[3] = 1'b1; // Read-during-Write thành công
                end
            end else begin
                cov_rd_nowrite[rd_addr] = 1'b1;
                if (rd_data != old_reg_val) begin
                    cov_func_cases[4] = 1'b1; // Chặn ghi thành công khi dữ liệu vào khác dữ liệu cũ
                end
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Task kích hoạt Reset bất đồng bộ và quét kiểm tra TOÀN BỘ 32 thanh ghi
    // ở cả 2 thời điểm:
    //   1) Ngay khi i_rstn = 0 (trước khi có bất kỳ cạnh lên i_clk nào xảy ra)
    //   2) Sau khi nhả i_rstn = 1
    // -------------------------------------------------------------------------
    task automatic apply_async_reset_and_verify_all(input string tag);
        bit         all_zero_during_rst;
        bit         all_zero_after_rst;
        bit         step_pass;
        logic [4:0] addr1;
        logic [4:0] addr2;
        logic [4:0] rev_idx;

        all_zero_during_rst = 1'b1;
        all_zero_after_rst  = 1'b1;

        @(negedge i_clk);
        i_rd_wren = 1'b0;
        #1; // Lệch pha 1ns sau cạnh xuống (còn 4ns nữa mới tới cạnh lên i_clk)
        i_rstn = 1'b0;
        for (int i = 0; i < 32; i++) begin
            ref_regs[i] = 32'b0;
        end

        // Quét kiểm tra toàn bộ 32 thanh ghi ngay khi đang giữ i_rstn = 0
        // 16 bước x 0.1ns = 1.6ns -> Hoàn tất kiểm tra cả 32 thanh ghi TRƯỚC cạnh lên i_clk!
        for (int k = 0; k < 16; k++) begin
            addr1      = k[4:0] << 1;
            addr2      = (k[4:0] << 1) | 5'd1;
            i_rs1_addr = addr1;
            i_rs2_addr = addr2;
            check_outputs(tag, "DURING_RST_ALL_REGS", 1'b1, step_pass);
            if (!step_pass) all_zero_during_rst = 1'b0;
        end

        // Nhả reset tại cạnh xuống clock tiếp theo
        @(negedge i_clk);
        i_rstn = 1'b1;

        // Quét kiểm tra lại toàn bộ 32 thanh ghi sau khi nhả Reset (i_rstn = 1)
        // 32 bước x 0.1ns = 3.2ns -> Hoàn tất trong cùng nửa chu kỳ clock
        for (int i = 0; i < 32; i++) begin
            rev_idx    = 5'd31 - i[4:0];
            i_rs1_addr = i[4:0];
            i_rs2_addr = rev_idx;
            check_outputs(tag, "AFTER_RST_ALL_REGS", 1'b1, step_pass);
            if (!step_pass) all_zero_after_rst = 1'b0;
        end

        // CHỈ đánh dấu Reset Coverage nếu toàn bộ 32 thanh ghi đều về 0 đúng yêu cầu
        if (all_zero_during_rst && all_zero_after_rst) begin
            cov_func_cases[0] = 1'b1;
        end
    endtask

    // =========================================================================
    // KỊCH BẢN KIỂM THỬ (TEST SCENARIOS)
    // =========================================================================
    initial begin
        bit          dummy_pass;
        logic [31:0] walk1;
        logic [31:0] walk0;
        logic [4:0]  rev_addr;
        logic [4:0]  rand_rd;
        logic [31:0] rand_data;
        logic        rand_wren;
        logic [4:0]  rand_rs1;
        logic [4:0]  rand_rs2;

        // Khởi tạo tín hiệu đầu vào
        i_rstn     = 1'b1;
        i_rs1_addr = 5'd0;
        i_rs2_addr = 5'd0;
        i_rd_addr  = 5'd0;
        i_rd_data  = 32'h0;
        i_rd_wren  = 1'b0;
        for (int i = 0; i < 32; i++) begin
            ref_regs[i] = 32'b0;
        end

        // ---------------------------------------------------------------------
        // 1. Nạp dữ liệu khác 0 vào tất cả thanh ghi (x1..x31) trước rồi mới
        //    Reset ban đầu để chứng minh INIT_RESET thực sự xóa toàn bộ về 0
        // ---------------------------------------------------------------------
        for (int i = 1; i < 32; i++) begin
            @(negedge i_clk);
            i_rd_wren   = 1'b1;
            i_rd_addr   = i[4:0];
            i_rd_data   = 32'hA5A5_0000 | i;
            @(posedge i_clk);
            ref_regs[i] = 32'hA5A5_0000 | i;
        end
        apply_async_reset_and_verify_all("INIT_RESET");

        // ---------------------------------------------------------------------
        // 2. Mô phỏng chính xác chuỗi sự kiện trong Giản đồ xung Figure 5
        // ---------------------------------------------------------------------
        // Bước 1 (Figure 5): Ghi 0x1234_5678 vào x5, đồng thời đọc x5 (rs1) và x8 (rs2)
        sync_write_and_check(5'd5,  32'h1234_5678, 1'b1, 5'd5,  5'd8,  "FIG5_WRITE_X5");
        // Giữ nguyên địa chỉ đọc sang chu kỳ tiếp theo khi tắt wren
        sync_write_and_check(5'd5,  32'h0000_0000, 1'b0, 5'd5,  5'd8,  "FIG5_HOLD_X5");

        // Bước 2 (Figure 5): Ghi 0xABCD_ABCD vào x31, rs1=0, rs2=31
        sync_write_and_check(5'd31, 32'hABCD_ABCD, 1'b1, 5'd0,  5'd31, "FIG5_WRITE_X31");
        // Đổi địa chỉ rs1 từ 0 sang 31 bất đồng bộ (không cần ghi) -> rs1 lập tức xuất 0xABCD_ABCD
        @(negedge i_clk);
        i_rd_wren  = 1'b0;
        i_rs1_addr = 5'd31;
        i_rs2_addr = 5'd31;
        check_outputs("FIG5_ASYNC_READ_X31", "COMB_READ", 1'b1, dummy_pass);

        // Bước 3 (Figure 5): Thử ghi 0xDEAD_BEEF vào x0, đọc x0 trên rs2 -> Phải luôn bằng 0
        sync_write_and_check(5'd0,  32'hDEAD_BEEF, 1'b1, 5'd31, 5'd0,  "FIG5_WRITE_X0");

        // ---------------------------------------------------------------------
        // 3. Kiểm tra chuyên sâu thanh ghi x0 (Hardwired Zero) với nhiều mẫu dữ liệu
        // ---------------------------------------------------------------------
        sync_write_and_check(5'd0, 32'hFFFF_FFFF, 1'b1, 5'd0, 5'd0, "X0_ALL_ONES");
        sync_write_and_check(5'd0, 32'h8000_0000, 1'b1, 5'd0, 5'd0, "X0_MIN_INT");
        sync_write_and_check(5'd0, 32'h5555_5555, 1'b1, 5'd0, 5'd0, "X0_ALT_55");

        // ---------------------------------------------------------------------
        // 4. Walking 1s & Walking 0s qua toàn bộ 32 thanh ghi
        // ---------------------------------------------------------------------
        for (int r = 0; r < 32; r++) begin
            walk1 = (32'h1 << r);
            walk0 = ~(32'h1 << r);

            // Ghi walk1 vào thanh ghi r và đọc ra trên cả 2 cổng
            sync_write_and_check(r[4:0], walk1, 1'b1, r[4:0], r[4:0], "WALK1_WRITE");
            // Thử ghi đè khi i_rd_wren = 0 (Dữ liệu không được phép thay đổi)
            sync_write_and_check(r[4:0], walk0, 1'b0, r[4:0], r[4:0], "WALK0_WEN_DISABLED");
            // Ghi walk0 khi i_rd_wren = 1
            sync_write_and_check(r[4:0], walk0, 1'b1, r[4:0], r[4:0], "WALK0_WRITE");
        end

        // ---------------------------------------------------------------------
        // 5. Quét đọc bất đồng bộ chéo toàn bộ cặp địa chỉ (rs1, rs2)
        // ---------------------------------------------------------------------
        @(negedge i_clk);
        i_rd_wren = 1'b0;
        for (int i = 0; i < 32; i++) begin
            rev_addr   = 5'd31 - i[4:0];
            i_rs1_addr = i[4:0];
            i_rs2_addr = rev_addr;
            check_outputs("ASYNC_CROSS_READ", "COMB_SCAN", 1'b1, dummy_pass);
        end

        // ---------------------------------------------------------------------
        // 6. Kiểm tra Reset bất đồng bộ giữa chừng & quét kiểm tra toàn bộ 32 thanh ghi
        // ---------------------------------------------------------------------
        apply_async_reset_and_verify_all("MID_SIM_ASYNC_RESET");

        // ---------------------------------------------------------------------
        // 7. Kiểm tra ngẫu nhiên (Random Testing) 1000 chu kỳ
        //    Lưu ý chuẩn IEEE 1800: $urandom_range(maxval, minval)
        // ---------------------------------------------------------------------
        for (int k = 0; k < 1000; k++) begin
            rand_rd   = $urandom_range(31, 0);
            rand_data = $urandom();
            rand_wren = $urandom_range(1, 0);
            rand_rs1  = $urandom_range(31, 0);
            rand_rs2  = $urandom_range(31, 0);

            sync_write_and_check(
                rand_rd,
                rand_data,
                rand_wren,
                rand_rs1,
                rand_rs2,
                "RANDOM"
            );
        end

        // ---------------------------------------------------------------------
        // 8. Kiểm tra Reset bất đồng bộ lần cuối sau khi chạy Random Test
        // ---------------------------------------------------------------------
        apply_async_reset_and_verify_all("FINAL_ASYNC_RESET");

        // =====================================================================
        // IN BÁO CÁO ĐỘ PHỦ (COVERAGE REPORT) & KẾT LUẬN
        // =====================================================================
        begin
            int rs1_hit;
            int rs2_hit;
            int rd_w_hit;
            int rd_nw_hit;
            int func_hit;
            int rs1_tog01;
            int rs1_tog10;
            int rs2_tog01;
            int rs2_tog10;
            bit all_cov_100;

            rs1_hit   = 0;
            rs2_hit   = 0;
            rd_w_hit  = 0;
            rd_nw_hit = 0;
            func_hit  = 0;
            rs1_tog01 = count_ones32(rs1_toggle_01);
            rs1_tog10 = count_ones32(rs1_toggle_10);
            rs2_tog01 = count_ones32(rs2_toggle_01);
            rs2_tog10 = count_ones32(rs2_toggle_10);

            for (int i = 0; i < 32; i++) begin
                if (cov_rs1_addr[i])   rs1_hit++;
                if (cov_rs2_addr[i])   rs2_hit++;
                if (cov_rd_write[i])   rd_w_hit++;
                if (cov_rd_nowrite[i]) rd_nw_hit++;
            end

            for (int f = 0; f < 5; f++) begin
                if (cov_func_cases[f]) func_hit++;
            end

            all_cov_100 = (rs1_hit == 32)   && (rs2_hit == 32)   &&
                          (rd_w_hit == 32)  && (rd_nw_hit == 32) &&
                          (func_hit == 5)   &&
                          (rs1_tog01 == 32) && (rs1_tog10 == 32) &&
                          (rs2_tog01 == 32) && (rs2_tog10 == 32);

            $display("================================================================");
            $display("          BAO CAO KIEM THU & COVERAGE BO REGISTER FILE          ");
            $display("================================================================");
            $display("  Tong so lan kiem tra (Checks)  : %0d", total_checks);
            $display("  Tong so loi phat hien (Errors) : %0d", error_count);
            $display("  Read Port 1 Address Coverage   : %0d / 32 regs (%0.2f%%)",
                     rs1_hit, (rs1_hit * 100.0) / 32.0);
            $display("  Read Port 2 Address Coverage   : %0d / 32 regs (%0.2f%%)",
                     rs2_hit, (rs2_hit * 100.0) / 32.0);
            $display("  Write Port Address (wren = 1)  : %0d / 32 regs (%0.2f%%)",
                     rd_w_hit, (rd_w_hit * 100.0) / 32.0);
            $display("  Write Port Masked  (wren = 0)  : %0d / 32 regs (%0.2f%%)",
                     rd_nw_hit, (rd_nw_hit * 100.0) / 32.0);
            $display("  Functional Corner Conditions   : %0d / 5  bins (%0.2f%%)",
                     func_hit, (func_hit * 100.0) / 5.0);
            $display("  o_rs1_data Toggle (0->1 / 1->0): %0d/32 (%0.2f%%) | %0d/32 (%0.2f%%)",
                     rs1_tog01, (rs1_tog01 * 100.0) / 32.0, rs1_tog10, (rs1_tog10 * 100.0) / 32.0);
            $display("  o_rs2_data Toggle (0->1 / 1->0): %0d/32 (%0.2f%%) | %0d/32 (%0.2f%%)",
                     rs2_tog01, (rs2_tog01 * 100.0) / 32.0, rs2_tog10, (rs2_tog10 * 100.0) / 32.0);
            $display("----------------------------------------------------------------");
            if ((error_count == 0) && all_cov_100) begin
                $display("  KET QUA: === REGFILE TEST PASSED! Tat ca %0d lan kiem tra chinh xac! ===", total_checks);
                $display("================================================================");
            end else begin
                $display("  KET QUA: === REGFILE TEST FAILED! (Errors: %0d, FullCov: %0b) ===",
                         error_count, all_cov_100);
                $display("================================================================");
                $fatal(1, "REGFILE VERIFICATION FAILED: Phat hien %0d loi hoac chua dat 100%% coverage!", error_count);
            end
        end

        $finish;
    end
endmodule
