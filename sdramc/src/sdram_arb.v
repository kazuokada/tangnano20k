`timescale 1ns / 1ps
// PSRAM I/F arbiter
// 3ch版
// 優先順位
// S0: 最強
// S1,S2 : 交互
module sdram_arb
(
    input  wire         rst_n, // sdramclk同期化済み
    input  wire         sdramclk,  //166MHz
    
    // SDRAM コマンドインターフェース(アービトレーション後)
    output reg          sdram_cmd,
    output reg          sdram_cmd_en,
    output reg [22:0]   sdram_addr,
    input wire [31:0]   sdram_rdata,
    input wire          sdram_rvalid,
    output wire[31:0]   sdram_wdata,
    output wire[3:0]    sdram_mask,
    input wire          sdram_ack,
    output reg [3:0]    sdram_cmd_len,
    
    // アービトレーション前 I/F
    input wire          cmd_s0,
    input wire          cmd_en_s0,
    input wire [22:0]   addr_s0,
    input wire [3:0]    len_s0,
    output wire [31:0]  rdata_s0,
    output wire         rvalid_s0,
    input wire [31:0]   wdata_s0,
    input wire [3:0]    mask_s0,
    output reg          cmd_ready_s0,
    

    input wire          cmd_s1,
    input wire          cmd_en_s1,
    input wire [22:0]   addr_s1,
    input wire [3:0]    len_s1,
    output wire [31:0]  rdata_s1,
    output wire         rvalid_s1,
    input wire [31:0]   wdata_s1,
    input wire [3:0]    mask_s1,
    output reg          cmd_ready_s1,

    input wire          cmd_s2,
    input wire          cmd_en_s2,
    input wire [22:0]   addr_s2,
    input wire [3:0]    len_s2,
    output wire [31:0]  rdata_s2,
    output wire         rvalid_s2,
    input wire [31:0]   wdata_s2,
    input wire [3:0]    mask_s2,
    output reg          cmd_ready_s2

);

// ---------------------------------
// 内部信号
// ---------------------------------

wire        rst_sdramclk;

reg [1:0]   sel_ch;
reg         sel_s1s2;   // 0:s1, 1:s2
reg [1:0]   sel_ch_hold;
reg [1:0]   sel_ch_read;
reg [3:0]   sel_len;
reg [3:0]   len_hold;
wire        sel_read;
wire        sel_write;
reg [4:0]   wfifo_wpt;
reg [4:0]   wfifo_rpt;
reg [31:0]  wfifo_data [0:15];
reg [3:0]   wfifo_mask [0:15];
wire [31:0] sel_wdata;
wire [3:0]  sel_wmask;
reg [31:0]  rdata_sx;
reg         rvalid_sx;

reg         rst_n_sdramclk_sync1;
reg         rst_n_sdramclk_sync2;


reg [2:0]   state;
reg [2:0]   next_state;
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
wire        S5ack=(state==S5);
wire        S6ack=(state==S6);
wire        S7ack=(state==S7);


// 
// reset 同期化
// 
always@(posedge sdramclk or negedge rst_n)
    if(!rst_n) begin
        rst_n_sdramclk_sync1 <= 1'b0;
        rst_n_sdramclk_sync2 <= 1'b0;
    end
    else begin
        rst_n_sdramclk_sync1 <= rst_n;
        rst_n_sdramclk_sync2 <= rst_n_sdramclk_sync1;
    end
assign rst_sdramclk = ~rst_n_sdramclk_sync2;


// ---------------------------------
// state
// ---------------------------------
always@(posedge sdramclk or posedge rst_sdramclk)
    if(rst_sdramclk)
        state <= 3'h0;
    else
        state <= next_state;


always@* begin
    case (state)
        S0 : if(cmd_en_s0|cmd_en_s1|cmd_en_s2) begin
                if(sel_read)
                    next_state = S1;
                else
                    next_state = S3;
             end
             else
                next_state = S0;
        S1 : if(sdram_ack)
                next_state = S2;
             else
                next_state = S1;
        S2 :  next_state = S0;
        S3 : if(sdram_ack & (wfifo_wpt[3:0]==sel_len))
                next_state = S0;
             else if(sdram_ack)
                next_state = S4;
             else if(wfifo_wpt[3:0]==sel_len)
                next_state = S5;
             else
                next_state = S3;
        S4 : if(wfifo_wpt[3:0]==sel_len)
                next_state = S0;
              else
                next_state = S4;
        S5 : if(sdram_ack)
                next_state = S0;
              else
                next_state = S5;
        default : next_state = S0;
    endcase
end



// ----------------------------
// arbitration
// ----------------------------
reg [1:0] w_sel_ch;
always@* begin
    casex ({cmd_en_s0,cmd_en_s1,cmd_en_s2,sel_s1s2})
        {1'b1, 3'bxxx}:
            w_sel_ch = 2'b00;
        {1'b0, 1'b1, 1'b0, 1'bx}:
            w_sel_ch = 2'b01;
        {1'b0, 1'b0, 1'b1, 1'bx}:
            w_sel_ch = 2'b10;
        {1'b0, 1'b1, 1'b1, 1'b0}:   // 前回s1
            w_sel_ch = 2'b10;
        {1'b0, 1'b1, 1'b1, 1'b1}:   // 前回S2
            w_sel_ch = 2'b01;
        default : w_sel_ch = 2'b00;
    endcase
end    

// ----------------------------
// aibitration 結果 hold
// ----------------------------
always@(posedge sdramclk)
    if(S0ack&(cmd_en_s0|cmd_en_s1|cmd_en_s2)) begin
        sel_ch <= w_sel_ch;
        sel_len <= (w_sel_ch==2'b00) ? len_s0:
                   (w_sel_ch==2'b01) ? len_s1:
                   len_s2 ;
    end

always@(posedge sdramclk or posedge rst_sdramclk)
    if(rst_sdramclk)
        sel_s1s2 <= 1'b0;
    else if(S0ack&(cmd_en_s0|cmd_en_s1|cmd_en_s2))
        sel_s1s2 <= (w_sel_ch==2'b01) ? 1'b0:
                    (w_sel_ch==2'b10) ? 1'b1:
                    sel_s1s2;
// ----------------------------
// aibitration 結果 hold 2段目
// ----------------------------
always@(posedge sdramclk)
    if(sdram_ack) begin
        len_hold <= sdram_cmd_len;
        sel_ch_hold <= sel_ch;
    end
// ----------------------------
// read, write?
// ----------------------------
assign sel_read = (w_sel_ch==2'b00) ? (cmd_s0==1'b0):
                  (w_sel_ch==2'b01) ? (cmd_s1==1'b0):
                  (w_sel_ch==2'b10) ? (cmd_s2==1'b0):
                  1'b0;
assign sel_write= (w_sel_ch==2'b00) ? (cmd_s0==1'b1):
                  (w_sel_ch==2'b01) ? (cmd_s1==1'b1):
                  (w_sel_ch==2'b10) ? (cmd_s2==1'b1):
                  1'b0;


// ----------------------------
// fifo 16byte カウンタ
// ----------------------------
always@(posedge sdramclk or posedge rst_sdramclk)
    if(rst_sdramclk)
        wfifo_wpt <= 5'h00;
    else if(S3ack|S4ack) begin
        if(wfifo_wpt[3:0]==sel_len)
            wfifo_wpt <= 5'h00;
        else
            wfifo_wpt <= wfifo_wpt + 5'h01;
    end
always@(posedge sdramclk or posedge rst_sdramclk)
    if(rst_sdramclk)
        wfifo_rpt <= 5'h00;
    else if((S3ack|S5ack)&sdram_ack) begin
        if(sdram_cmd_len==4'h0)
            wfifo_rpt <= 5'h00;
        else
            wfifo_rpt <= wfifo_rpt + 5'h01;
    end
    else if(wfifo_rpt[3:0]!=4'h0) begin
        if(wfifo_rpt[3:0]==len_hold)
            wfifo_rpt <= 5'h00;
        else
            wfifo_rpt <= wfifo_rpt + 5'h01;
    end
    
// ----------------------------
// fifo 書き込み
// ----------------------------
assign sel_wdata = (sel_ch==2'b00) ? wdata_s0:
                   (sel_ch==2'b01) ? wdata_s1:
                    wdata_s2;
assign sel_wmask = (sel_ch==2'b00) ? mask_s0:
                   (sel_ch==2'b01) ? mask_s1:
                    mask_s2;
                    
always@(posedge sdramclk)
    if(S3ack|S4ack) begin
        wfifo_data[wfifo_wpt[3:0]] <= sel_wdata;
        wfifo_mask[wfifo_wpt[3:0]] <= sel_wmask;
    end
    
// ----------------------------
// cmd_ready*
// ----------------------------
always@(posedge sdramclk or posedge rst_sdramclk)
    if(rst_sdramclk)
        cmd_ready_s0 <= 1'b0;
    else if(cmd_ready_s0)
        cmd_ready_s0 <= 1'b0;
    else if(S1ack&(sel_ch==2'b00)&sdram_ack)
        cmd_ready_s0 <= 1'b1;
    else if(S0ack&sel_write&(w_sel_ch==2'b00))
        cmd_ready_s0 <= 1'b1;

always@(posedge sdramclk or posedge rst_sdramclk)
    if(rst_sdramclk)
        cmd_ready_s1 <= 1'b0;
    else if(cmd_ready_s1)
        cmd_ready_s1 <= 1'b0;
    else if(S1ack&(sel_ch==2'b01)&sdram_ack)
        cmd_ready_s1 <= 1'b1;
    else if(S0ack&sel_write&(w_sel_ch==2'b01))
        cmd_ready_s1 <= 1'b1;

always@(posedge sdramclk or posedge rst_sdramclk)
    if(rst_sdramclk)
        cmd_ready_s2 <= 1'b0;
    else if(cmd_ready_s2)
        cmd_ready_s2 <= 1'b0;
    else if(S1ack&(sel_ch==2'b10)&sdram_ack)
        cmd_ready_s2 <= 1'b1;
    else if(S0ack&sel_write&(w_sel_ch==2'b10))
        cmd_ready_s2 <= 1'b1;

// ----------------------------
// 各信号選択
// ----------------------------
always@(posedge sdramclk)
    if(S0ack&(cmd_en_s0|cmd_en_s1|cmd_en_s2)) begin
        if(w_sel_ch==2'b00) begin
            sdram_cmd <= cmd_s0;
            sdram_addr <= addr_s0;
            sdram_cmd_len <= len_s0;
        end
        else if(w_sel_ch==2'b01) begin
            sdram_cmd <= cmd_s1;
            sdram_addr <= addr_s1;
            sdram_cmd_len <= len_s1;
        end
        else if(w_sel_ch==2'b10) begin
            sdram_cmd <= cmd_s2;
            sdram_addr <= addr_s2;
            sdram_cmd_len <= len_s2;
        end
    end

always@(posedge sdramclk or posedge rst_sdramclk)
    if(rst_sdramclk)
        sdram_cmd_en <= 1'b0;
    else if((S1ack|S3ack|S5ack)&sdram_ack)
        sdram_cmd_en <= 1'b0;
    else if(S0ack&(cmd_en_s0|cmd_en_s1|cmd_en_s2))
        sdram_cmd_en <= 1'b1;

assign sdram_wdata = wfifo_data[wfifo_rpt[3:0]];
assign sdram_mask = wfifo_mask[wfifo_rpt[3:0]];

    
// ----------------------------
// rvalid_s*
// ----------------------------
always@(posedge sdramclk or posedge rst_sdramclk)
    if(rst_sdramclk)
        rvalid_sx <= 1'b0;
    else
        rvalid_sx <= sdram_rvalid;

always@(posedge sdramclk)
    if(sdram_rvalid&(~rvalid_sx))
        sel_ch_read <= sel_ch_hold;

wire [1:0] w_sel_ch_read;
assign w_sel_ch_read = (sdram_rvalid&(~rvalid_sx)) ? sel_ch_hold:
                        sel_ch_read;
                        
assign rvalid_s0 = (w_sel_ch_read==2'b00)&rvalid_sx;
assign rvalid_s1 = (w_sel_ch_read==2'b01)&rvalid_sx;
assign rvalid_s2 = (w_sel_ch_read==2'b10)&rvalid_sx;

always@(posedge sdramclk)
    if(sdram_rvalid)
        rdata_sx <= sdram_rdata;

assign rdata_s0 = rdata_sx;
assign rdata_s1 = rdata_sx;
assign rdata_s2 = rdata_sx;



endmodule
