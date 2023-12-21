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
// cache tag 初期化
module brd_wb2ps_wc_inittag #
(
    parameter integer BURST_RNUM = 8
)
(
    // System Signals
    input WSHRST,
    input cpuclk,       // wishbone clk

    // tag init中。強制 ready="0"& valid府認識
    // to brd_wb2ps_wc_enter
    output reg          run_inittag,

    output wire         taginit_en,
    output reg [9:6]    taginit_lineno

);


// ---------------------------------
// 内部信号
// ---------------------------------
reg         init_tag_int;
reg         init_tag_int2;
reg         init_tag_int3;
reg [1:0]   state;
reg [1:0]   next_state;

// ---------------------------------
// init_tag_pulse_int(init tag internal)
// ---------------------------------
always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST) begin
        init_tag_int <= 1'b0;
        init_tag_int2 <= 1'b0;
        init_tag_int3 <= 1'b0;
    end
    else begin
        init_tag_int <= 1'b1;
        init_tag_int2 <= init_tag_int;
        init_tag_int3 <= init_tag_int2;
    end

wire init_tag_int_rise = init_tag_int2 & (~init_tag_int3);

// ---------------------------------
// state machine
// ---------------------------------
parameter   S0  = 2'h0,
            S1  = 2'h1,
            S2  = 2'h2,
            S3  = 2'h3;

wire        S0ack=(state==S0);
wire        S1ack=(state==S1);
wire        S2ack=(state==S2);
wire        S3ack=(state==S3);

always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        state <= 3'h0;
    else
        state <= next_state;


always@* begin
    case (state)
        S0 : if(init_tag_int_rise)
                next_state = S1;
             else
                next_state = S0;
        S1 : if(taginit_lineno==4'hf)
                next_state = S2;
             else
                next_state = S1;
        S2 : next_state = S2;
        default : next_state = S0;
    endcase
end

// ---------------------------------
// taginit_lineno
// ---------------------------------
always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        taginit_lineno <= 4'h0;
    else if(init_tag_int_rise|S1ack)
        taginit_lineno <= taginit_lineno + 4'h1;

assign taginit_en = init_tag_int_rise|S1ack;
// ---------------------------------
// run_inittag
// ---------------------------------
always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        run_inittag <= 1'b0;
    else
        run_inittag <= S1ack;
        


endmodule
