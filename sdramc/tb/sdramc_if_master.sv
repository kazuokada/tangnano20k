`timescale 1ps/1ps
// PSRAM 擬似モデル
// 64burst(64byte) 転送
// data幅 32bit
// 入力アドレスは4byteでなく2byteバウンダリ

module sdramc_master (
    input wire          clk,       // 166MHz clk
    output reg          cmd,           //input cmd 0:read, 1:write
    output reg          cmd_en,        //input cmd_en
    input wire          cmd_ack,
    output reg [3:0]    cmd_len,
    output reg [22:0]   addr,  // byte address
    output wire [31:0]  wr_data,
    output wire [3:0]   wr_mask,
    input wire [31:0]   rd_data,
    input wire          rd_data_valid
    
    );

// write タスク呼び出す際は以下のregへバースト分のデータを
// 入れておくこと
reg [31:0] wdata[0:15];
reg [3:0]  wmask[0:15];

// 読み出し時にデータが格納される
reg [31:0] rdata[0:15];

reg [31:0]  radrs[0:3];
reg [2:0]   read_rpt;
reg [2:0]   read_wpt;

reg [31:0]  wadrs[0:3];
reg [3:0]   wlen[0:3];
reg [2:0]   write_rpt;
reg [2:0]   write_wpt;

event kick_a_write;
event complete_write;

task init;
    begin
        cmd_en=0;
        read_rpt=0;
        read_wpt=0;
        write_rpt=0;
        write_wpt=0;
    end
endtask

// アドレス指定
task a_write;
    input [31:0] adrs;
    input [3:0] len;
    
    integer i;
    begin
        cmd=1;      // write
        cmd_en=1;
        addr = adrs[22:0];
        wadrs[write_wpt&3]=adrs;
        wlen[write_wpt&3]=len;
        write_wpt=write_wpt+1;
        cmd_len=len;
        i=0;
        //wr_data=wdata[i];
        //wr_mask = wmask[i];
        i=i+1;
        while(cmd_ack==0)
            @(posedge clk);
        -> kick_a_write;
        #10;
        cmd_en=0;
    end
endtask

// データ指定
integer pt_wdata;
reg [31:0] wdata2;
reg [3:0] wmask2;
assign wr_data = cmd_ack ? wdata[0] : wdata2;
assign wr_mask = cmd_ack ? wmask[0] : wmask2;

   
initial begin
    #100;
    while(1) begin
        pt_wdata=1;
        @(kick_a_write);
        repeat(wlen[write_rpt&3]) begin
            #10;
            wdata2=wdata[pt_wdata];
            wmask2 = wmask[pt_wdata];
            pt_wdata = pt_wdata + 1;
            @(posedge clk);
        end
        write_rpt=write_rpt+1;
        -> complete_write;
        
    end
    
end




// アドレス指定
task a_read;
    input [31:0] adrs;
    input [3:0] len;
    integer i;
    begin
        cmd=0;      // read
        cmd_en=1;
        addr = adrs[22:0];
        radrs[read_wpt&3]=adrs;
        cmd_len=len;
        while(cmd_ack==0)
            @(posedge clk);
        #10;
        read_wpt=read_wpt+1;
        cmd_en=0;
    end
endtask

// リードデータ取得
task d_read;
    input [31:0] adrs;
    input [3:0] len;
    
    integer i;
    begin
        i=0;
        while(rd_data_valid==0)
            @(posedge clk);
        rdata[i]=rd_data;
        read_rpt = read_rpt+1;
        i=i+1;
        repeat(len) begin
            @(posedge clk);
            while(rd_data_valid==0)
                @(posedge clk);
            rdata[i]=rd_data;
            i=i+1;
        end
    end
endtask



endmodule