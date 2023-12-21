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
// cache tag/data 制御部
//
module brd_wb2ps_wc_cacheram_ctl #
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

    // TAG/DATA read ctl
    // 4way
    input wire          READ_TAG,
    input wire [9:6]    read_lineno,
    input wire          READ_DATA_BUS,  // bus出力用リード
    input wire [5:2]    read_adr_lsb,

    // to cache_ctl
    output wire [22:10] tag_addr0,
    output reg [1:0]    tag_lru0,
    output wire         tag_valid0,
    output wire         tag_dirty0,

    output wire [22:10] tag_addr1,
    output reg [1:0]    tag_lru1,
    output wire         tag_valid1,
    output wire         tag_dirty1,

    output wire [22:10] tag_addr2,
    output reg [1:0]    tag_lru2,
    output wire         tag_valid2,
    output wire         tag_dirty2,

    output wire [22:10] tag_addr3,
    output reg [1:0]    tag_lru3,
    output wire         tag_valid3,
    output wire         tag_dirty3,

    // tag ram write : from cachectl
    // cpuclk
    input wire [1:0]    w_lru0,
    input wire [1:0]    w_lru1,
    input wire [1:0]    w_lru2,
    input wire [1:0]    w_lru3,
    input wire          rewrite_lru,

    //input reg [9:6]     r_w_lineno, // WB以降

    input wire [3:0]    rewrite_tag,
    input wire [22:10]  w_tagadr,
    input wire          w_valid,
    input wire          w_dirty,

    // cache data ram write : from cachectl
    // WHIT時
    input wire [3:0]    w_dc,   // 4way
    input wire [22:2]   r_w_adrs,
    input wire [31:0]   r_w_wdata,
    input wire [3:0]    r_w_strb,
    
    // data cache アクセス from brd_wb2ps_wc_wb_rfill
    // psclk
    input wire [9:2]    wb_cache_adr,
    output wire [31:0]  wb_cache_rdata,
    input wire          wb_cache_ren,
    input wire          wb_cache_wen,
    input wire [31:0]   wb_cache_wdata,
    input wire [3:0]    wb_cache_strb,
    input wire [3:0]    wb_cache_wayno,
    
    // data cache アクセス from brd_wb2ps_wc_enter
    // cpuclk
    output wire [31:0]  rf_cache_rdata0,
    output wire [31:0]  rf_cache_rdata1,
    output wire [31:0]  rf_cache_rdata2,
    output wire [31:0]  rf_cache_rdata3,

    // soft wb
    input wire          READ_TAG_SOFTWB,
    input wire [9:6]    clean_dirty_lineno,
    input wire [3:0]    clean_dirty_wayno,
    output wire [22:10] clean_dirty_tagadr_o,
    output wire         clean_dirty_dirty_o,
    output wire         clean_dirty_valid_o,

    input wire [3:0]    rewrite_tag_clean_dirty, // tag書き換え指示
    input wire [22:10]  rewrite_tagadr_clean_dirty,

    // tag ram init
    input               taginit_en,
    input wire [9:6]    taginit_lineno


);


// ---------------------------------
// 内部信号
// ---------------------------------
reg [1:0]   lru0[0:15];
reg [1:0]   lru1[0:15];
reg [1:0]   lru2[0:15];
reg [1:0]   lru3[0:15];

// ---------------------------------
// tag ram inst
// tagdata 構成
//   [14]  [13]    [12:0]
// {dirty, valid,  addr}
// ---------------------------------
// lruはFF

// lruのみ毎回差し替える。
// lru以外のtagは最古wayだけが書き換え対象
always@(posedge cpuclk)
    if(taginit_en) begin
        lru0[taginit_lineno] <= 2'b11; //最初の書き換え対象なので最大値
        lru1[taginit_lineno] <= 2'b10;
        lru2[taginit_lineno] <= 2'b01;
        lru3[taginit_lineno] <= 2'b00;
    end
    else if(rewrite_lru) begin    // Hit時,miss時のフィル動作時
        lru0[read_lineno] <= w_lru0;
        lru1[read_lineno] <= w_lru1;
        lru2[read_lineno] <= w_lru2;
        lru3[read_lineno] <= w_lru3;
    end
    

always@(posedge cpuclk)
    if(READ_TAG) begin
        tag_lru0 <= lru0[read_lineno];
        tag_lru1 <= lru1[read_lineno];
        tag_lru2 <= lru2[read_lineno];
        tag_lru3 <= lru3[read_lineno];
    end

wire [14:0] doutB0;
wire [14:0] doutB1;
wire [14:0] doutB2;
wire [14:0] doutB3;

reg [14:0] l_doutB0;
reg [14:0] l_doutB1;
reg [14:0] l_doutB2;
reg [14:0] l_doutB3;

reg     READ_TAG_SOFTWB2;
//reg     READ_TAG_SOFTWB3;

always@(posedge psclk) begin
    READ_TAG_SOFTWB2 <= READ_TAG_SOFTWB;
    //READ_TAG_SOFTWB3 <= READ_TAG_SOFTWB2;
end

always@(posedge psclk)
    if(READ_TAG_SOFTWB2) begin
        l_doutB0 <= doutB0;
        l_doutB1 <= doutB1;
        l_doutB2 <= doutB2;
        l_doutB3 <= doutB3;
    end

assign {clean_dirty_dirty_o,clean_dirty_valid_o,
       clean_dirty_tagadr_o} =
       clean_dirty_wayno[0] ? l_doutB0:
       clean_dirty_wayno[1] ? l_doutB1:
       clean_dirty_wayno[2] ? l_doutB2: l_doutB3;
       
DPRAM_WRAP #(
    .ADDR_WIDTH (4),        // 16word
    .DATA_WIDTH (1+1+13)      // dirty,valid, adr[22:10]
    ) cache_tag_way0
    (
    .clkA(cpuclk),
    .weA(taginit_en ? 1'b1 : rewrite_tag[0]),
    //.ul_en(2'b11),
    .enA(taginit_en ? 1'b1 : (READ_TAG|rewrite_tag[0])),
    .addrA(taginit_en ? taginit_lineno : read_lineno),
    .dinA(taginit_en ? 15'h0000 : {w_dirty, w_valid,w_tagadr}),
    .doutA({tag_dirty0,tag_valid0,tag_addr0}),

    .clkB(psclk),
    .weB(rewrite_tag_clean_dirty[0]),
    .enB((READ_TAG_SOFTWB&clean_dirty_wayno[0])|
            rewrite_tag_clean_dirty[0]),
    .addrB(clean_dirty_lineno),
    .dinB({1'b0,1'b1,rewrite_tagadr_clean_dirty}),
    .doutB(doutB0)
    );
    
    
DPRAM_WRAP #(
    .ADDR_WIDTH (4),        // 16word
    .DATA_WIDTH (1+1+13)      // dirty,valid, adr[22:10]
    ) cache_tag_way1
    (
    .clkA(cpuclk),
    .weA(taginit_en ? 1'b1 : rewrite_tag[1]),
    //.ul_en(2'b11),
    .enA(taginit_en ? 1'b1 : (READ_TAG | rewrite_tag[1])),
    .addrA(taginit_en ? taginit_lineno : read_lineno),
    .dinA(taginit_en ? 15'h0000 : {w_dirty, w_valid,w_tagadr}),
    .doutA({tag_dirty1,tag_valid1,tag_addr1}),

    .clkB(psclk),
    .weB(rewrite_tag_clean_dirty[1]),
    .enB((READ_TAG_SOFTWB&clean_dirty_wayno[1])|
            rewrite_tag_clean_dirty[1]),
    .addrB(clean_dirty_lineno),
    .dinB({1'b0,1'b1,rewrite_tagadr_clean_dirty}),
    .doutB(doutB1)
    
    );
DPRAM_WRAP #(
    .ADDR_WIDTH (4),        // 16word
    .DATA_WIDTH (1+1+13)      // dirty,valid, adr[22:10]
    ) cache_tag_way2
    (
    .clkA(cpuclk),
    .weA(taginit_en ? 1'b1 : rewrite_tag[2]),
    //.ul_en(2'b11),
    .enA(taginit_en ? 1'b1 : (READ_TAG | rewrite_tag[2])),
    .addrA(taginit_en ? taginit_lineno : read_lineno),
    .dinA(taginit_en ? 15'h0000 : {w_dirty, w_valid,w_tagadr}),
    .doutA({tag_dirty2,tag_valid2,tag_addr2}),

    .clkB(psclk),
    .weB(rewrite_tag_clean_dirty[2]),
    .enB((READ_TAG_SOFTWB&clean_dirty_wayno[2])|
            rewrite_tag_clean_dirty[2]),
    .addrB(clean_dirty_lineno),
    .dinB({1'b0,1'b1,rewrite_tagadr_clean_dirty}),
    .doutB(doutB2)

    );
DPRAM_WRAP #(
    .ADDR_WIDTH (4),        // 16word
    .DATA_WIDTH (1+1+13)      // dirty,valid, adr[22:10]
    ) cache_tag_way3
    (
    .clkA(cpuclk),
    .weA(taginit_en ? 1'b1 : rewrite_tag[3]),
    //.ul_en(2'b11),
    .enA(taginit_en ? 1'b1 : (READ_TAG | rewrite_tag[3])),
    .addrA(taginit_en ? taginit_lineno : read_lineno),
    .dinA(taginit_en ? 15'h0000 : {w_dirty, w_valid,w_tagadr}),
    .doutA({tag_dirty3,tag_valid3,tag_addr3}),
    
    .clkB(psclk),
    .weB(rewrite_tag_clean_dirty[3]),
    .enB((READ_TAG_SOFTWB&clean_dirty_wayno[3])|
            rewrite_tag_clean_dirty[3]),
    .addrB(clean_dirty_lineno),
    .dinB({1'b0,1'b1,rewrite_tagadr_clean_dirty}),
    .doutB(doutB3)
    
    );

// way毎に分ける必要あり
wire [31:0] wb_cache_rdata0;
wire [31:0] wb_cache_rdata1;
wire [31:0] wb_cache_rdata2;
wire [31:0] wb_cache_rdata3;

assign wb_cache_rdata = ({32{wb_cache_wayno[0]}}&wb_cache_rdata0) |
                    ({32{wb_cache_wayno[1]}}&wb_cache_rdata1) |
                    ({32{wb_cache_wayno[2]}}&wb_cache_rdata2) |
                    ({32{wb_cache_wayno[3]}}&wb_cache_rdata3) ;

wire [1:0] dram_addr_upper_portA = w_dc[0] ? 2'b00  :
                                    w_dc[1] ? 2'b01 :
                                    w_dc[2] ? 2'b10 : 2'b11;
                                    
                    
DPRAM_BYTEW_WRAP #(
    .NUM_COL(4),    // 32bitを4分割(=byte write)
    .COL_WIDTH(8),  // 8bit単位でライト
    .ADDR_WIDTH(8)  // 16line x (64/4) = 256 -> 8bit
    ) cache_tag_data0
    (
     .clkA(cpuclk),
     .enaA(w_dc[0]|READ_DATA_BUS),    // WHITのみ
     .weA({4{w_dc[0]}}&r_w_strb),
     .addrA(READ_DATA_BUS ? {read_lineno,read_adr_lsb} :r_w_adrs[9:2]),
     .dinA(r_w_wdata),
     .doutA(rf_cache_rdata0),
     
     .clkB(psclk),
     .enaB((wb_cache_ren|wb_cache_wen)&wb_cache_wayno[0]),
     .weB({4{wb_cache_wen}}&wb_cache_strb),
     .addrB(wb_cache_adr),
     .dinB(wb_cache_wdata),
     .doutB(wb_cache_rdata0)
    );
DPRAM_BYTEW_WRAP #(
    .NUM_COL(4),    // 32bitを4分割(=byte write)
    .COL_WIDTH(8),  // 8bit単位でライト
    .ADDR_WIDTH(8)  // 16line x (64/4) = 256 -> 8bit
    ) cache_tag_data1
    (
     .clkA(cpuclk),
     .enaA(w_dc[1]|READ_DATA_BUS),    // WHITのみ
     .weA({4{w_dc[1]}}&r_w_strb),
     .addrA(READ_DATA_BUS ? {read_lineno,read_adr_lsb} :r_w_adrs[9:2]),
     .dinA(r_w_wdata),
     .doutA(rf_cache_rdata1),
     
     .clkB(psclk),
     .enaB((wb_cache_ren|wb_cache_wen)&wb_cache_wayno[1]),
     .weB({4{wb_cache_wen}}&wb_cache_strb),
     .addrB(wb_cache_adr),
     .dinB(wb_cache_wdata),
     .doutB(wb_cache_rdata1)
    );
DPRAM_BYTEW_WRAP #(
    .NUM_COL(4),    // 32bitを4分割(=byte write)
    .COL_WIDTH(8),  // 8bit単位でライト
    .ADDR_WIDTH(8)  // 16line x (64/4) = 256 -> 8bit
    ) cache_tag_data2
    (
     .clkA(cpuclk),
     .enaA(w_dc[2]|READ_DATA_BUS),    // WHITのみ
     .weA({4{w_dc[2]}}&r_w_strb),
     .addrA(READ_DATA_BUS ? {read_lineno,read_adr_lsb} :r_w_adrs[9:2]),
     .dinA(r_w_wdata),
     .doutA(rf_cache_rdata2),
     
     .clkB(psclk),
     .enaB((wb_cache_ren|wb_cache_wen)&wb_cache_wayno[2]),
     .weB({4{wb_cache_wen}}&wb_cache_strb),
     .addrB(wb_cache_adr),
     .dinB(wb_cache_wdata),
     .doutB(wb_cache_rdata2)
    );
DPRAM_BYTEW_WRAP #(
    .NUM_COL(4),    // 32bitを4分割(=byte write)
    .COL_WIDTH(8),  // 8bit単位でライト
    .ADDR_WIDTH(8)  // 16line x (64/4) = 256 -> 8bit
    ) cache_tag_data3
    (
     .clkA(cpuclk),
     .enaA(w_dc[3]|READ_DATA_BUS),    // WHITのみ
     .weA({4{w_dc[3]}}&r_w_strb),
     .addrA(READ_DATA_BUS ? {read_lineno,read_adr_lsb} : r_w_adrs[9:2]),
     .dinA(r_w_wdata),
     .doutA(rf_cache_rdata3),
     
     .clkB(psclk),
     .enaB((wb_cache_ren|wb_cache_wen)&wb_cache_wayno[3]),
     .weB({4{wb_cache_wen}}&wb_cache_strb),
     .addrB(wb_cache_adr),
     .dinB(wb_cache_wdata),
     .doutB(wb_cache_rdata3)
    );
    
endmodule
