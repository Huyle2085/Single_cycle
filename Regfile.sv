module regfile (
    input  logic        i_clk,
    input  logic        i_rstn,
    input  logic [4:0]  i_rs1_addr,
    input  logic [4:0]  i_rs2_addr,
    input  logic [4:0]  i_rd_addr,
    input  logic [31:0] i_rd_data,
    input  logic        i_rd_wren,
    output logic [31:0] o_rs1_data,
    output logic [31:0] o_rs2_data
);

    // Mảng 32 thanh ghi 32-bit (x0 đến x31)
    logic [31:0] regs [0:31];

    // Cổng ghi đồng bộ theo cạnh lên i_clk và reset bất đồng bộ tích cực mức thấp i_rstn
    // Thanh ghi x0 luôn cố định bằng 0 (bỏ qua mọi lệnh ghi vào địa chỉ 0)
    always_ff @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            for (int i = 0; i < 32; i++) begin
                regs[i] <= 32'b0;
            end
        end else if (i_rd_wren && (i_rd_addr != 5'd0)) begin
            regs[i_rd_addr] <= i_rd_data;
        end
    end

    // Hai cổng đọc bất đồng bộ (mạch tổ hợp, trả về 0 nếu địa chỉ đọc là 0)
    assign o_rs1_data = (i_rs1_addr == 5'd0) ? 32'b0 : regs[i_rs1_addr];
    assign o_rs2_data = (i_rs2_addr == 5'd0) ? 32'b0 : regs[i_rs2_addr];

endmodule
