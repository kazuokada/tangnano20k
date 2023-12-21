`timescale 1ns/1ps
// WISH_BORN バス <-> PSRAM bridge回路
// cache 付き
// cache 構成
//   4way
//   64byte/line
//   16line/way
//   width 32bit
// -> 4*16*64byte = 4096byte
// 22   10| 9     6|5   0
// tag_adr|lineno  | 64byte
//
//
module brd_wb2ps_wc_enter #
(
    parameter integer BURST_RNUM = 8
)
(
    // System Signals
    input WSHRST,
    input cpuclk,       // wishbone clk

    // PSRAM IF
    // cpuclk domain
    input wire [22:0]   ps_mem_addr,
    input wire [31:0]   ps_mem_wdata,
    output reg [31:0]   ps_mem_rdata,
    input wire [3:0]    ps_mem_wstrb,
    input wire          ps_mem_valid,
    output wire         ps_mem_ready,

    // cache判定用
    output reg [22:0]   buf_addr,
    output reg          buf_wvalid,
    output reg          buf_rvalid,
    output reg [31:0]   buf_wdata,
    output reg [3:0]    buf_wstrb,
    
    
    // TAG/DATA read ctl
    // 4way
    output wire         READ_TAG,
    output wire [9:6]   read_lineno,
    output wire         READ_DATA_BUS,  // bus出力用リード
    output wire [5:2]   read_adr_lsb,
    
    // tag初期化タイミング
    input              run_inittag,

    // cache 状態
    input               MISS,
    input [3:0]         HIT_way,
    input               WB_RUN,
    input               WB_RUN_CLR_cpuclk_r,
    input               RFILL_RUN,
    input               RFILL_RUN_CLR_cpuclk_r,
    
    //  read fillした際に入手したアクセスアドレスのデータ
    input wire [31:0]   get_psram_rdata,
    // read hitしたときのcache data
    input wire [31:0]   cache_rdata0,
    input wire [31:0]   cache_rdata1,
    input wire [31:0]   cache_rdata2,
    input wire [31:0]   cache_rdata3
    

);

// ---------------------------------
// 内部信号
// ---------------------------------
reg [2:0]   state;
reg [2:0]   next_state;
reg         pre_ps_mem_ready;
reg         S3ack_2;

// ---------------------------------
// wbuf (バスを一旦ラッチ)
// ---------------------------------
always@(posedge cpuclk)
    if(ps_mem_valid & (~run_inittag)) begin
        buf_addr <= ps_mem_addr;
        buf_wvalid <= ps_mem_valid & (|ps_mem_wstrb);
        buf_rvalid <= ps_mem_valid & (ps_mem_wstrb==4'h0);
        buf_wstrb <= ps_mem_wstrb;
        buf_wdata <= ps_mem_wdata;
        
    end

// ---------------------------------
// bus state
// ---------------------------------
// ---------------------------------
// state machine
// ---------------------------------
parameter   S0  = 3'h0,
            S1  = 3'h1,
            S2  = 3'h2,
            S3  = 3'h3,
            S4  = 3'h4,
            S5  = 3'h5,
            S6  = 3'h6,
            S7  = 3'h7;
            
wire        S0ack=(state==S0);
wire        S1ack=(state==S1);
wire        S2ack=(state==S2);
wire        S3ack=(state==S3);
wire        S4ack=(state==S4);
wire        start_S3ack = S3ack & (~S3ack_2);

always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        S3ack_2 <= 1'b0;
    else
        S3ack_2 <= S3ack;
        
always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        state <= 3'h0;
    else
        state <= next_state;


always@* begin
    case (state)
        S0 : if(run_inittag)
                next_state = S0;
             else if(MISS)
                next_state = S2;
             else if(ps_mem_valid) begin
                if(ps_mem_wstrb==4'h0)
                    next_state = S3;
                else
                    next_state = S1;
             end
             else
                next_state = S0;
        S1 : next_state = S0;
/*
        S2 : if(ps_mem_valid&(ps_mem_wstrb==4'h0)) begin
                if(RFILL_RUN_CLR_cpuclk_r|WB_RUN_CLR_cpuclk_r)
                    next_state = S3;
                else
                    next_state = S2;
             end
             else if(WB_RUN|RFILL_RUN)
                next_state = S2;
             else
                next_state = S0;
*/

        S2 : if(WB_RUN|RFILL_RUN) begin
                if(RFILL_RUN_CLR_cpuclk_r|WB_RUN_CLR_cpuclk_r) begin
                    if(ps_mem_valid) begin
                        if(ps_mem_wstrb==4'h0)  // read
                            next_state = S3;
                        else                    // write
                            next_state = S2;
                    end
                    else
                        next_state = S0;
                end
                else
                    next_state = S2;
            end
            else
                next_state = S0;

        S3 : if(RFILL_RUN_CLR_cpuclk_r|WB_RUN_CLR_cpuclk_r|
                (|HIT_way))
                next_state = S4;
             else
                next_state = S3;
        S4 : next_state = S0;
        default : next_state = S0;
    endcase
end

// ---------------------------------
// ready
// ---------------------------------
always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        pre_ps_mem_ready <= 1'b0;
    else if(((S1ack|S2ack)&ps_mem_ready)|run_inittag)
        pre_ps_mem_ready <= 1'b0;
    // 基本reday=0でバスアクセスの後半だけ"H"にするルールなので
    // 以下はNG
    //else if(~ps_mem_valid&S0ack) // busアクセスない時
    //    pre_ps_mem_ready <= 1'b1;
    else if(ps_mem_valid&(|ps_mem_wstrb)&(S0ack|S2ack))    // write時
        pre_ps_mem_ready <= 1'b1;
    //else    // read時
    //    pre_ps_mem_ready <= RFILL_RUN_CLR_f |;

assign ps_mem_ready = S4ack | pre_ps_mem_ready&(~(WB_RUN|RFILL_RUN));

           
// ---------------------------------
// tag リード制御
// ---------------------------------
// READ_TAG (tag ram ren)
// ---------------------------------
//assign READ_TAG = pre_ps_mem_ready&(~(WB_RUN|RFILL_RUN));
assign READ_TAG = (S1ack|(S2ack&ps_mem_valid&(~(WB_RUN|RFILL_RUN)))|
                    start_S3ack
                    );

assign READ_DATA_BUS = start_S3ack;

// ---------------------------------
// read_lineno
// ---------------------------------
assign read_lineno = buf_addr[9:6];

assign read_adr_lsb =  buf_addr[5:2];
// ---------------------------------
// wish bone read data
// ---------------------------------
wire [31:0] sel_cache_rdata =
                {32{HIT_way[3]}}&cache_rdata3 |
                {32{HIT_way[2]}}&cache_rdata2 |
                {32{HIT_way[1]}}&cache_rdata1 |
                {32{HIT_way[0]}}&cache_rdata0 ;
always@(posedge cpuclk)
    if((RFILL_RUN & RFILL_RUN_CLR_cpuclk_r)|
        (WB_RUN|WB_RUN_CLR_cpuclk_r))
        ps_mem_rdata <= get_psram_rdata;
    else if(|HIT_way)
        ps_mem_rdata = sel_cache_rdata;

endmodule
