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
// write-back, read fill動作

module brd_wb2ps_wc_wb_rfill #
(
    parameter integer BURST_RNUM = 8
)
(
    // System Signals
    input WSHRST,
    input cpuclk,       // wishbone clk

    // System Signals PSRAM
    input PSRST,
    input psclk,       // psram clk

    // write back & ReadFill指示
    // from/to brd_wb2ps_wc_cachectl
    input wire          WB_RUN,
    output wire         WB_RUN_CLR_cpuclk_r,
    input wire [3:0]    WB_w_wayno,  // 4way 1hot
    input wire [9:6]    WB_w_lineno,
    input wire [22:10]  WB_w_tagadr,
    input wire [22:10]  RF_w_tagadr,
    // readfill完了後のwriteデータ
    // readfill時に取得するアドレス
    input wire [31:0]   OW_w_data,
    input wire [3:0]    OW_w_strb,
    input wire [5:2]    OW_w_adr_lsb,
    input wire          OW_w_wvalid,

// read fillした際に入手したアクセスアドレスのデータ
    output reg [31:0]   get_psram_rdata,
    
    // read fillのみ実行
    input wire          RFILL_RUN,
    output wire         RFILL_RUN_CLR_cpuclk_r,

    // softからのWB実行
    input wire          RUN_CLEAN_WB,
    output wire         RUN_CLEAN_WB_CLR_cpuclk,

    // PSRAM IF
    output reg          psram_cmd,
    output reg          psram_cmd_en,
    output reg [22:0]   psram_addr,
    input wire [31:0]   psram_rdata,
    input wire          psram_rvalid,
    output reg [31:0]   psram_wdata,
    output wire [3:0]   psram_mask,
    input wire          psram_ready,
    input wire          psram_ready_clone,
    
    // data cache アクセス
    output wire [9:2]   wb_cache_adr,
    input wire [31:0]   wb_cache_rdata,
    output wire         wb_cache_ren,
    output wire         wb_cache_wen,
    output wire [31:0]  wb_cache_wdata,
    output wire [3:0]   wb_cache_strb,
    output wire [3:0]   wb_cache_wayno,

    // SOFTからのWB指示の時のtag アクセス
    output wire         READ_TAG_SOFTWB,    
    output reg [9:6]    clean_dirty_lineno,
    output reg [3:0]    clean_dirty_wayno,
    input wire [22:10]  clean_dirty_tagadr_i,
    input wire          clean_dirty_dirty_i,
    
    output reg [3:0]    rewrite_tag_clean_dirty,
    // tag書き戻し
    output wire [22:10] rewrite_tagadr_clean_dirty

);


// ---------------------------------
// 内部信号
// ---------------------------------
reg         WB_RUN_sync1;
reg         WB_RUN_sync2;
wire        WB_RUN_psclk;

reg         RFILL_RUN_sync1;
reg         RFILL_RUN_sync2;
wire        RFILL_RUN_psclk;

reg         RUN_CLEAN_WB_sync1;
reg         RUN_CLEAN_WB_sync2;
wire        RUN_CLEAN_WB_psclk;

reg         WB_RUN_CLR_psclk;
reg         WB_RUN_CLR_cpuclk_sync1;
reg         WB_RUN_CLR_cpuclk_sync2;
reg         WB_RUN_CLR_cpuclk_sync3;

reg         RFILL_RUN_CLR_psclk;
reg         RFILL_RUN_CLR_cpuclk_sync1;
reg         RFILL_RUN_CLR_cpuclk_sync2;
reg         RFILL_RUN_CLR_cpuclk_sync3;
wire        RFILL_RUN_CLR_cpuclk;

reg         RUN_CLEAN_WB_CLR_psclk;
reg         RUN_CLEAN_WB_CLR_cpuclk_sync1;
reg         RUN_CLEAN_WB_CLR_cpuclk_sync2;



reg [4:0]   rfill_state;
reg [4:0]   next_rfill_state;

reg [9:6]   WB_read_lineno;
reg [3:0]   WB_read_wayno;  // wayno

reg [3:0]   cache_datacnt;
reg [31:0]  pre_psram_wdata;

wire        cache_ow_timing;

reg         r_STATE_S8;

// ---------------------------------
// WB同期化
// ---------------------------------
always@(posedge psclk or posedge PSRST)
    if(PSRST) begin
        WB_RUN_sync1 <= 1'b0;
        WB_RUN_sync2 <= 1'b0;
        RFILL_RUN_sync1 <= 1'b0;
        RFILL_RUN_sync2 <= 1'b0;
        RUN_CLEAN_WB_sync1 <= 1'b0;
        RUN_CLEAN_WB_sync2 <= 1'b0;
    end
    else begin
        WB_RUN_sync1 <= WB_RUN;
        WB_RUN_sync2 <= WB_RUN_sync1;
        RFILL_RUN_sync1 <= RFILL_RUN;
        RFILL_RUN_sync2 <= RFILL_RUN_sync1;
        RUN_CLEAN_WB_sync1 <= RUN_CLEAN_WB;
        RUN_CLEAN_WB_sync2 <= RUN_CLEAN_WB_sync1;
    end
assign WB_RUN_psclk = WB_RUN_sync2;
assign RFILL_RUN_psclk = RFILL_RUN_sync2;
assign RUN_CLEAN_WB_psclk = RUN_CLEAN_WB_sync2;


always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST) begin
        WB_RUN_CLR_cpuclk_sync1 <= 1'b0;
        WB_RUN_CLR_cpuclk_sync2 <= 1'b0;
        WB_RUN_CLR_cpuclk_sync3 <= 1'b0;
        RUN_CLEAN_WB_CLR_cpuclk_sync1 <= 1'b0;
        RUN_CLEAN_WB_CLR_cpuclk_sync2 <= 1'b0;
        RFILL_RUN_CLR_cpuclk_sync1 <= 1'b0;
        RFILL_RUN_CLR_cpuclk_sync2 <= 1'b0;
        RFILL_RUN_CLR_cpuclk_sync3 <= 1'b0;
    end
    else begin
        WB_RUN_CLR_cpuclk_sync1 <= WB_RUN_CLR_psclk;
        WB_RUN_CLR_cpuclk_sync2 <= WB_RUN_CLR_cpuclk_sync1;
        WB_RUN_CLR_cpuclk_sync3 <= WB_RUN_CLR_cpuclk_sync2;
        RUN_CLEAN_WB_CLR_cpuclk_sync1 <= RUN_CLEAN_WB_CLR_psclk;
        RUN_CLEAN_WB_CLR_cpuclk_sync2 <= RUN_CLEAN_WB_CLR_cpuclk_sync1;
        RFILL_RUN_CLR_cpuclk_sync1 <= RFILL_RUN_CLR_psclk;
        RFILL_RUN_CLR_cpuclk_sync2 <= RFILL_RUN_CLR_cpuclk_sync1;
        RFILL_RUN_CLR_cpuclk_sync3 <= RFILL_RUN_CLR_cpuclk_sync2;
    end

//assign WB_RUN_CLR_cpuclk = WB_RUN_CLR_cpuclk_sync2;
assign WB_RUN_CLR_cpuclk_r = WB_RUN_CLR_cpuclk_sync2&(~WB_RUN_CLR_cpuclk_sync3);
assign RUN_CLEAN_WB_CLR_cpuclk = RUN_CLEAN_WB_CLR_cpuclk_sync2;
assign RFILL_RUN_CLR_cpuclk = RFILL_RUN_CLR_cpuclk_sync2;
assign RFILL_RUN_CLR_cpuclk_r = RFILL_RUN_CLR_cpuclk_sync2 &(~RFILL_RUN_CLR_cpuclk_sync3);
// ---------------------------------
// state machine
// ---------------------------------
parameter   S0  = 5'h00,
            S1  = 5'h01,
            S2  = 5'h02,
            S3  = 5'h03,
            S4  = 5'h04,
            S5  = 5'h05,
            S6  = 5'h06,
            S7  = 5'h07,
            S8  = 5'h08,
            S9  = 5'h09,
            SA  = 5'h0a,
            SB  = 5'h0b,
            SC  = 5'h0c,
            SD  = 5'h0d,
            SE  = 5'h0e,
            SF  = 5'h0f,
            S10 = 5'h10,
            S11 = 5'h11;
            
wire        S0ack=(rfill_state==S0);
wire        S1ack=(rfill_state==S1);
wire        S2ack=(rfill_state==S2);
wire        S3ack=(rfill_state==S3);
wire        S4ack=(rfill_state==S4);
wire        S5ack=(rfill_state==S5);
wire        S6ack=(rfill_state==S6);
wire        S7ack=(rfill_state==S7);
wire        S8ack=(rfill_state==S8);
wire        S9ack=(rfill_state==S9);
wire        SAack=(rfill_state==SA);
wire        SBack=(rfill_state==SB);
wire        SCack=(rfill_state==SC);
wire        SDack=(rfill_state==SD);
wire        SEack=(rfill_state==SE);
wire        SFack=(rfill_state==SF);
wire        S10ack=(rfill_state==S10);
wire        S11ack=(rfill_state==S11);

always@(posedge psclk or posedge PSRST)
    if(PSRST)
        rfill_state <= 5'h00;
    else
        rfill_state <= next_rfill_state;


always@* begin
    case (rfill_state)
        S0 : if(WB_RUN_psclk)
                next_rfill_state = S1;
             else if(RUN_CLEAN_WB_psclk)
                next_rfill_state = SA;
             else if(RFILL_RUN_psclk)
                next_rfill_state = S4;
             else
                next_rfill_state = S0;
        //S1 : next_rfill_state = S2;
        S1 : next_rfill_state = SF;
        S2 : if(psram_ready)
                next_rfill_state = S3;
             else
                next_rfill_state = S2;
        S3 : if(cache_datacnt==4'hf)
                next_rfill_state = S4;    // readfill
             else
                next_rfill_state = S3;
        S4 : next_rfill_state = S5;
        S5 : if(psram_ready)
                next_rfill_state = S6;
             else
                next_rfill_state = S5;
        S6 : if ( psram_rvalid&(cache_datacnt==4'hf)) begin
                if(OW_w_wvalid)
                    next_rfill_state = S8;
                else
                    next_rfill_state = S7;
             end
             else
                next_rfill_state = S6;
        S7 : if((~WB_RUN_sync2)&(~RFILL_RUN_sync2)&
                (~RUN_CLEAN_WB_psclk) )
                next_rfill_state = S0;
             else
                next_rfill_state = S7;
        S8 : next_rfill_state = S7;
        //SA : next_rfill_state = SB;
        SA : next_rfill_state = SF;
        SB : if(~clean_dirty_dirty_i&RUN_CLEAN_WB_psclk)
                next_rfill_state = SE;
             else
                next_rfill_state = SC;
        SC : next_rfill_state = S10;
        S10 : if(psram_ready)
                next_rfill_state = SD;
             else
                next_rfill_state = S10;
        SD : if(cache_datacnt==4'hf) begin
                if(WB_RUN_psclk)
                    next_rfill_state = S4;
                else begin
                    if((clean_dirty_wayno==4'h8)&(clean_dirty_lineno==4'hf))
                        next_rfill_state = S7;
                    else
                        next_rfill_state = SE;    // readfill
                end
             end
             else
                next_rfill_state = SD;
        SE : if((clean_dirty_wayno==4'h8)&(clean_dirty_lineno==4'hf))
                next_rfill_state = S7;
             else
                next_rfill_state = SA;
        SF : next_rfill_state = SB;
        
        default : next_rfill_state = S0;
    endcase
end

// ---------------------------------
// StateのFF化
// ---------------------------------

always@(posedge psclk)
    r_STATE_S8 <= (next_rfill_state==S8);
    

// ---------------------------------
// 各種要求信号の取得
// 信号が安定しているところで取り込み
// するのでシンクロナイザーは不要
// ---------------------------------
always@(posedge psclk) begin
    WB_read_lineno <= WB_w_lineno;
    WB_read_wayno <= WB_w_wayno;
end

// ---------------------------------
// cache データカウンタ
// cache_datacnt
// ---------------------------------
always@(posedge psclk or posedge PSRST )
    if(PSRST)
        cache_datacnt <= 4'h0;
    //else if((S0ack&(~WB_RUN_sync2))|SAack)
    else if(S0ack | S1ack | SAack)
        cache_datacnt <= 4'h0;
    else if(SBack&RUN_CLEAN_WB_psclk&(~clean_dirty_dirty_i))
        cache_datacnt <= 4'h0;
    //else if((S0ack & WB_RUN_sync2)|SBack)
    else if(SBack)
        cache_datacnt <= cache_datacnt + 4'h1;
    //else if((S2ack|S10ack) & psram_ready)
    else if(S10ack & psram_ready)
        cache_datacnt <= cache_datacnt + 4'h1;
    //else if(S3ack|SCack|SDack)
    else if(SCack|SDack)
        cache_datacnt <= cache_datacnt + 4'h1;
    else if(S5ack&(~RFILL_RUN_sync2))
        cache_datacnt <= 4'h0;
    else if(S6ack&psram_rvalid)
        cache_datacnt <= cache_datacnt + 4'h1;
        
// ---------------------------------
// cache RAM制御
// ---------------------------------
//assign cache_ow_timing = S8ack;
assign cache_ow_timing = r_STATE_S8;
assign wb_cache_adr = cache_ow_timing ? {WB_w_lineno,OW_w_adr_lsb} :
                      RUN_CLEAN_WB_psclk ? {clean_dirty_lineno, cache_datacnt[3:0]}:
                      {WB_read_lineno,cache_datacnt[3:0]};
assign wb_cache_ren = ( // (S0ack&WB_RUN_sync2)|S1ack|S2ack|S3ack|
                       SFack|SCack|(S10ack&psram_ready_clone)|SDack );
assign wb_cache_wen = psram_rvalid|cache_ow_timing;
assign wb_cache_wdata = cache_ow_timing ? OW_w_data :
                        psram_rdata;
assign wb_cache_strb = cache_ow_timing ? OW_w_strb :
                        4'hf;
assign wb_cache_wayno = RUN_CLEAN_WB_psclk ?
                        clean_dirty_wayno : WB_read_wayno;

assign READ_TAG_SOFTWB = SAack;

always@(posedge psclk )
    rewrite_tag_clean_dirty <= {4{SAack}}&clean_dirty_wayno;

assign rewrite_tagadr_clean_dirty = clean_dirty_tagadr_i;
// ---------------------------------
// tag linenoカウンタ
// ---------------------------------
always@(posedge psclk )
    if(S0ack)
        clean_dirty_lineno <= 4'h0;
    else if(SEack)
        clean_dirty_lineno <= clean_dirty_lineno + 4'h1;
always@(posedge psclk )
    if(S0ack)
        clean_dirty_wayno <= 4'h1;
    else if(SEack & (clean_dirty_lineno==4'hf))
        clean_dirty_wayno <= clean_dirty_wayno << 1;


// ---------------------------------
// MISS read時、PSRAMからreadした値を、横で取得し
// 後でwish bone バスへ投げる
// ---------------------------------
always@(posedge psclk )
    if(S6ack&psram_rvalid) begin
        if(cache_datacnt==OW_w_adr_lsb)
            get_psram_rdata <= psram_rdata;
    end
        
// ---------------------------------
// PSRAM I/F
// ---------------------------------
always@(posedge psclk or posedge PSRST )
    if(PSRST)
        psram_cmd_en <= 1'b0;
     //else if((S2ack|S5ack|S10ack) & psram_ready)
     else if((S5ack|S10ack) & psram_ready)
        psram_cmd_en <= 1'b0;
     //else if(S1ack|S4ack|(SBack&clean_dirty_dirty_i))
     else if(S4ack|(SBack&WB_RUN_psclk)|
            (SBack&RUN_CLEAN_WB_psclk&clean_dirty_dirty_i)
            )
        psram_cmd_en <= 1'b1;

always@(posedge psclk )
    //if(S1ack|SBack)
    if(SBack)
        psram_cmd <= 1'b1;  // write
    else if(S4ack)
        psram_cmd <= 1'b0;  // read

always@(posedge psclk )
    //if(S1ack)
    //    psram_addr <= {WB_w_tagadr,WB_w_lineno,6'h00};
    if(S4ack)
        psram_addr <= {RF_w_tagadr,WB_w_lineno,6'h00};
    else if(SBack) begin
        if(WB_RUN_psclk)
            psram_addr <= {WB_w_tagadr,WB_w_lineno,6'h00};
        else
            psram_addr <= {clean_dirty_tagadr_i,clean_dirty_lineno,6'h00};
    end

always@(posedge psclk )
    //if(S1ack|SBack|(S10ack&psram_ready)|SDack|SEack|S7ack)
    if(S4ack|SBack|(S10ack&psram_ready_clone)|SDack|SEack|S7ack)
        psram_wdata <= wb_cache_rdata;

//assign psram_wdata =  (S2ack|SCack|S10ack|SDack|SEack|SAack|S7ack) ? pre_psram_wdata :
//assign psram_wdata =  (SCack|S10ack|SDack|SEack|SAack|S7ack) ? pre_psram_wdata :
//                        wb_cache_rdata;
assign psram_mask = 4'h0;

always@(posedge psclk or posedge PSRST )
    if(PSRST)
        WB_RUN_CLR_psclk <= 1'b0;
    else if(~WB_RUN_psclk)  // WB_RUNをpsclkへ載せ替えたもの。WB_RUNはこのCLR信号を受けて"L"になる
        WB_RUN_CLR_psclk <= 1'b0;
    else if(r_STATE_S8|S7ack)
        WB_RUN_CLR_psclk <= 1'b1;
    

always@(posedge psclk or posedge PSRST )
    if(PSRST)
        RUN_CLEAN_WB_CLR_psclk <= 1'b0;
    else if(~RUN_CLEAN_WB_psclk)  // cpuclkへ乗換へ、更にpsclkへ乗り換えて戻ってきたら
        RUN_CLEAN_WB_CLR_psclk <= 1'b0;
    //else if(SDack&(cache_datacnt==4'hf)&(clean_dirty_lineno==4'hf)&(clean_dirty_wayno==4'h8))
    else if(S7ack)
        RUN_CLEAN_WB_CLR_psclk <= 1'b1;

always@(posedge psclk or posedge PSRST )
    if(PSRST)
        RFILL_RUN_CLR_psclk <= 1'b0;
    else if(~RFILL_RUN_psclk)  // cpuclkへ乗換へ、更にpsclkへ乗り換えて戻ってきたら
        RFILL_RUN_CLR_psclk <= 1'b0;
    else if(S7ack)
        RFILL_RUN_CLR_psclk <= 1'b1;

endmodule
