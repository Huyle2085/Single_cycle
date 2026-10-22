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
    // =========================================================================
    int total_checks = 0;
    int error_count  = 0;

    // 1. Address Coverage cho rs1, rs2, và rd (khi wren=1 và wren=0)
    bit cov_rs1_addr   [0:31];
    bit cov_rs2_addr   [0:31];
    bit cov_rd_write   [0:31]; // Ghi khi i_rd_wren = 1
    bit cov_rd_nowrite [0:31]; // Thử ghi khi i_rd_wren = 0

    // 2. Functional Corner Cases Coverage:
    //    [0] Reset bất đồng bộ xóa toàn bộ thanh ghi về 0
    //    [1] Ghi vào x0 bị bỏ qua (x0 luôn bằng 0)
    //    [2] Đọc đồng thời cùng 1 thanh ghi trên cả 2 cổng (rs1 == rs2)
    //    [3] Đọc cùng địa chỉ đang được ghi (Read-during-Write: rs1/rs2 == rd)
    //    [4] Chặn ghi khi i_rd_wren = 0 (dữ liệu cũ được bảo toàn)
    bit cov_func_cases [0:4];

    // 3. Toggle Coverage trên o_rs1_data và o_rs2_data (32 bit)
    logic [31:0] prev_rs1       = 32'h0;
    logic [31:0] prev_rs2       = 32'h0;
    logic [31:0] rs1_toggle_01  = 32'h0;
    logic [31:0] rs1_toggle_10  = 32'h0;
    logic [31:0] rs2_toggle_01  = 32'h0;
    logic [31:0] rs2_toggle_10  = 32'h0;
    bit          first_sample   = 1;

    // Task thu thập Toggle Coverage và kiểm tra ngõ ra với Golden Reference
    task automatic check_outputs(input string tag);
        #1; // Đợi mạch tổ hợp ổn định
        total_checks++;

        if (!$isunknown(i_rs1_addr)) cov_rs1_addr[i_rs1_addr] = 1'b1;
        if (!$isunknown(i_rs2_addr)) cov_rs2_addr[i_rs2_addr] = 1'b1;
        if (i_rs1_addr == i_rs2_addr && i_rs1_addr != 5'd0) cov_func_cases[2] = 1'b1;

        if (!$isunknown(o_rs1_data) && !$isunknown(o_rs2_data)) begin
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

        if (o_rs1_data !== exp_rs1_data || o_rs2_data !== exp_rs2_data) begin
            $display("[ERROR - %s] Time=%0t | rs1_addr=%0d, rs2_addr=%0d | Got rs1=%h, rs2=%h | Exp rs1=%h, rs2=%h",
                     tag, $time, i_rs1_addr, i_rs2_addr, o_rs1_data, o_rs2_data, exp_rs1_data, exp_rs2_data);
            error_count++;
        end
    endtask

    // Task thực hiện 1 chu kỳ ghi đồng bộ và cập nhật mô hình chuẩn
    task automatic sync_write_and_check(
        input logic [4:0]  rd_addr,
        input logic [31:0] rd_data,
        input logic        wren,
        input logic [4:0]  rs1_addr,
        input logic [4:0]  rs2_addr,
        input string       tag
    );
        @(negedge i_clk);
        i_rd_addr  = rd_addr;
        i_rd_data  = rd_data;
        i_rd_wren  = wren;
        i_rs1_addr = rs1_addr;
        i_rs2_addr = rs2_addr;

        // Kiểm tra đọc bất đồng bộ TRƯỚC cạnh lên xung nhịp
        check_outputs({tag, "_PRE_CLK"});

        // Đợi cạnh lên i_clk (thời điểm ghi đồng bộ)
        @(posedge i_clk);
        if (wren) begin
            cov_rd_write[rd_addr] = 1'b1;
            if (rd_addr == 5'd0 && rd_data != 32'b0) cov_func_cases[1] = 1'b1;
            if ((rs1_addr == rd_addr || rs2_addr == rd_addr) && rd_addr != 5'd0) cov_func_cases[3] = 1'b1;
            if (rd_addr != 5'd0) ref_regs[rd_addr] = rd_data;
        end else begin
            cov_rd_nowrite[rd_addr] = 1'b1;
            cov_func_cases[4]       = 1'b1;
        end

        // Kiểm tra kết quả SAU cạnh lên xung nhịp
        check_outputs({tag, "_POST_CLK"});
    endtask

    // Task kích hoạt Reset bất đồng bộ
    task automatic apply_async_reset(input string tag);
        @(negedge i_clk);
        i_rd_wren = 1'b0;
        #2; // Tác động lệch pha clock để kiểm tra tính bất đồng bộ ngay lập tức
        i_rstn = 1'b0;
        for (int i = 0; i < 32; i++) ref_regs[i] = 32'b0;
        cov_func_cases[0] = 1'b1;
        check_outputs({tag, "_DURING_RST"});
        @(negedge i_clk);
        i_rstn = 1'b1;
        check_outputs({tag, "_AFTER_RST"});
    endtask

    // =========================================================================
    // KỊCH BẢN KIỂM THỬ (TEST SCENARIOS)
    // =========================================================================
    initial begin
        // Khởi tạo tín hiệu đầu vào
        i_rstn     = 1'b1;
        i_rs1_addr = 5'd0;
        i_rs2_addr = 5'd0;
        i_rd_addr  = 5'd0;
        i_rd_data  = 32'h0;
        i_rd_wren  = 1'b0;
        for (int i = 0; i < 32; i++) ref_regs[i] = 32'b0;

        // ---------------------------------------------------------------------
        // 1. Kiểm tra Reset bất đồng bộ ban đầu & Mô phỏng đúng Giản đồ xung Figure 5
        // ---------------------------------------------------------------------
        apply_async_reset("INIT_RESET");

        // Bước 1 của Figure 5: Ghi 0x1234_5678 vào x5, đồng thời đọc x5 (rs1) và x8 (rs2)
        sync_write_and_check(5'd5,  32'h1234_5678, 1'b1, 5'd5,  5'd8,  "FIG5_WRITE_X5");
        // Giữ nguyên địa chỉ đọc sang chu kỳ tiếp theo khi tắt wren
        sync_write_and_check(5'd5,  32'h0000_0000, 1'b0, 5'd5,  5'd8,  "FIG5_HOLD_X5");

        // Bước 2 của Figure 5: Ghi 0xABCD_ABCD vào x31, rs1=0, rs2=31
        sync_write_and_check(5'd31, 32'hABCD_ABCD, 1'b1, 5'd0,  5'd31, "FIG5_WRITE_X31");
        // Đổi địa chỉ rs1 từ 0 sang 31 bất đồng bộ (không cần ghi) -> rs1 lập tức xuất 0xABCD_ABCD
        @(negedge i_clk);
        i_rd_wren  = 1'b0;
        i_rs1_addr = 5'd31;
        i_rs2_addr = 5'd31;
        check_outputs("FIG5_ASYNC_READ_X31");

        // Bước 3 của Figure 5: Thử ghi 0xDEAD_BEEF vào x0, đọc x0 trên rs2 -> Phải luôn bằng 0
        sync_write_and_check(5'd0,  32'hDEAD_BEEF, 1'b1, 5'd31, 5'd0,  "FIG5_WRITE_X0");

        // ---------------------------------------------------------------------
        // 2. Kiểm tra chuyên sâu thanh ghi x0 (Hardwired Zero) với nhiều mẫu dữ liệu
        // ---------------------------------------------------------------------
        sync_write_and_check(5'd0, 32'hFFFF_FFFF, 1'b1, 5'd0, 5'd0, "X0_ALL_ONES");
        sync_write_and_check(5'd0, 32'h8000_0000, 1'b1, 5'd0, 5'd0, "X0_MIN_INT");
        sync_write_and_check(5'd0, 32'h5555_5555, 1'b1, 5'd0, 5'd0, "X0_ALT_55");

        // ---------------------------------------------------------------------
        // 3. Walking 1s & Walking 0s qua toàn bộ 32 thanh ghi (Đạt 100% Toggle & Address)
        // ---------------------------------------------------------------------
        for (int r = 0; r < 32; r++) begin
            automatic logic [31:0] walk1 = (32'h1 << r);
            automatic logic [31:0] walk0 = ~(32'h1 << r);

            // Ghi walk1 vào thanh ghi r và đọc ra trên cả 2 cổng
            sync_write_and_check(r[4:0], walk1, 1'b1, r[4:0], r[4:0], "WALK1_WRITE");
            // Thử ghi đè khi i_rd_wren = 0 (Dữ liệu không được phép thay đổi)
            sync_write_and_check(r[4:0], walk0, 1'b0, r[4:0], r[4:0], "WALK0_WEN_DISABLED");
            // Ghi walk0 khi i_rd_wren = 1
            sync_write_and_check(r[4:0], walk0, 1'b1, r[4:0], r[4:0], "WALK0_WRITE");
        end

        // ---------------------------------------------------------------------
        // 4. Quét đọc bất đồng bộ chéo toàn bộ cặp địa chỉ (rs1, rs2)
        // ---------------------------------------------------------------------
        @(negedge i_clk);
        i_rd_wren = 1'b0;
        for (int i = 0; i < 32; i++) begin
            i_rs1_addr = i[4:0];
            i_rs2_addr = 5'(31 - i);
            check_outputs("ASYNC_CROSS_READ");
        end

        // ---------------------------------------------------------------------
        // 5. Kiểm tra Reset bất đồng bộ giữa chừng khi các thanh ghi đang chứa dữ liệu
        // ---------------------------------------------------------------------
        apply_async_reset("MID_SIM_ASYNC_RESET");
        for (int i = 0; i < 32; i++) begin
            i_rs1_addr = i[4:0];
            i_rs2_addr = 5'(31 - i);
            check_outputs("VERIFY_ALL_ZERO_AFTER_RESET");
        end

        // ---------------------------------------------------------------------
        // 6. Kiểm tra ngẫu nhiên (Random Testing) 1000 chu kỳ
        // ---------------------------------------------------------------------
        for (int k = 0; k < 1000; k++) begin
            sync_write_and_check(
                $urandom_range(0, 31),
                $urandom(),
                $urandom_range(0, 1),
                $urandom_range(0, 31),
                $urandom_range(0, 31),
                "RANDOM"
            );
        end

        // =====================================================================
        // IN BÁO CÁO ĐỘ PHỦ (COVERAGE REPORT)
        // =====================================================================
        begin
            automatic int rs1_hit      = 0;
            automatic int rs2_hit      = 0;
            automatic int rd_w_hit     = 0;
            automatic int rd_nw_hit    = 0;
            automatic int func_hit     = 0;
            automatic int rs1_tog01    = $countones(rs1_toggle_01);
            automatic int rs1_tog10    = $countones(rs1_toggle_10);
            automatic int rs2_tog01    = $countones(rs2_toggle_01);
            automatic int rs2_tog10    = $countones(rs2_toggle_10);

            for (int i = 0; i < 32; i++) begin
                if (cov_rs1_addr[i])   rs1_hit++;
                if (cov_rs2_addr[i])   rs2_hit++;
                if (cov_rd_write[i])   rd_w_hit++;
                if (cov_rd_nowrite[i]) rd_nw_hit++;
            end

            for (int f = 0; f < 5; f++) begin
                if (cov_func_cases[f]) func_hit++;
            end

            $display("================================================================");
            $display("          BAO CAO KIEM THU & COVERAGE BO REGISTER FILE          ");
            $display("================================================================");
            $display("  Tong so lan kiem tra (Checks)  : %0d", total_checks);
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
            if (error_count == 0)
                $display("  KET QUA: === REGFILE TEST PASSED! Tat ca %0d lan kiem tra chinh xac! ===", total_checks);
            else
                $display("  KET QUA: === REGFILE TEST FAILED voi %0d loi! ===", error_count);
            $display("================================================================");
        end

        $finish;
    end
endmodule
