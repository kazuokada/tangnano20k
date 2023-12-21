`timescale 1ns/1ps
// wishbone → PSRAM バスブリッジ
// csche付
// 64burst(64byte) 転送
// data幅 32bit
//
// cache 構成
//   64byte/line
//   16line/way
//   4way
//   4KB(total)
module brd_wb2ps_wc (
    input RST,
    input cpuclk,       // wishbone clk 
    // wishbone
    // reg i/f
    // cache 制御用
    // writeback指示
    // fifo制御用
    input wire [11:0]   reg_mem_addr,
    input wire [31:0]   reg_mem_wdata,
    output reg [31:0]   reg_mem_rdata,
    input wire [3:0]    reg_mem_wstrb,
    input wire          reg_mem_valid,
    output wire         reg_mem_ready,

    // PSRAM 32Mbit x 2
    // cpuclk domain
    input wire [22:0]   ps_mem_addr,
    input wire [31:0]   ps_mem_wdata,
    output wire [31:0]  ps_mem_rdata,
    input wire [3:0]    ps_mem_wstrb,
    input wire          ps_mem_valid,
    output wire         ps_mem_ready,

    // PSRAM i/f
    // psramclk domain
    // cache側のPSRAM I/F
    input wire          half_psramclk,       // 83MHz clk
    output wire         cmd0,           //input cmd0
    output wire         cmd_en0,        //input cmd_en0
    output wire [22:0]  addr0,
    output wire [31:0]  wr_data0,
    input wire [31:0]   rd_data0,
    input wire          rd_data_valid0,
    output wire [3:0]   data_mask0,
    input wire          cmd_ready,
    input wire          cmd_ready_clone,
    
    // fifo側のPSRAM I/F
    output wire         cmd_fifo,           //input cmd0
    output wire         cmd_en_fifo,        //input cmd_en0
    output wire [22:0]  addr_fifo,
    output wire [31:0]  wr_data_fifo,
    output wire [3:0]   data_mask_fifo,
    input wire          cmd_ready_fifo
    
    );

// ---------------------------------
// 結線 wire 宣言
// ---------------------------------
wire    psramclk = half_psramclk;
wire    psclk = half_psramclk;
wire    WSHRST;
wire    PSRST;
reg     RST_cpuclk_sync1;
reg     RST_cpuclk_sync2;
reg     RST_psramclk_sync1;
reg     RST_psramclk_sync2;


// brd_wb2ps_wc_enter <-> brd_wb2ps_wc_cachectl
wire [22:0] buf_addr;
wire        buf_wvalid;
wire        buf_rvalid;
wire [31:0] buf_wdata;
wire [3:0]  buf_wstrb;

// brd_wb2ps_wc_enter <-> brd_wb2ps_wc_cachectl
//                    <-> brd_wb2ps_wc_cacheram_ctl
wire        READ_TAG;
wire [9:6]  read_lineno;
wire        READ_DATA_BUS;
wire [5:2]  read_adr_lsb;

wire        MISS;
wire [3:0]  HIT_way;
wire [31:0] rf_cache_rdata0;
wire [31:0] rf_cache_rdata1;
wire [31:0] rf_cache_rdata2;
wire [31:0] rf_cache_rdata3;

// brd_wb2ps_wc_enter <-> brd_wb2ps_wc_wb_rfill
wire [31:0] get_psram_rdata;

// brd_wb2ps_wc_cachectl <-> brd_wb2ps_wc_cacheram_ctl
wire [22:10]    tag_addr0;
wire [1:0]      tag_lru0;
wire            tag_valid0;
wire            tag_dirty0;
wire [22:10]    tag_addr1;
wire [1:0]      tag_lru1;
wire            tag_valid1;
wire            tag_dirty1;
wire [22:10]    tag_addr2;
wire [1:0]      tag_lru2;
wire            tag_valid2;
wire            tag_dirty2;
wire [22:10]    tag_addr3;
wire [1:0]      tag_lru3;
wire            tag_valid3;
wire            tag_dirty3;

wire [1:0]      w_lru0;
wire [1:0]      w_lru1;
wire [1:0]      w_lru2;
wire [1:0]      w_lru3;
wire            rewrite_lru;

wire [3:0]      rewrite_tag;
wire [22:10]    w_tagadr;
wire            w_valid;
wire            w_dirty;

wire [3:0]      w_dc;
wire [22:2]     r_w_adrs;
wire [31:0]     r_w_wdata;
wire [3:0]      r_w_strb;
//wire            r_w_wvalid;

// brd_wb2ps_wc_cachectl <-> brd_wb2ps_wc_wb_rfill
wire            WB_RUN;
wire            WB_RUN_CLR_cpuclk_r;
wire [3:0]      WB_w_wayno;
wire [9:6]      WB_w_lineno;
wire [22:10]    WB_w_tagadr;
wire [22:10]    RF_w_tagadr;
wire [31:0]     OW_w_data;
wire [3:0]      OW_w_strb;
wire [5:2]      OW_w_adr_lsb;
wire            OW_w_wvalid;

wire            RFILL_RUN;
wire            RFILL_RUN_CLR_cpuclk_r;

// brd_wb2ps_wc_cacheram_ctl <-> brd_wb2ps_wc_wb_rfill
wire [9:2]      wb_cache_adr;
wire [31:0]     wb_cache_rdata;
wire            wb_cache_ren;
wire            wb_cache_wen;
wire [31:0]     wb_cache_wdata;
wire [3:0]      wb_cache_strb;
wire [3:0]      wb_cache_wayno;
// soft wb
wire            READ_TAG_SOFTWB;
wire [9:6]      clean_dirty_lineno;
wire [3:0]      clean_dirty_wayno;

wire [3:0]      rewrite_tag_clean_dirty;    // tag書き換え指示
wire [22:10]    clean_dirty_tagadr_o;       // 上記の結果
wire            clean_dirty_dirty_o;
wire            clean_dirty_valid_o;
// tag書き戻し
wire [22:10]    rewrite_tagadr_clean_dirty;


// brd_wb2ps_wc_cacheram_ctl <-> brd_wb2ps_wc_inittag
wire            taginit_en;
wire [9:6]      taginit_lineno;

// brd_wb2ps_wc_inittag <-> brd_wb2ps_wc_enter
wire            run_inittag;

// reg部 <-> brd_wb2ps_wc_wb_rfill
wire            RUN_CLEAN_WB_CLR_cpuclk;


// ---------------------------------
// キャッシュ制御レジスタ
// ---------------------------------
reg         run_writeback;
reg         run_clean;
reg         specify_adrs;
wire        stat_writeback;
wire        stat_clean;
reg [31:0]  wb_sadr;
reg [31:0]  wb_eadr;
reg [47:0]  free_timer;
wire [31:0] whit_cnt;
wire [31:0] rhit_cnt;
wire [31:0] acc_cnt;

reg [31:0]  fifo_wadrs;
reg [31:0]  fifo_warea;
reg [31:0]  fifo_wdata;
reg         fifo_wdata_wen2;
reg         fifo_startp;
reg         fifo_endp;
reg         fifo_reg_eflag;
wire        fifo_almost_full;
wire        fifo_run;
wire        fifo_run_endp;

reg [31:0]  debug;  // for LogicAnalyzer

wire        reg_r_ready;
wire        reg_w_ready;
// 内部レジスタ wen
wire        ctl0_wen0;
wire        ctl0_wen3;
wire        wb_sadr_wen;
wire        wb_eadr_wen;
wire        fifo_wadrs_wen;
wire        fifo_warea_wen;
wire        fifo_wdata_wen;
wire        fifo_ctl;
wire        debug_wen;

wire        read_ctl0;
wire        read_wb_sadr;
wire        read_wb_eadr;
wire        read_freetimer0;
wire        read_freetimer1;
wire        read_whit_cnt;
wire        read_rhit_cnt;
wire        read_acc_cnt;
wire        read_fifo_wadrs;
wire        read_fifo_warea;
wire        read_fifo_ctl;
wire        read_debug;

reg         RSTATE;

assign reg_mem_ready = reg_r_ready & reg_w_ready ;
assign reg_w_ready = ~fifo_almost_full;

// ---------------------------------
// 各種ライト レジスタ
// ---------------------------------
wire [11:0] ctl0_adr = 12'h000;
assign ctl0_wen0 = (reg_mem_addr[11:2]==ctl0_adr[11:2])&
                    reg_mem_valid&(reg_mem_wstrb[0])&reg_w_ready;
assign ctl0_wen3 = (reg_mem_addr[11:2]==(12'h000>>2))&
                    reg_mem_valid&(reg_mem_wstrb[3])&reg_w_ready;
assign wb_sadr_wen = (reg_mem_addr[11:2]==(12'h004>>2))&
                    reg_mem_valid&(|reg_mem_wstrb)&reg_w_ready;
assign wb_eadr_wen = (reg_mem_addr[11:2]==(12'h008>>2))&
                    reg_mem_valid&(|reg_mem_wstrb)&reg_w_ready;
assign fifo_wadrs_wen = (reg_mem_addr[11:2]==(12'h030>>2))&
                    reg_mem_valid&(|reg_mem_wstrb)&reg_w_ready;
assign fifo_warea_wen = (reg_mem_addr[11:2]==(12'h034>>2))&
                    reg_mem_valid&(|reg_mem_wstrb)&reg_w_ready;
assign fifo_wdata_wen = (reg_mem_addr[11:2]==(12'h038>>2))&
                    reg_mem_valid&(|reg_mem_wstrb)&reg_w_ready;
assign fifo_ctl = (reg_mem_addr[11:2]==(12'h03c>>2))&
                    reg_mem_valid&(|reg_mem_wstrb)&reg_w_ready;
assign debug_wen =   (reg_mem_addr[11:2]==(12'h040>>2))&
                    reg_mem_valid&(|reg_mem_wstrb)&reg_w_ready;
                    
always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        run_writeback <= 1'b0;
    else if(RUN_CLEAN_WB_CLR_cpuclk)
        run_writeback <= 1'b0;
    else if(ctl0_wen0)
        run_writeback <= reg_mem_wdata[0];
always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        run_clean <= 1'b0;
    else if(ctl0_wen0)
        run_clean <= reg_mem_wdata[1];

always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        specify_adrs <= 1'b0;
    else if(ctl0_wen3)
        specify_adrs <= reg_mem_wdata[31];

always@(posedge cpuclk)
    if(wb_sadr_wen)
        wb_sadr <= reg_mem_wdata;
always@(posedge cpuclk)
    if(wb_eadr_wen)
        wb_eadr <= reg_mem_wdata;

// fifo制御
always@(posedge cpuclk)
    if(fifo_wadrs_wen)
        fifo_wadrs <= reg_mem_wdata;
always@(posedge cpuclk)
    if(fifo_warea_wen)
        fifo_warea <= reg_mem_wdata;
always@(posedge cpuclk)
    if(fifo_wdata_wen)
        fifo_wdata <= reg_mem_wdata;
always@(posedge cpuclk)
    fifo_wdata_wen2 <= fifo_wdata_wen;
    
// fifo_startp/endp 1shot
always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        fifo_startp <= 1'b0;
    else if(fifo_startp)
        fifo_startp <= 1'b0;
    else if(fifo_ctl) begin
        if(reg_mem_wdata[0])
            fifo_startp <= 1'b1;
    end
always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        fifo_endp <= 1'b0;
    else if(fifo_endp)
        fifo_endp <= 1'b0;
    else if(fifo_ctl) begin
        if(reg_mem_wdata[1])
            fifo_endp <= 1'b1;
    end

always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        fifo_reg_eflag <= 1'b0;
    else if(fifo_run_endp)
        fifo_reg_eflag <= 1'b1;
    else if(fifo_ctl&reg_mem_wdata[8])  // 1write clear
        fifo_reg_eflag <= 1'b0;

// for logic analyzer
always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        debug <= 32'h0000_0000;
    else if(debug_wen)
        debug <= reg_mem_wdata;


// read busタイミング
wire read_bus = reg_mem_valid & (reg_mem_wstrb==4'h0);
assign read_ctl0 = (reg_mem_addr[11:2]==(12'h000>>2))&read_bus;
assign read_wb_sadr = (reg_mem_addr[11:2]==(12'h004>>2))&read_bus;
assign read_wb_eadr = (reg_mem_addr[11:2]==(12'h008>>2))&read_bus;
assign read_freetimer0 = (reg_mem_addr[11:2]==(12'h010>>2))&read_bus;
assign read_freetimer1 = (reg_mem_addr[11:2]==(12'h014>>2))&read_bus;
assign read_acc_cnt = (reg_mem_addr[11:2]==(12'h020>>2))&read_bus;
assign read_whit_cnt = (reg_mem_addr[11:2]==(12'h024>>2))&read_bus;
assign read_rhit_cnt = (reg_mem_addr[11:2]==(12'h028>>2))&read_bus;
assign read_fifo_wadrs = (reg_mem_addr[11:2]==(12'h030>>2))&read_bus;
assign read_fifo_warea = (reg_mem_addr[11:2]==(12'h034>>2))&read_bus;
assign read_fifo_ctl = (reg_mem_addr[11:2]==(12'h03c>>2))&read_bus;
assign read_debug = (reg_mem_addr[11:2]==(12'h040>>2))&read_bus;

// ------------------------------------
// mem_r_ready (read側 wishbone ready)
// ------------------------------------
assign reg_r_ready = ~(read_bus & (~RSTATE));

// ------------------------------------
// RSTATE (read bus timing 後半サイクル)
// ------------------------------------
always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        RSTATE <= 1'b0;
    else if(RSTATE)
        RSTATE <= 1'b0;
    else if(read_bus)
        RSTATE <= 1'b1;
// -------------------------------------
// bus
// reg_mem_rdata
// -------------------------------------
assign stat_writeback = run_writeback;
wire inhibit_cachectl = RFILL_RUN|WB_RUN;
always@(posedge cpuclk)
    if(read_ctl0&(~RSTATE))
        reg_mem_rdata <= {specify_adrs,23'h0000_00,
                3'b000,inhibit_cachectl,
                2'b00,1'b0,stat_writeback};
    else if(read_wb_sadr&(~RSTATE))
        reg_mem_rdata <= wb_sadr;
    else if(read_wb_eadr&(~RSTATE))
        reg_mem_rdata <= wb_eadr;
    else if(read_freetimer0&(~RSTATE))
        reg_mem_rdata <= free_timer[31:0];
    else if(read_freetimer1&(~RSTATE))
        reg_mem_rdata <= free_timer[47:32];
    else if(read_acc_cnt&(~RSTATE))
        reg_mem_rdata <= acc_cnt;
    else if(read_whit_cnt&(~RSTATE))
        reg_mem_rdata <= whit_cnt;
    else if(read_rhit_cnt&(~RSTATE))
        reg_mem_rdata <= rhit_cnt;
    else if(read_fifo_wadrs&(~RSTATE))
        reg_mem_rdata <= fifo_wadrs;
    else if(read_fifo_warea&(~RSTATE))
        reg_mem_rdata <= fifo_warea;
    else if(read_fifo_ctl&(~RSTATE))
        reg_mem_rdata <= {15'h0000,fifo_run, 7'h00,
                            fifo_reg_eflag, 8'h00};
    else if(read_debug&(~RSTATE))
        reg_mem_rdata <= debug;
        
// ---------------------------------
// 各種リセット同期化
// ---------------------------------
always@(posedge cpuclk or posedge RST)
    if(RST) begin
        RST_cpuclk_sync1 <= 1'b1;
        RST_cpuclk_sync2 <= 1'b1;
    end
    else begin
        RST_cpuclk_sync1 <= RST;
        RST_cpuclk_sync2 <= RST_cpuclk_sync1;
    end
assign WSHRST = RST_cpuclk_sync2;

always@(posedge psramclk or posedge RST)
    if(RST) begin
        RST_psramclk_sync1 <= 1'b1;
        RST_psramclk_sync2 <= 1'b1;
    end
    else begin
        RST_psramclk_sync1 <= RST;
        RST_psramclk_sync2 <= RST_psramclk_sync1;
    end
assign PSRST = RST_psramclk_sync2;

// ---------------------------------
// freerun timer
// ---------------------------------
always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        free_timer <= 48'h0000_00000000;
    else
        free_timer <= free_timer + 48'h0000_00000001;

// ---------------------------------
// reg_w_ready モニタ
// ---------------------------------
reg [15:0] reg_w_ready_cnt;
reg reg_w_ready2;
wire reg_w_ready2_r;
wire reg_w_ready2_f;
reg reg_w_ready_cnten;

always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        reg_w_ready2 <= 1'b1;
    else
        reg_w_ready2 <= reg_w_ready;

assign reg_w_ready2_f = (~reg_w_ready) & reg_w_ready2;
assign reg_w_ready2_r = reg_w_ready & (~reg_w_ready2);
wire    trg_reg_w_ready_cnt;
assign trg_reg_w_ready_cnt = (reg_w_ready_cnt == 16'd256);

always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        reg_w_ready_cnten <= 1'b0;
    else if(reg_w_ready2_f)
        reg_w_ready_cnten <= 1'b1;
    else if(reg_w_ready2_r)
        reg_w_ready_cnten <= 1'b0;


always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        reg_w_ready_cnt <= 16'h0000;
    else if(reg_w_ready_cnten)
        reg_w_ready_cnt <= reg_w_ready_cnt + 16'h0001;
    else
        reg_w_ready_cnt <= 16'h0000;


// ---------------------------------
// wishbone i/f制御
// wbuf
// brd_wb2ps_wc_enter
// ---------------------------------

brd_wb2ps_wc_enter #
(
    .BURST_RNUM(8)
) brd_wb2ps_wc_enter
(
    // System Signals
    .WSHRST(WSHRST),        // in
    .cpuclk(cpuclk),        // in       // wishbone clk

    // PSRAM IF
    // cpuclk domain
    .ps_mem_addr(ps_mem_addr),      // input wire [22:0]
    .ps_mem_wdata(ps_mem_wdata),    // input wire [31:0]
    .ps_mem_rdata(ps_mem_rdata),    // output reg [31:0]
    .ps_mem_wstrb(ps_mem_wstrb),    // input wire [3:0]
    .ps_mem_valid(ps_mem_valid),    // input wire
    .ps_mem_ready(ps_mem_ready),    // output wire

    // cache判定用
    .buf_addr(buf_addr),        // output reg [22:0]
    .buf_wvalid(buf_wvalid),    // output reg
    .buf_rvalid(buf_rvalid),    // output reg
    .buf_wdata(buf_wdata),      // output [31:0]
    .buf_wstrb(buf_wstrb),      // output reg [3:0]

    // TAG/DATA read ctl
    // 4way
    .READ_TAG(READ_TAG),        // output reg
    .read_lineno(read_lineno),  // output wire [9:6]
    .READ_DATA_BUS(READ_DATA_BUS),  // output wire      bus出力用リード
    .read_adr_lsb(read_adr_lsb),    // output wire [5:2]
    
    .run_inittag(run_inittag),  // input
    .MISS(MISS),                // input
    .HIT_way(HIT_way),          // input
    .WB_RUN(WB_RUN),            // input
    .WB_RUN_CLR_cpuclk_r(WB_RUN_CLR_cpuclk_r),  // input wire
    .RFILL_RUN(RFILL_RUN),      // input
    .RFILL_RUN_CLR_cpuclk_r(RFILL_RUN_CLR_cpuclk_r),    // input
    .get_psram_rdata(get_psram_rdata),  // input
    .cache_rdata0(rf_cache_rdata0),     // input wire [31:0]
    .cache_rdata1(rf_cache_rdata1),     // input wire [31:0]
    .cache_rdata2(rf_cache_rdata2),     // input wire [31:0]
    .cache_rdata3(rf_cache_rdata3)      // input wire [31:0]

);

brd_wb2ps_wc_cachectl #
(
    .BURST_RNUM(8)
) brd_wb2ps_wc_cachectl
(
    // System Signals
    .WSHRST(WSHRST),
    .cpuclk(cpuclk),       // wishbone clk

    // TAG/DATA read ctl
    // 4way
    .READ_TAG(READ_TAG),        // input wire
    .read_lineno(read_lineno),  // input wire [9:6]

    // cache アクセス用 一時バッファ
    .buf_addr(buf_addr),        // input wire [22:0]
    .buf_wvalid(buf_wvalid),    // input wire
    .buf_rvalid(buf_rvalid),    // input wire
    .buf_wdata(buf_wdata),      // input wire [31:0]
    .buf_wstrb(buf_wstrb),      // input wire [3:0]

    // from tag ram
    .tag_addr0(tag_addr0),      // input wire [22:10]
    .tag_lru0(tag_lru0),        // input wire [1:0]
    .tag_valid0(tag_valid0),    // input wire
    .tag_dirty0(tag_dirty0),    // input wire

    .tag_addr1(tag_addr1),      // input wire [22:10]
    .tag_lru1(tag_lru1),        // input wire [1:0]
    .tag_valid1(tag_valid1),    // input wire
    .tag_dirty1(tag_dirty1),    // input wire

    .tag_addr2(tag_addr2),      // input wire [22:10]
    .tag_lru2(tag_lru2),        // input wire [1:0]
    .tag_valid2(tag_valid2),    // input wire
    .tag_dirty2(tag_dirty2),    // input wire

    .tag_addr3(tag_addr3),      // input wire [22:10]
    .tag_lru3(tag_lru3),        // input wire [1:0]
    .tag_valid3(tag_valid3),    // input wire
    .tag_dirty3(tag_dirty3),    // input wire

    // tag ram write : to tag ram
    // regだが組み合わせ回路
    .w_lru0(w_lru0),            // output reg [1:0]
    .w_lru1(w_lru1),            // output reg [1:0]
    .w_lru2(w_lru2),            // output reg [1:0]
    .w_lru3(w_lru3),            // output reg [1:0]
    .rewrite_lru(rewrite_lru),  // output wire

    .r_w_lineno(), // WB以降  output reg [9:6]

    // WHIT/WMISS tag書き換え
    .rewrite_tag(rewrite_tag),  // 4way output wire [3:0]
    .w_tagadr(w_tagadr),        //      output wire [22:10]
    .w_valid(w_valid),          //      output wire
    .w_dirty(w_dirty),          //      output wire


    // cache data ram write : to data ram
    // WHIT時
    .w_dc(w_dc),                // 4way output wire [3:0]
    .r_w_adrs(r_w_adrs),        //      output reg [22:2]
    .r_w_wdata(r_w_wdata),      //      output reg [31:0]
    .r_w_strb(r_w_strb),        //      output reg [3:0]
    //.r_w_wvalid(r_w_wvalid),    //      output reg
    
    // write back & ReadFill指示
    .WB_RUN(WB_RUN),            //  output reg
    .WB_RUN_CLR_cpuclk_r(WB_RUN_CLR_cpuclk_r),  // input wire
    .WB_w_wayno(WB_w_wayno),    // 4way 1hot  output reg [3:0]
    .WB_w_lineno(WB_w_lineno),  // output wire [9:6]
    .WB_w_tagadr(WB_w_tagadr),  // output wire [22:10]
    .RF_w_tagadr(RF_w_tagadr),  // output wire [22:10]

    // READ_FILLのみ指示
    .RFILL_RUN(RFILL_RUN),      // output reg
    .RFILL_RUN_CLR_cpuclk_r(RFILL_RUN_CLR_cpuclk_r), //   input wire

    .OW_w_data(OW_w_data),      // output wire [31:0]
    .OW_w_strb(OW_w_strb),      // output wire [3:0] 
    .OW_w_adr_lsb(OW_w_adr_lsb),// output wire [5:2] 
    .OW_w_wvalid(OW_w_wvalid),  // output wire
    
    .MISS(MISS),                // output
    .HIT_way(HIT_way),          // output
    // アクセスモニター
    .whit_cnt(whit_cnt),        // output reg [31:0]
    .rhit_cnt(rhit_cnt),        // output reg [31:0]
    .acc_cnt(acc_cnt)          // output reg [31:0]

);

brd_wb2ps_wc_cacheram_ctl #
(
    .BURST_RNUM(8)
) brd_wb2ps_wc_cacheram_ctl
(
    // System Signals
    .WSHRST(WSHRST),
    .cpuclk(cpuclk),        // wishbone clk

    // System Signals PSRAM
    .PSRST(PSRST),
    .psclk(psclk),          // psram clk

    // TAG/DATA read ctl
    // 4way
    .READ_TAG(READ_TAG),        // input wire
    .read_lineno(read_lineno),  // input wire [9:6]
    .READ_DATA_BUS(READ_DATA_BUS),  // input wire      bus出力用リード
    .read_adr_lsb(read_adr_lsb),    // input wire [5:2]

    // to cache_ctl
    .tag_addr0(tag_addr0),      // output wire [22:10]
    .tag_lru0(tag_lru0),        // output wire [1:0]
    .tag_valid0(tag_valid0),    // output wire
    .tag_dirty0(tag_dirty0),    // output wire
    .tag_addr1(tag_addr1),      // output wire [22:10]
    .tag_lru1(tag_lru1),        // output wire [1:0]
    .tag_valid1(tag_valid1),    // output wire
    .tag_dirty1(tag_dirty1),    // output wire
    .tag_addr2(tag_addr2),      // output wire [22:10]
    .tag_lru2(tag_lru2),        // output wire [1:0]
    .tag_valid2(tag_valid2),    // output wire
    .tag_dirty2(tag_dirty2),    // output wire
    .tag_addr3(tag_addr3),      // output wire [22:10]
    .tag_lru3(tag_lru3),        // output wire [1:0]
    .tag_valid3(tag_valid3),    // output wire
    .tag_dirty3(tag_dirty3),    // output wire

    // tag ram write : from cachectl
    // cpuclk
    .w_lru0(w_lru0),        // input wire [1:0]
    .w_lru1(w_lru1),        // input wire [1:0]
    .w_lru2(w_lru2),        // input wire [1:0]
    .w_lru3(w_lru3),        // input wire [1:0]
    .rewrite_lru(rewrite_lru),  // input wire

    //.r_w_lineno(r_w_lineno),    // input reg [9:6]    WB以降

    .rewrite_tag(rewrite_tag),  // input wire [3:0]
    .w_tagadr(w_tagadr),        // input wire [22:10]
    .w_valid(w_valid),          // input wire
    .w_dirty(w_dirty),          // input wire

    // cache data ram write : from cachectl
    // WHIT時
    .w_dc(w_dc),            // 4way input wire [3:0]
    .r_w_adrs(r_w_adrs),    // input wire [22:2]
    .r_w_wdata(r_w_wdata),  // input wire [31:0]
    .r_w_strb(r_w_strb),    // input wire [3:0]

    // data cache アクセス from brd_wb2ps_wc_wb_rfill
    // psclk
    .wb_cache_adr(wb_cache_adr),        // input wire [9:2]
    .wb_cache_rdata(wb_cache_rdata),    // output wire [31:0]
    .wb_cache_ren(wb_cache_ren),        // input wire
    .wb_cache_wen(wb_cache_wen),        // input wire
    .wb_cache_wdata(wb_cache_wdata),    // input wire [31:0]
    .wb_cache_strb(wb_cache_strb),      // input wire [3:0] 
    .wb_cache_wayno(wb_cache_wayno),    // input wire [3:0]

    // data cache アクセス from brd_wb2ps_wc_enter
    // cpuclk
    .rf_cache_rdata0(rf_cache_rdata0),  // output wire [31:0]
    .rf_cache_rdata1(rf_cache_rdata1),  // output wire [31:0]
    .rf_cache_rdata2(rf_cache_rdata2),  // output wire [31:0]
    .rf_cache_rdata3(rf_cache_rdata3),  // output wire [31:0]

    // soft wb
    .READ_TAG_SOFTWB(READ_TAG_SOFTWB),         // input wire          
    .clean_dirty_lineno(clean_dirty_lineno),      // input wire [9:6]    
    .clean_dirty_wayno(clean_dirty_wayno),       // input wire [3:0]    
    .clean_dirty_tagadr_o(clean_dirty_tagadr_o),    // output wire [22:10]  上記の結果
    .clean_dirty_dirty_o(clean_dirty_dirty_o),     // output wire         
    .clean_dirty_valid_o(clean_dirty_valid_o),     // output wire         

    .rewrite_tag_clean_dirty(rewrite_tag_clean_dirty), // input wire [3:0]    / tag書き換え指示
    // tag書き戻し
    .rewrite_tagadr_clean_dirty(rewrite_tagadr_clean_dirty),    // input wire [22:10]

    .taginit_en(taginit_en),            // input
    .taginit_lineno(taginit_lineno)     // input wire [9:6]
);

brd_wb2ps_wc_wb_rfill #
(
   .BURST_RNUM(8)
) brd_wb2ps_wc_wb_rfill
(
    // System Signals
    .WSHRST(WSHRST),
    .cpuclk(cpuclk),        // wishbone clk

    // System Signals PSRAM
    .PSRST(PSRST),
    .psclk(psclk),          // psram clk

    // write back & ReadFill指示
    // from/to brd_wb2ps_wc_cachectl
    .WB_RUN(WB_RUN),                        // input wire
    .WB_RUN_CLR_cpuclk_r(WB_RUN_CLR_cpuclk_r),  // output reg
    .WB_w_wayno(WB_w_wayno),                // 4way 1hot   input wire [3:0]
    .WB_w_lineno(WB_w_lineno),              // input wire [9:6]
    .WB_w_tagadr(WB_w_tagadr),              // input wire [22:10]
    .RF_w_tagadr(RF_w_tagadr),              // input wire [22:10]
    .OW_w_data(OW_w_data),                  // input wire [31:0]
    .OW_w_strb(OW_w_strb),                  // input wire [3:0] 
    .OW_w_adr_lsb(OW_w_adr_lsb),            // input wire [5:2] 
    .OW_w_wvalid(OW_w_wvalid),              // input wire

// read fillした際に入手したアクセスアドレスのデータ
    .get_psram_rdata(get_psram_rdata),  // output reg [31:0]
    
    // read fillのみ実行
    .RFILL_RUN(RFILL_RUN),                       // input wire
    .RFILL_RUN_CLR_cpuclk_r(RFILL_RUN_CLR_cpuclk_r), // output 1shot

    // softからのwb指示
    .RUN_CLEAN_WB(run_writeback),           // input
    .RUN_CLEAN_WB_CLR_cpuclk(RUN_CLEAN_WB_CLR_cpuclk), // output

    // PSRAM IF
    .psram_cmd(cmd0),           // output reg
    .psram_cmd_en(cmd_en0),     // output reg
    .psram_addr(addr0),         // output reg [22:0]
    .psram_rdata(rd_data0),     // input wire [31:0]
    .psram_rvalid(rd_data_valid0),  // input wire
    .psram_wdata(wr_data0),     // output wire [31:0]
    .psram_mask(data_mask0),    // output wire [3:0]
    .psram_ready(cmd_ready),    // input wire
    .psram_ready_clone(cmd_ready_clone),    // input wire

    // data cache アクセス
    .wb_cache_adr(wb_cache_adr),    // output wire [9:2]
    .wb_cache_rdata(wb_cache_rdata),// input wire [31:0]
    .wb_cache_ren(wb_cache_ren),    // output wire
    .wb_cache_wen(wb_cache_wen),    // output wire
    .wb_cache_wdata(wb_cache_wdata),// output wire [31:0]
    .wb_cache_strb(wb_cache_strb),  // output wire [3:0] 
    .wb_cache_wayno(wb_cache_wayno), // output wire [3:0]

    .READ_TAG_SOFTWB(READ_TAG_SOFTWB),              // output wire       
    .clean_dirty_lineno(clean_dirty_lineno),        // output reg [9:6]  
    .clean_dirty_wayno(clean_dirty_wayno),          // output reg [3:0]  
    .clean_dirty_tagadr_i(clean_dirty_tagadr_o),    // input wire [22:10]
    .clean_dirty_dirty_i(clean_dirty_dirty_o),      // input wire
    .rewrite_tag_clean_dirty(rewrite_tag_clean_dirty), // output reg [3:0]  
    // tag書き戻し
    .rewrite_tagadr_clean_dirty(rewrite_tagadr_clean_dirty) // output wire [22:10]

);

brd_wb2ps_wc_inittag #
(
    .BURST_RNUM(8)
) brd_wb2ps_wc_inittag
(
    // System Signals
    .WSHRST(WSHRST),
    .cpuclk(cpuclk),       // wishbone clk

    // tag init中。強制 ready="0"& valid府認識
    // to brd_wb2ps_wc_enter
    .run_inittag(run_inittag),          // output reg      

    .taginit_en(taginit_en),            // output wire     
    .taginit_lineno(taginit_lineno)     // output reg [9:6]
);

brd_wb2ps_wc_fifodma brd_wb2ps_wc_fifodma
(
    // System Signals
    .WSHRST(WSHRST),
    .cpuclk(cpuclk),       // wishbone clk

    // System Signals PSRAM
    .PSRST(PSRST),
    .psclk(psclk),       // psram clk

    .fifo_wdata_wen2(fifo_wdata_wen2),      // in
    .fifo_wdata(fifo_wdata),                // in
    .fifo_wadrs(fifo_wadrs),                // in
    .fifo_warea(fifo_warea),                // in
    .fifo_startp(fifo_startp),              // in
    .fifo_endp(fifo_endp),
    .fifo_almost_full(fifo_almost_full),    // output
    .fifo_run(fifo_run),                    // output
    .fifo_run_endp(fifo_run_endp),          // output

    // PSRAM IF
    .psram_cmd(cmd_fifo),
    .psram_cmd_en(cmd_en_fifo),
    .psram_addr(addr_fifo),
    .psram_wdata(wr_data_fifo),
    .psram_mask(data_mask_fifo),
    .psram_ready(cmd_ready_fifo)

);

endmodule