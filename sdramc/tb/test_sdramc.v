`timescale 1ps/1ps
// tang nano 20k SDRAM動作確認
//

module test;

`define SIM

reg sys_clk;
wire clk_sdram; // 上記と逆相
reg reset;

reg s1;
wire O_sdram_clk;
wire O_sdram_cke;
wire O_sdram_cs_n;
wire O_sdram_cas_n;
wire O_sdram_ras_n;
wire O_sdram_wen_n;
wire [31:0] IO_sdram_dq;
wire [10:0] O_sdram_addr;
wire [1:0] O_sdram_ba;
wire [3:0] O_sdram_dqm;

reg reset_sync1;
reg reset_sync2;
wire sdramc_resetn=~reset_sync2;
wire [22:0] cmd_addr;
wire        cmd;
wire        cmd_en;
wire        cmd_ack;
wire [3:0]  cmd_len;
wire [31:0] rd_data;
wire        rd_data_valid;
wire [31:0] wr_data;
wire [3:0]  wr_mask;

always@(posedge sys_clk or posedge reset)
    if(reset) begin
        reset_sync1 <= 1'b1;
        reset_sync2 <= 1'b1;
    end
    else begin
        reset_sync1 <= 1'b0;
        reset_sync2 <= reset_sync1;
    end

`define SDRAMC_SIM
sdramc #(
    .FREQ(166*1000000)     // 166MHz
) u_sdramc
  (
    // "Magic" port names that the gowin compiler connects to the on-chip SDRAM
    .SDRAM_CLK(O_sdram_clk),
    .SDRAM_CKE(O_sdram_cke),
    .SDRAM_nCS(O_sdram_cs_n),       // chip select
    .SDRAM_nCAS(O_sdram_cas_n),     // columns address select
    .SDRAM_nRAS(O_sdram_ras_n),     // row address select
    .SDRAM_nWE(O_sdram_wen_n),      // write enable
    .SDRAM_DQ(IO_sdram_dq),         // 32 bit bidirectional data bus
    .SDRAM_A(O_sdram_addr),         // 11 bit multiplexed address bus
    .SDRAM_BA(O_sdram_ba),          // two banks
    .SDRAM_DQM(O_sdram_dqm),        // 32/4

    // Logic side interface
    .clk(sys_clk),  // in
    .clk_sdram(sys_clk),    // phase shifted from clk (normally 180-degrees)
    .clk_capdq(sys_clk),   // DQ capture clock
    .resetn(sdramc_resetn), // in
    .addr(cmd_addr),    // in [22:0] byte addr
    .cmd(cmd),          // 0:read, 1:write
    .cmd_en(cmd_en),
    .cmd_ack(cmd_ack),  // out
    .cmd_len(cmd_len),  // in    // 0-15
    .rd_data(rd_data),  // out
    .rd_data_valid(rd_data_valid),    // out
    .wr_data(wr_data),  // in wrdata
    .wr_mask(wr_mask),   // in wmask
    
    .busy(busy)
  );

// 擬似マスター
sdramc_master u_sdramc_master (
    .clk(sys_clk),       // 166MHz clk
    .cmd(cmd),           //input cmd 0:read(), 1:write
    .cmd_en(cmd_en),        //input cmd_en
    .cmd_ack(cmd_ack),
    .cmd_len(cmd_len),
    .addr(cmd_addr),  // byte address
    .wr_data(wr_data),
    .wr_mask(wr_mask),
    .rd_data(rd_data),
    .rd_data_valid(rd_data_valid)
    );
    

mt48lc2m32b2 u_sdram
(
    .Clk(O_sdram_clk),
    .Cke(O_sdram_cke),
    .Cs_n(O_sdram_cs_n),
    .Ras_n(O_sdram_ras_n),
    .Cas_n(O_sdram_cas_n),
    .We_n(O_sdram_wen_n),
    .Dq(IO_sdram_dq),
    .Addr(O_sdram_addr),
    .Ba(O_sdram_ba),
    .Dqm(O_sdram_dqm)
    );

// クロックの生成
// 166MHz
always begin
    sys_clk = 0; #(6_024/2);
    sys_clk = 1; #(6_024/2);
end

assign clk_sdram = ~sys_clk;

event sim_trap;
integer i;
integer testno;
reg       rand_w;
reg [1:0] rand_bank;
reg [3:0] rand_bl;
reg [7:0] rand_adr;
integer   rand_spc;

initial begin
    testno=0;
    reset=1;
    u_sdramc_master.init;
    repeat(50) @(posedge sys_clk);
    reset=0;
    repeat(50) @(posedge sys_clk);
    u_sdramc_master.wdata[0]=0;
    u_sdramc_master.wdata[1]=1;
    u_sdramc_master.wdata[2]=2;
    u_sdramc_master.wdata[3]=3;
    u_sdramc_master.wmask[0]=1;
    u_sdramc_master.wmask[1]=2;
    u_sdramc_master.wmask[2]=4;
    u_sdramc_master.wmask[3]=8;
    u_sdramc_master.a_write(32'h0000_0000,3);
    u_sdramc_master.a_write(32'h0000_0010,0);
    for(i=0; i<16; i=i+1) begin
        u_sdramc_master.wdata[i]=i;
        u_sdramc_master.wmask[i]=4'h0;
    end
    u_sdramc_master.a_write(32'h0000_0020,15);
    u_sdramc_master.a_write(32'h0000_0060,15);
    u_sdramc_master.a_write(32'h0000_00a0,0);   // BL=1
    u_sdramc_master.a_write(32'h0000_00a4,0);   // BL=1
    u_sdramc_master.a_write(32'h0000_00a8,1);   // BL=2
    u_sdramc_master.a_write(32'h0000_00b0,1);   // BL=2
    
    testno=1;
    repeat(100) @(posedge sys_clk);
    u_sdramc_master.a_read(32'h0000_0000,3);
    u_sdramc_master.a_read(32'h0000_0010,0);
    u_sdramc_master.a_read(32'h0000_0020,15);
    u_sdramc_master.a_read(32'h0000_0060,15);
    u_sdramc_master.a_read(32'h0000_00a0,0);   // BL=1
    u_sdramc_master.a_read(32'h0000_00a4,0);   // BL=1
    u_sdramc_master.a_read(32'h0000_00a8,1);   // BL=2
    u_sdramc_master.a_read(32'h0000_00b0,1);   // BL=2
    repeat(100) @(posedge sys_clk);

    testno=2;
    // BL=1  R->W ACT間隔 11cyc
    // BL=2  R->W ACT間隔 11cyc (1cycle効率がよい.というかBLが小さいのはEXTRA不要)
    // BL=3  R->W ACT間隔 11cyc (2cycle効率がよい.というかBLが小さいのはEXTRA不要)
    // BL=4  R->W ACT間隔 12cyc (3良い。ここまでTRAS待ちでprecharge発行が遅れる)
    // BL=5  R->W ACT間隔 13cyc (3cycle効率がよい.というかBLが小さいのはEXTRA不要)
    // BL=13 R->W ACT間隔 21cyc (3cycle効率がよい.というかBLが小さいのはEXTRA不要)
    // BL=16 R->W ACT間隔 24cyc (3cycle効率がよい.というかBLが小さいのはEXTRA不要)
    // write -> read -> write
    u_sdramc_master.a_write(32'h0000_0100,15);
    u_sdramc_master.a_read(32'h0000_0100,15);
    u_sdramc_master.a_write(32'h0000_0140,15);
    u_sdramc_master.a_read(32'h0000_0140,15);
    u_sdramc_master.a_write(32'h0000_0180,0);
    u_sdramc_master.a_read(32'h0000_0180,0);
    u_sdramc_master.a_write(32'h0000_01c0,0);
    u_sdramc_master.a_read(32'h0000_01c0,0);
    
    u_sdramc_master.a_write(32'h0000_0180,1);
    u_sdramc_master.a_read(32'h0000_0180,1);
    u_sdramc_master.a_write(32'h0000_01c0,1);
    u_sdramc_master.a_read(32'h0000_01c0,1);
    
    u_sdramc_master.a_write(32'h0000_0180,2);
    u_sdramc_master.a_read(32'h0000_0180,2);
    u_sdramc_master.a_write(32'h0000_01c0,2);
    u_sdramc_master.a_read(32'h0000_01c0,2);

    u_sdramc_master.a_write(32'h0000_0180,3);
    u_sdramc_master.a_read(32'h0000_0180,3);
    u_sdramc_master.a_write(32'h0000_01c0,3);
    u_sdramc_master.a_read(32'h0000_01c0,3);

    u_sdramc_master.a_write(32'h0000_0180,4);
    u_sdramc_master.a_read(32'h0000_0180,4);
    u_sdramc_master.a_write(32'h0000_01c0,4);
    u_sdramc_master.a_read(32'h0000_01c0,4);

    u_sdramc_master.a_write(32'h0000_0180,12);
    u_sdramc_master.a_read(32'h0000_0180,12);
    u_sdramc_master.a_write(32'h0000_01c0,12);
    u_sdramc_master.a_read(32'h0000_01c0,12);

    repeat(100) @(posedge sys_clk);

    testno=3;
    // randomアクセス
    repeat(100) begin
        rand_w = $random%2;
        rand_bank = $random%4;
        rand_bl = $random%16;
        rand_adr = $random%256;
        rand_spc = ($random%8)*10;

        if(rand_w==0)
            u_sdramc_master.a_read({9'b0,rand_bank[1:0],13'b0,rand_adr[7:0]},rand_bl);
        else
            u_sdramc_master.a_write({9'b0,rand_bank[1:0],13'b0,rand_adr[7:0]},rand_bl);
        repeat(rand_spc) @(posedge sys_clk);
    end
    
    repeat(100) @(posedge sys_clk);
    $finish;
    
end

initial begin
    #100;
    @(sim_trap);
    repeat(10000) @(posedge O_sdram_clk);
    $finish;
end

// read data print
initial begin
    #100;
    while(1) begin
        @(posedge sys_clk);
        if(rd_data_valid)
            $write("sdramc: readdata=%h\n",rd_data);
    end
end
endmodule
