`timescale 1ns/1ps
// WISH_BORN バス <-> PSRAM bridge回路
// fifo型
//
// fifo制御部
module brd_wb2ps_wc_fifodma
(
    // System Signals
    input           WSHRST,
    input           cpuclk,       // wishbone clk

    // System Signals PSRAM
    input           PSRST,
    input           psclk,       // psram clk

    input           fifo_wdata_wen2,
    input [31:0]    fifo_wdata,
    input [31:0]    fifo_wadrs,
    input [31:0]    fifo_warea,
    input           fifo_startp,
    input           fifo_endp,
    output wire     fifo_almost_full,
    output wire     fifo_run,
    output wire     fifo_run_endp,
    
    // PSRAM IF
    output reg          psram_cmd_en,
    output wire         psram_cmd,
    output reg [22:0]   psram_addr,
    //input wire [31:0]   psram_rdata,
    //input wire          psram_rvalid,
    output reg  [31:0]  psram_wdata,
    output wire [3:0]   psram_mask,
    input wire          psram_ready
);


// ---------------------------------
// 内部信号
// ---------------------------------
reg [6:0]   fifo_wpt_cpuclk;       // 16x4段x2 = 128
reg [6:0]   fifo_rpt_cpuclk;       // 16x4段x2 = 128
reg         fifo_ready_cpuclk;
reg         fifo_ready_psclk_sync1;
reg         fifo_ready_psclk_sync2;
reg         fifo_ready_psclk_sync3;
wire        fifo_ready_psclk_r;
wire        fifo_ready;
wire        fifo_full;
//wire        fifo_almost_full;

reg [6:0]   fifo_wpt_psclk;       // 64byte毎

reg         fifo_rpt_inc_psclk;
reg         fifo_rpt_inc_cpuclk_sync1;
reg         fifo_rpt_inc_cpuclk_sync2;
reg         fifo_rpt_inc_cpuclk_sync3;
reg         fifo_rpt_inc_cpuclk_sync4;
wire        fifo_rpt_inc_rise;

reg         fifo_rpt_inc_clear_cpuclk;
reg         fifo_rpt_inc_clear_psclk_sync1;
reg         fifo_rpt_inc_clear_psclk_sync2;
reg         fifo_rpt_inc_clear_psclk_sync3;
wire        fifo_rpt_inc_clear_psclk_rise;

reg [2:0]   fifo_state;
reg [2:0]   next_fifo_state;

reg [5:0]   fifo_rpt_psram;
reg [19:0]  trans_cnt;

wire        fifo_ram_ren;
reg         fifo_rdata_valid;
wire [31:0] fifo_rdata;
//reg [31:0]  fifo_rdata_1st;
//reg [31:0]  psram_wdata_l;

reg         fifo_start_lvl;
reg         fifo_run_psclk;
reg         fifo_run_cpuclk_sync1;
reg         fifo_run_cpuclk_sync2;
reg         fifo_run_cpuclk_sync3;

parameter   S0  = 3'h0,
            S1  = 3'h1,
            S2  = 3'h2,
            S3  = 3'h3,
            S4  = 3'h4,
            S5  = 3'h5,
            S6  = 3'h6,
            S7  = 3'h7;
            
wire        S0ack=(fifo_state==S0);
wire        S1ack=(fifo_state==S1);
wire        S2ack=(fifo_state==S2);
wire        S3ack=(fifo_state==S3);
wire        S4ack=(fifo_state==S4);
wire        S5ack=(fifo_state==S5);
wire        S6ack=(fifo_state==S6);
wire        S7ack=(fifo_state==S7);


// ---------------------------------
// fifo instance
// ---------------------------------
fifo_1rd1wr #(
    .DATA_WIDTH(32),
    .ADDR_WIDTH(6)  // 64byte x 4 -> 6bit
    ) u_fifo_1rd1wr
(
    // write port
    .clkA(cpuclk),
    .enaA(fifo_wdata_wen2), 
    .weA(fifo_wdata_wen2),
    .addrA(fifo_wpt_cpuclk[5:0]),    // 64byte x 4
    .dinA(fifo_wdata),     // in 32bit
       
    // read port
    .clkB(psclk),
    .enaB(fifo_ram_ren),
    .addrB(fifo_rpt_psram),
    .doutB(fifo_rdata)
);

// ---------------------------------
// fifo_start_lvl
// ---------------------------------
always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        fifo_start_lvl <= 1'b0;
    else if(fifo_endp)
        fifo_start_lvl <= 1'b0;
    else if(fifo_startp)
        fifo_start_lvl <= 1'b1;
// ---------------------------------
// fifo wpt/rpt cpuclk 4byte毎
// ---------------------------------
always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        fifo_wpt_cpuclk <= 7'h00;
    else if(fifo_wdata_wen2)
        fifo_wpt_cpuclk <= fifo_wpt_cpuclk + 7'h01;

always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        fifo_rpt_cpuclk <= 7'h00;
    else if(fifo_rpt_inc_rise)
        fifo_rpt_cpuclk <= fifo_rpt_cpuclk + 7'h10;

// ---------------------------------
// fifo データがたまった？
// almost fullでreadyアサート
// ---------------------------------
wire [6:0] fifo_delta = fifo_wpt_cpuclk - fifo_rpt_cpuclk;
assign fifo_ready = (|fifo_delta[6:4]);
assign fifo_full = (fifo_wpt_cpuclk[6]!=fifo_rpt_cpuclk[6])&
                    (fifo_delta[5:0]==6'h00);
assign fifo_almost_full =  fifo_run&((fifo_delta[5:0]==6'h3f)|fifo_full);

always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        fifo_ready_cpuclk <= 1'b0;
    else
        fifo_ready_cpuclk <= fifo_ready;

// ---------------------------------
// fifo_ready_coreclk同期化
// ---------------------------------
always@(posedge psclk or posedge PSRST)
    if(PSRST) begin
        fifo_ready_psclk_sync1 <= 1'b0;
        fifo_ready_psclk_sync2 <= 1'b0;
        fifo_ready_psclk_sync3 <= 1'b0;
    end
    else begin
        fifo_ready_psclk_sync1 <= (fifo_ready_cpuclk&fifo_start_lvl);
        fifo_ready_psclk_sync2 <= fifo_ready_psclk_sync1;
        fifo_ready_psclk_sync3 <= fifo_ready_psclk_sync2;
    end

assign fifo_ready_psclk_r = fifo_ready_psclk_sync2 & (~fifo_ready_psclk_sync3);

// ---------------------------------
// fifo_state
// ---------------------------------

always@(posedge psclk or posedge PSRST)
    if(PSRST)
        fifo_state <= 3'h0;
    else
        fifo_state <= next_fifo_state;


always@* begin
    case (fifo_state)
        S0 : if(fifo_ready_psclk_r)
                next_fifo_state = S1;
             else
                next_fifo_state = S0;
        S1 : if(psram_ready)
                next_fifo_state = S4;
             else
                next_fifo_state = S1;
        //S2 : if(trans_cnt==20'h0_0000)
        //        next_fifo_state = S0;
        //     else
        //        next_fifo_state = S3;
        S2 : next_fifo_state = S5;
        S3 : if(fifo_ready_psclk_sync2)
                next_fifo_state = S1;
             else
                next_fifo_state = S3;
        S4 : if(fifo_rpt_psram[3:0]==4'hf)
                next_fifo_state = S2;
             else
                next_fifo_state = S4;
        S5 : if(fifo_rpt_inc_clear_psclk_sync3) begin
                if(trans_cnt==20'h0_0000)
                    next_fifo_state = S0;
                else
                    next_fifo_state = S3;
             end
             else
                next_fifo_state = S5;
        default : next_fifo_state = S0;
    endcase
end


// ---------------------------------
// fifo_rpt_psram
// ---------------------------------
always@(posedge psclk or posedge PSRST)
    if(PSRST)
        fifo_rpt_psram <= 6'h0;
    else if(S0ack)
        fifo_rpt_psram <= 6'h0;
    else if(S1ack) begin
        if((fifo_rpt_psram[3:0]==4'h0)|(fifo_rpt_psram[3:0]==4'h1)|psram_ready)
            fifo_rpt_psram <= fifo_rpt_psram + 6'h1;
    end
    else if(S4ack)
        fifo_rpt_psram <= fifo_rpt_psram + 6'h1;
        
assign fifo_ram_ren = S1ack&(
                        (fifo_rpt_psram[3:0]==4'h0)|
                        (fifo_rpt_psram[3:0]==4'h1)|
                        psram_ready) |
                      S4ack;

// ---------------------------------
// fifo_rdata 有効区間
// ---------------------------------
always@(posedge psclk or posedge PSRST)
    if(PSRST)
        fifo_rdata_valid <= 1'b0;
    else
        fifo_rdata_valid <= fifo_ram_ren;

// ---------------------------------
// 1個目だけfifi_rdata を取り込む
// ---------------------------------
//always@(posedge psclk)
//    if(fifo_rdata_valid&(fifo_rpt_psram[3:0]==4'h1))
//        fifo_rdata_1st <= fifo_rdata;
        
// ---------------------------------
// fifo_rpt_inc
// ---------------------------------
always@(posedge psclk or posedge PSRST)
    if(PSRST)
        fifo_rpt_inc_psclk <= 1'b0;
    else if(fifo_rpt_inc_clear_psclk_rise)
        fifo_rpt_inc_psclk <= 1'b0;
    else if(S2ack)
        fifo_rpt_inc_psclk <= 1'b1;

always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST) begin
        fifo_rpt_inc_cpuclk_sync1 <= 1'b0;
        fifo_rpt_inc_cpuclk_sync2 <= 1'b0;
        fifo_rpt_inc_cpuclk_sync3 <= 1'b0;
        fifo_rpt_inc_cpuclk_sync4 <= 1'b0;
    end
    else begin
        fifo_rpt_inc_cpuclk_sync1 <= fifo_rpt_inc_psclk;
        fifo_rpt_inc_cpuclk_sync2 <= fifo_rpt_inc_cpuclk_sync1;
        fifo_rpt_inc_cpuclk_sync3 <= fifo_rpt_inc_cpuclk_sync2;
        fifo_rpt_inc_cpuclk_sync4 <= fifo_rpt_inc_cpuclk_sync3;
    end

assign fifo_rpt_inc_rise = fifo_rpt_inc_cpuclk_sync2 & (~fifo_rpt_inc_cpuclk_sync3);

always@(posedge psclk or posedge PSRST)
    if(PSRST) begin
        fifo_rpt_inc_clear_psclk_sync1 <= 1'b0;
        fifo_rpt_inc_clear_psclk_sync2 <= 1'b0;
        fifo_rpt_inc_clear_psclk_sync3 <= 1'b0;
    end
    else begin
        fifo_rpt_inc_clear_psclk_sync1 <= fifo_rpt_inc_cpuclk_sync4;
        fifo_rpt_inc_clear_psclk_sync2 <= fifo_rpt_inc_clear_psclk_sync1;
        fifo_rpt_inc_clear_psclk_sync3 <= fifo_rpt_inc_clear_psclk_sync2;
    end

assign fifo_rpt_inc_clear_psclk_rise = fifo_rpt_inc_clear_psclk_sync2&(~fifo_rpt_inc_clear_psclk_sync3);

// ---------------------------------
// trans_cnt
// ---------------------------------
always@(posedge psclk)
    if(S0ack&fifo_ready_psclk_r)
        trans_cnt <= fifo_warea[25:6];
    else if(S2ack)
        trans_cnt <= trans_cnt - 20'h0_0001;

// ---------------------------------
// status
// ---------------------------------
always@(posedge psclk or posedge PSRST)
    if(PSRST)
        fifo_run_psclk <= 1'b0;
    else
        fifo_run_psclk <= (~S0ack);

always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST) begin
        fifo_run_cpuclk_sync1 <= 1'b0;
        fifo_run_cpuclk_sync2 <= 1'b0;
        fifo_run_cpuclk_sync3 <= 1'b0;
    end
    else begin
        fifo_run_cpuclk_sync1 <= fifo_run_psclk;
        fifo_run_cpuclk_sync2 <= fifo_run_cpuclk_sync1;
        fifo_run_cpuclk_sync3 <= fifo_run_cpuclk_sync2;
    end

assign fifo_run= fifo_run_cpuclk_sync2;
assign fifo_run_endp = ~fifo_run_cpuclk_sync2 & fifo_run_cpuclk_sync3;

// ---------------------------------
// PSRAM I/F
// ---------------------------------
always@(posedge psclk or posedge PSRST)
    if(PSRST)
        psram_cmd_en <= 1'b0;
    else
        psram_cmd_en <= S1ack&(~psram_ready);

assign psram_cmd = 1'b1;     // write only

always@(posedge psclk)
    if(S0ack&fifo_ready_psclk_r)
        psram_addr <= {fifo_wadrs[22:6],6'h00};
    else if(S2ack)
        psram_addr <= psram_addr + 23'd64;

//always@(posedge psclk)
//    if((S1ack&psram_ready)|S4ack|S2ack)
//        psram_wdata_l <= fifo_rdata;

always@(posedge psclk)
    if(fifo_ram_ren|S2ack)
        psram_wdata <= fifo_rdata;

//assign psram_wdata =  S1ack ? fifo_rdata_1st : psram_wdata_l;

assign psram_mask = 4'h0;
        
endmodule
