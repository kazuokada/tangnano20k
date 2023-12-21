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
// cache hit miss 判定
module brd_wb2ps_wc_cachectl #
(
    parameter integer BURST_RNUM = 8
)
(
    // System Signals
    input WSHRST,
    input cpuclk,       // wishbone clk

    // TAG/DATA read ctl
    // 4way
    input wire          READ_TAG,
    input wire [9:6]    read_lineno,
    
    // cache アクセス用 一時バッファ
    input wire [22:0]   buf_addr,
    input wire          buf_wvalid,
    input wire          buf_rvalid,
    input wire [31:0]   buf_wdata,
    input wire [3:0]    buf_wstrb,

    // from tag ram
    input wire [22:10]  tag_addr0,
    input wire [1:0]    tag_lru0,
    input wire          tag_valid0,
    input wire          tag_dirty0,

    input wire [22:10]  tag_addr1,
    input wire [1:0]    tag_lru1,
    input wire          tag_valid1,
    input wire          tag_dirty1,

    input wire [22:10]  tag_addr2,
    input wire [1:0]    tag_lru2,
    input wire          tag_valid2,
    input wire          tag_dirty2,

    input wire [22:10]  tag_addr3,
    input wire [1:0]    tag_lru3,
    input wire          tag_valid3,
    input wire          tag_dirty3,


    // tag ram write : to tag ram
    // regだが組み合わせ回路
    output reg [1:0]    w_lru0,
    output reg [1:0]    w_lru1,
    output reg [1:0]    w_lru2,
    output reg [1:0]    w_lru3,
    output wire         rewrite_lru,
    
    output reg [9:6]    r_w_lineno, // WB以降

    // WHIT/WMISS tag書き換え
    output wire [3:0]   rewrite_tag,    // 4way
    output wire [22:10] w_tagadr,
    output wire         w_valid,
    output wire         w_dirty,


    // cache data ram write : to data ram
    // WHIT時
    output wire [3:0]   w_dc,   // 4way
    output reg [22:2]   r_w_adrs,
    output reg [31:0]   r_w_wdata,
    output reg [3:0]    r_w_strb,
    //output reg          r_w_wvalid,

    // write back & ReadFill兼用情報
    output reg          WB_RUN,
    input wire          WB_RUN_CLR_cpuclk_r,
    output reg [3:0]    WB_w_wayno,  // 4way 1hot
    output wire [9:6]   WB_w_lineno,
    output reg [22:10]  WB_w_tagadr,    // psram書き出しアドレスのtag_adr
    output wire [22:10] RF_w_tagadr,    // readfill時のtag_adr

    // ReadFillのみ情報
    output reg          RFILL_RUN,
    input wire          RFILL_RUN_CLR_cpuclk_r, // 1shot

    // readfill完了後のwriteデータ
    output wire [31:0]  OW_w_data,
    output wire [3:0]   OW_w_strb,
    output wire [5:2]   OW_w_adr_lsb,
    output wire         OW_w_wvalid,
    
    output wire         MISS,
    output wire [3:0]   HIT_way,
    
    // アクセスモニター
    output reg [31:0]  whit_cnt,
    output reg [31:0]  rhit_cnt,
    output reg [31:0]  acc_cnt    // cache area カウンター

);


// ---------------------------------
// 内部信号
// ---------------------------------
reg         cache_judge;

wire        HIT;
wire [3:0]  MISS_way;


wire [1:0]  oldest_way;
wire        wb_tag_valid;
wire        wb_tag_dirty;
wire [3:0]  wb_way;
wire [22:10]wb_tag_addr;

reg         r_w_wvalid;

reg [2:0]   wbuf_state;
reg [2:0]   next_wbuf_state;



// ---------------------------------
// hit/miss 判定タイミング
// ---------------------------------
always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        cache_judge <= 1'b0;
    else
        cache_judge <= READ_TAG;

    
// ---------------------------------
// hit判定
// ---------------------------------
// --------------------------------------------------------
// cache HIT 判定
// --------------------------------------------------------
assign HIT_way[0] = cache_judge &
                ( tag_valid0 & (tag_addr0[22:10]== buf_addr[22:10])
                );
assign HIT_way[1] = cache_judge &
                ( tag_valid1 & (tag_addr1[22:10]== buf_addr[22:10])
                );
assign HIT_way[2] = cache_judge &
                ( tag_valid2 & (tag_addr2[22:10]== buf_addr[22:10])
                );
assign HIT_way[3] = cache_judge &
                ( tag_valid3 & (tag_addr3[22:10]== buf_addr[22:10])
                );


assign HIT = |HIT_way;

// --------------------------------------------------------
// cache MISS 判定
// --------------------------------------------------------
assign MISS_way[0] = cache_judge & (( ~tag_valid0 ) |
                ( tag_valid0 & (tag_addr0[22:10] != buf_addr[22:10]) )
                );
assign MISS_way[1] = cache_judge & (( ~tag_valid1 ) |
                ( tag_valid1 & (tag_addr1[22:10] != buf_addr[22:10]) )
                );
assign MISS_way[2] = cache_judge & (( ~tag_valid2 ) |
                ( tag_valid2 & (tag_addr2[22:10] != buf_addr[22:10]) )
                );
assign MISS_way[3] = cache_judge & (( ~tag_valid3 ) |
                ( tag_valid3 & (tag_addr3[22:10] != buf_addr[22:10]) )
                );


assign MISS = &MISS_way;


always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        acc_cnt <= 32'h0000_0000;
    else if(cache_judge)
        acc_cnt <= acc_cnt + 32'h0000_0001;

always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        whit_cnt <= 32'h0000_0000;
    else if(HIT&buf_wvalid)
        whit_cnt <= whit_cnt + 32'h0000_0001;

always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        rhit_cnt <= 32'h0000_0000;
    else if(HIT&buf_rvalid)
        rhit_cnt <= rhit_cnt + 32'h0000_0001;
    
// --------------------------------------------------------
// HIT時のLRU制御
// HITしたwayはlru=0になる
// Hitしたwayより数値が小さい場合は+1
// Hitしたwayより数値が大きい場合は変わらず
// Hitしたwayが既に0の場合は状態は変わらず
// way 0 1 2 3
// cur 0 1 2 3  way=1がhit -> 1 0 2 3
// --------------------------------------------------------

// 基本的にread miss hitで埋める際には+1すればOK
wire [7:0] cur_lru;
assign cur_lru = {tag_lru0, tag_lru1, tag_lru2, tag_lru3};
reg [7:0] next_lru; // 実際にはwire
//reg [7:0] next_lru;    // wire
//always@* begin   // Verilog 2001
//    case({HIT_way,cur_lru})
//        {2'b00, 8'b11_10_01_00} : next_lru = 8'b00_11_10_01;
`include "next_lru.v"
// hitしたらLRU値は全way変わる
always@* begin
    w_lru0 = next_lru[7:6];
    w_lru1 = next_lru[5:4];
    w_lru2 = next_lru[3:2];
    w_lru3 = next_lru[1:0];
end

assign rewrite_lru = cache_judge;

// --------------------------------------------------------
// w_lineno
// 書き換え lineno
// data cache 書き換えアドレス
// LSBのアドレス
// strb
// --------------------------------------------------------
always@(posedge cpuclk)
    //if(READ_TAG&(~WB_RUN)) begin
    if(READ_TAG) begin
        r_w_lineno <= buf_addr[9:6];
        r_w_adrs <= buf_addr[22:2];
        r_w_wdata <= buf_wdata;
        r_w_strb <= buf_wstrb;
        r_w_wvalid <= buf_wvalid;
    end

// WHIT時はhit wayのみ書き換える
//   LRUの書き換え(全way)
//   dirty=1(hitway)にすること(readから始まった場合のことを考慮)
//    valid, tagadrは同じ値なので書き換えなくても良い
// RHIT時は
//   tagは書き換えない
// WMISS時は
//   oldest wayが書き換え対象
//   LRUは全way書き換える
//   dirty=1, valid=1, tagadr(wbufにあるadr情報) 
//   キャッシュ送出時はtagから読み出したadrs情報でPSRAMへ書き出す
//   キャッシュ入力時はwbufにあるadr情報
//   whit時と同タイミングでtag_adrを書き換えると、
//   キャッシュ送出時のアドレス情報を失うので
//   tag情報を読みだした時のものをラッチしておく
assign rewrite_tag = ({4{buf_wvalid}}&HIT_way) | ({4{MISS}}&wb_way);  // 4way
assign w_tagadr = r_w_adrs[22:10];
assign w_valid = 1'b1;
assign w_dirty = buf_wvalid;   // write時のみdirtyになる
always@(posedge cpuclk)
    if(MISS) begin
        WB_w_tagadr <= wb_tag_addr;
    end
// --------------------------------------------------------
// data cache 書き換えタイミング
// write hit時のみ書き換える
// --------------------------------------------------------
assign w_dc = {4{buf_wvalid}} & HIT_way;

// --------------------------------------------------------
//
// write back関連
//
// --------------------------------------------------------
// --------------------------------------------------------
// WB_RUN
// w_miss
// 差し替えway(cur_lru==3)のdirty
//                          tag_valid=1
// --------------------------------------------------------
assign oldest_way = (tag_lru0==2'b11) ? 2'b00:
                    (tag_lru1==2'b11) ? 2'b01:
                    (tag_lru2==2'b11) ? 2'b10:
                    2'b11;
// wbで書き換え対象wayのvalid
assign wb_tag_valid = (oldest_way==2'b00) ? tag_valid0:
                    (oldest_way==2'b01) ? tag_valid1:
                    (oldest_way==2'b10) ? tag_valid2:
                    tag_valid3;
assign wb_tag_dirty = (oldest_way==2'b00) ? tag_dirty0:
                    (oldest_way==2'b01) ? tag_dirty1:
                    (oldest_way==2'b10) ? tag_dirty2:
                    tag_dirty3;
assign wb_tag_addr = (oldest_way==2'b00) ? tag_addr0:
                    (oldest_way==2'b01) ? tag_addr1:
                    (oldest_way==2'b10) ? tag_addr2:
                    tag_addr3;

assign wb_way = (tag_lru0==2'b11) ? 4'b0001:
                (tag_lru1==2'b11) ? 4'b0010:
                (tag_lru2==2'b11) ? 4'b0100:
                4'b1000;

// WB_RUNはRFILLも行う
always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        WB_RUN <= 1'b0;
    else if(WB_RUN_CLR_cpuclk_r)
        WB_RUN <= 1'b0;
    else if( ( (wb_tag_valid & wb_tag_dirty)) & MISS)
        WB_RUN <= 1'b1;

// READ,Write MISS
// dirty=0の時はread fillのみ行う
always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        RFILL_RUN <= 1'b0;
    else if(RFILL_RUN_CLR_cpuclk_r)
        RFILL_RUN <= 1'b0;
    else if( (~wb_tag_valid | (wb_tag_valid & (~wb_tag_dirty))) & MISS)
        RFILL_RUN <= 1'b1;
        

always@(posedge cpuclk)
    WB_w_wayno <= wb_way;

assign WB_w_lineno = r_w_lineno[9:6];
//  writeデータのアドレス(wbufに入ってたアドレス)
// psramへの書き出し用アドレスではない
assign RF_w_tagadr = r_w_adrs[22:10];   // writeデータのアドレス

// readfill完了後のwriteデータ
assign OW_w_data = r_w_wdata;
assign OW_w_strb = r_w_strb;
assign OW_w_adr_lsb = r_w_adrs[5:2];
assign OW_w_wvalid = r_w_wvalid;

endmodule
