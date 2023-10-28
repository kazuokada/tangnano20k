`timescale 1ps/1ps
// Simple SDRAM controller for Tang 20k
// nand2mario
// 
// 2023.7: add buffers to din, dout and addr for ease-of-use.
// 2023.3: ported to use GW2AR-18's embedded 64Mbit SDRAM.
//         changed to byte-based access.
// 2022.9: iniital version.
//
// This is a byte-based, low-latency and non-bursting controller for the embedded SDRAM
// on Tang Nano 20K. The SDRAM module is 64Mbit 32bit. (2K rows x 256 columns x 4 banks x 32 bits).
//
// Under default settings (max 66.7Mhz):
// - Data read latency is 4 cycles. 
// - Read/write operations take 5 cycles to complete. There's no overlap between
//   reads/writes.
// - All reads/writes are done with auto-precharge. So user does not need to deal with
//   row activations and precharges.
// - SDRAMs need periodic refreshes or they lose data. So they provide an "auto-refresh"
//   function to do one row of refresh. This "auto-refresh" operation is controlled with
//   the 'refresh' input. 4096 or more refreshes should happen in any 64ms for the memory
//   to not lose data. So the main circuit should invoke auto-refresh at least once 
//   **every ~15us**.
//
// Finally you need a 180-degree phase-shifted clock signal (clk_sdram) for SDRAM. 
// This can be generated with PLL's clkoutp output.
//
// ------------------------------------------------
// Modified from above
//
// 2023/10/15:
//  Support burst transfer.
//  Change from AutoPrecharge to assert precharge command.
//  Change command i/f(Logical side interface)
//  Buit-in refresh request
//
// Under default settings (max 166Mhz):
// - Data read latency is 11 cycles.
// - When BurstLength is 16, Read operations take 19 cycles to complete.
// - When BurstLength is 16, Write operations take 26 cycles to complete.
//   There's no overlap between reads/writes.
// - All reads/writes are done with manual-precharge, so user can change burst length per access.
//   this controller does not use bank interleave access.
// - As for auto-resfresh function, it is the same as the original.
//
//  for SIM, must be define SDRAMC_SIM
//
module sdramc
#(
    parameter         FREQ = 166_000_000,  
    parameter         DATA_WIDTH = 32,
    parameter         ROW_WIDTH = 11,  // 2K rows
    parameter         COL_WIDTH = 8,   // 256 words per row (1Kbytes)
    parameter         BANK_WIDTH = 2,  // 4 banks

    // Time delays for 66.7Mhz max clock (min clock cycle 15ns)
    // The SDRAM supports max 166.7Mhz (RP/RCD/RC need changes)
    // Timing Parameters for -6 CL3
//    parameter [4:0]   CAS  = 5'd3,     // 2/3 cycles, set in mode register
//    parameter [4:0]   T_WR = 5'd2,     // 2 cycles, write recovery
//    parameter [4:0]   T_MRD= 5'd2,     // 2 cycles, mode register set
//    parameter [4:0]   T_RP = 5'd3,     // 18ns, precharge to active
//    parameter [4:0]   T_RCD= 5'd3,     // 18ns, active to r/w
//    parameter [4:0]   T_RC = 5'd10,    // 60ns, ref/active to ref/active
//    parameter [4:0]   T_RAS = 5'd7     // 42ns, active to precharge

    // Timing Parameters for -7 CL3
    parameter [4:0]   CAS  = 5'd3,     // 2/3 cycles, set in mode register
    parameter [4:0]   T_WR = 5'd3,     // 14ns, write recovery
    parameter [4:0]   T_MRD= 5'd2,     // 2 cycles, mode register set
    parameter [4:0]   T_RP = 5'd4,     // 20ns, precharge to active
    parameter [4:0]   T_RCD= 5'd4,     // 20ns, active to r/w
    parameter [4:0]   T_RC = 5'd12,    // 70ns, ref/active to ref/active
    parameter [4:0]   T_RAS = 5'd7     // 42ns, active to precharge
)
(
    // SDRAM side interface
    inout [DATA_WIDTH-1:0]      SDRAM_DQ,
    output reg [ROW_WIDTH-1:0]  SDRAM_A,
    output reg [BANK_WIDTH-1:0] SDRAM_BA,
    output            SDRAM_nCS,    // not strictly necessary, always 0
    output reg        SDRAM_nWE,
    output reg        SDRAM_nRAS,
    output reg        SDRAM_nCAS,
    output            SDRAM_CLK,
    output            SDRAM_CKE,    // not strictly necessary, always 1
    output reg  [3:0] SDRAM_DQM,
    
    // Logic side interface
    input             clk,
    input             clk_sdram,    // phase shifted from clk (normally 180-degrees)
    input             clk_capdq,
    input             resetn,
    input      [22:0] addr,         // byte address, buffered at cmd_en time. 8MB
    output reg        busy,         // 0: ready for next command

    input             cmd,          // 0:read, 1:write
    input             cmd_en,
    output wire       cmd_ack,
    input [3:0]       cmd_len,      // 0-15
    output reg [31:0] rd_data,
    output reg        rd_data_valid,
    input [31:0]      wr_data,
    input [3:0]       wr_mask
);

localparam   GET_DQ_1CYCDLY = 130_000_000;
// Tri-state DQ input/output
reg dq_oen;         // 0 means output
reg [DATA_WIDTH-1:0] dq_out;
assign SDRAM_DQ = dq_oen ? 32'bzzzz_zzzz_zzzz_zzzz_zzzz_zzzz_zzzz_zzzz : dq_out;
wire [DATA_WIDTH-1:0] dq_in;
// 実機想定で遅延入れる
`ifdef SDRAMC_SIM
generate
if(FREQ > GET_DQ_1CYCDLY) begin
reg [31:0] dly_SDRAM_DQ;
always @(posedge clk_capdq)
    dly_SDRAM_DQ <= SDRAM_DQ;
assign #(0) dq_in = dly_SDRAM_DQ;
end
else begin
wire [31:0] dly_SDRAM_DQ;
assign #(2500) dly_SDRAM_DQ = SDRAM_DQ;     // DQ input
assign #(2500) dq_in = dly_SDRAM_DQ;
end
endgenerate
`else
assign #(0) dq_in = SDRAM_DQ;     // DQ input
`endif

assign SDRAM_CLK = clk_sdram;
assign SDRAM_CKE = 1'b1;
assign SDRAM_nCS = 1'b0;

reg [3:0] state;
localparam INIT = 4'd0;
localparam CONFIG = 4'd1;
localparam IDLE = 4'd2;
localparam READ = 4'd3;
localparam WRITE = 4'd4;
localparam REFRESH = 4'd5;
localparam PRE = 4'd6;
localparam EXTRA = 4'd7;
localparam WAIT_TWR = 4'd8;
localparam R_PRE = 4'd9;

// RAS# CAS# WE#
localparam CMD_SetModeReg=3'b000;
localparam CMD_AutoRefresh=3'b001;
localparam CMD_PreCharge=3'b010;
localparam CMD_BankActivate=3'b011;
localparam CMD_Write=3'b100;
localparam CMD_Read=3'b101;
localparam CMD_NOP=3'b111;

localparam [2:0] BURST_LEN = 3'b0;      // burst length 1
localparam BURST_MODE = 1'b0;           // sequential
localparam [10:0] MODE_REG = {4'b0, CAS[2:0], BURST_MODE, BURST_LEN};

reg         cfg_now;    // pulse for configuration
reg [4:0]   cycle;      // each operation (config/read/write) are max 7 cycles
reg [22:0]  addr_buf;
reg [3:0]   len_buf;
reg [3:0]   readlen_buf2;

reg [COL_WIDTH-1:0] col_adr;
reg [1:0]   before_cmd;   // runned command before 00:init, 01:ref, 10:read, 11:write 
reg [3:0]   trans_cnt;
reg         trans_cnt_en;
reg [2:0]   trcd_cnt;
reg [3:0]   cl_cnt;
reg         cl_cnt_en;
reg [3:0]   get_dq_cnt;
reg         get_dq_en;
reg         get_dq_en2;
reg         get_dq_en3;
reg [31:0]  get_dq;

reg refresh_en;
reg refresh_ack;

wire [4:0] WR_PRE_TIM = (T_RAS>(T_RCD+len_buf+T_WR)) ? T_RAS :
                        (T_RCD+len_buf+T_WR);
wire [4:0] BEGIN_TWR =  T_RCD+len_buf+1;
wire [4:0] END_TWR = T_RCD+len_buf+T_WR-1;

wire [4:0] RD_PRE_TIM = (T_RAS>(T_RCD+len_buf+1'b1)) ? T_RAS :
                        (T_RCD+len_buf+1'b1);
                       
//
// SDRAM state machine
//
always @(posedge clk) begin
    cycle <= cycle == 5'd31 ? 5'd31 : cycle + 5'd1;
    // defaults
    {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_NOP; 
    casex ({state, cycle})
        // wait 200 us on power-on
        {INIT, 5'bxxxxx} : if (cfg_now) begin
            state <= CONFIG;
            cycle <= 0;
            before_cmd <= 2'b00;
        end

        // configuration sequence
        //  cycle  / 0 \___/ 1 \___/ 2 \___/ ... __/ 6 \___/ ...___/10 \___/11 \___/ 12\___
        //  cmd            |PC_All |Refresh|       |Refresh|       |  MRD  |       | _next_
        //                 '-T_RP--`----  T_RC  ---'----  T_RC  ---'------T_MRD----'
        {CONFIG, 5'd0} : begin
            // precharge all
            {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_PreCharge;
            SDRAM_A[10] <= 1'b1;
        end
        {CONFIG, T_RP} : begin
            // 1st AutoRefresh
            {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_AutoRefresh;
        end
        {CONFIG, T_RP+T_RC} : begin
            // 2nd AutoRefresh
            {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_AutoRefresh;
        end
        {CONFIG, T_RP+T_RC+T_RC} : begin
            // set register
            {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_SetModeReg;
            SDRAM_A[10:0] <= MODE_REG;
        end
        {CONFIG, T_RP+T_RC+T_RC+T_MRD} : begin
            state <= IDLE;
            busy <= 1'b0;              // init&config is done
        end
        
        // read/write/refresh
        {IDLE, 5'bxxxxx}:
        if (refresh_en) begin
            // auto-refresh
            // no need for precharge-all b/c all our r/w are done with auto-precharge.
            {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_AutoRefresh;
            state <= REFRESH;
            cycle <= 5'd1;
            busy <= 1'b1;
        end
        else if (cmd_en) begin
            // bank activate
            {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_BankActivate;
            SDRAM_BA <= addr[ROW_WIDTH+COL_WIDTH+BANK_WIDTH-1+2 : ROW_WIDTH+COL_WIDTH+2];    // bank id
            SDRAM_A <= addr[ROW_WIDTH+COL_WIDTH-1+2:COL_WIDTH+2];      // 12-bit row address
            addr_buf <= addr;
            col_adr <= addr[COL_WIDTH-1+2:2];
            len_buf <= cmd_len;
            busy <= 1'b1;
            // R -> W & early write access
            if ( (before_cmd == 2'b10) & cmd &  // before read & current write
                ((cycle==5'h01) | (cycle==5'h02)) ) begin
                cycle <= cycle;
                state <= EXTRA;
            end
            else begin
                state <= cmd ? WRITE : READ;
                if(cmd)
                    dq_oen <= 1'b0;                 // DQ output on
                //if (wr) din_buf <= din;
                cycle <= 4'd1;
            end
        end
        // read sequence
        //  cycle  / 0 \___/ 1 \___/ 2 \___/ 3 \___/ 4 \___/ 5 \___
        //  rd     /       \_______________________________
        //  cmd            |Active | Read  |  NOP  |  NOP  | _Next_
        //  DQ                                     |  Dout |
        //  data_ready ____________________________/       \_______   
        //  busy   ________/                               \_______
        //                 `-T_RCD-'------CAS------'
        {READ, 5'bxxxxx}: begin
            if(trcd_cnt == T_RCD) begin
                {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_Read;
                SDRAM_A[10] <= 1'b0;        // disable auto precharge
                SDRAM_A[9:0] <= {1'b0, col_adr};  // column address
                SDRAM_DQM <= 4'b0;
                col_adr <= col_adr + 1'b1;
                before_cmd <= 2'b10;
                if( (len_buf == 4'h0) | (trans_cnt==len_buf) ) begin
                    //cycle <= 5'd1;
                    state <= R_PRE;
                end
            end
        end
        //{PRE, 5'h01}: begin
        {PRE, WR_PRE_TIM}: begin
            {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_PreCharge;
            SDRAM_A[10] <= 1'b0;        // Single Bank precharge
            SDRAM_BA <= addr_buf[ROW_WIDTH+COL_WIDTH+BANK_WIDTH-1+2 : ROW_WIDTH+COL_WIDTH+2];    // bank id
            dq_oen <= 1'b1;     // DQ Hi-Z
            if(T_RP==5'h01) begin
                busy <= 0;
                cycle <= 5'd1;
                state <= IDLE;
            end
        end
        {PRE, WR_PRE_TIM+T_RP-5'd1}: begin
            busy <= 0;
            cycle <= 5'd1;
            state <= IDLE;
        end
        {R_PRE, RD_PRE_TIM}: begin
            {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_PreCharge;
            SDRAM_A[10] <= 1'b0;        // Single Bank precharge
            SDRAM_BA <= addr_buf[ROW_WIDTH+COL_WIDTH+BANK_WIDTH-1+2 : ROW_WIDTH+COL_WIDTH+2];    // bank id
            if(T_RP==5'h01) begin
                busy <= 0;
                cycle <= 5'd1;
                state <= IDLE;
            end
        end
        {R_PRE, RD_PRE_TIM+T_RP-5'd1}: begin
            busy <= 0;
            cycle <= 5'd1;
            state <= IDLE;
        end

        // write sequence
        //  cycle / 0 \___/ 1 \___/ 2 \___/ 3 \___/ 4 \___/ 5 \___
        //  wr    /       \_______________________________
        //  cmd           |Active | Write |  NOP  |  NOP  | _Next_
        //  DQ                    |wr_data|
        //  busy   _______/                               \_______
        //                `-T_RCD-'-------T_WR+T_RP-------'
        {WRITE, 5'bxxxxx}: begin
            if(trcd_cnt == T_RCD) begin
                {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_Write;
                SDRAM_A[10] <= 1'b0;        // disable auto precharge
                SDRAM_A[9:0] <= {1'b0,col_adr};  // column address
                SDRAM_DQM <= wr_mask;
                dq_out <= wr_data;
                //dq_oen <= 1'b0;                 // DQ output on
                col_adr <= col_adr + 1'b1;
                before_cmd <= 2'b11;
                if( (len_buf == 4'h0) | (trans_cnt==len_buf) ) begin
                    //cycle <= 5'd1;
                    if(T_WR==5'h01) begin
                        state <= PRE;
                        //dq_oen <= 1'b1;
                    end
                    else
                        state <= WAIT_TWR;
                end
            end
        end

        // refresh sequence
        //  cycle   / 0 \___/ 1 \___/ 2 \___/ 3 \___/ 4 \___/ 5 \___
        //  refresh /       \_______________________________
        //  cmd             |Refresh|  NOP  |  NOP  |  NOP  | _Next_
        //  busy     _______/                               \_______
        //                  `------------- T_RC ------------'
        {REFRESH, T_RC}: begin
            state <= IDLE;
            busy <= 0;
            before_cmd <= 2'b01;
        end
        
        // EXTRA cycle
        // when read to write cycle is 1 or 2, insert nop cycle
        {EXTRA, 5'h02}: begin
            cycle <= 4'd1;
            state <= WRITE;
            dq_oen <= 1'b0;                 // DQ output on
        end
        // tWR wait cycle
        {WAIT_TWR, BEGIN_TWR}: begin
            dq_oen <= 1'b1;
            if(T_WR==5'h02) begin   // cycle==(T_WR-1)
                //cycle <= 5'd1;
                state <= PRE;
            end
        end
        {WAIT_TWR, END_TWR}: begin
            //cycle <= 5'd1;
            state <= PRE;
        end
    endcase

    if (~resetn) begin
        busy <= 1'b1;
        dq_oen <= 1'b1;         // turn off DQ output
        SDRAM_DQM <= 4'b0;
        before_cmd <= 2'b00;
        state <= INIT;
    end
end


//
// Generate cfg_now pulse after initialization delay (normally 200us)
//
reg  [15:0]   rst_cnt;
reg rst_done, rst_done_p1, cfg_busy;
  
always @(posedge clk) begin
    rst_done_p1 <= rst_done;
    cfg_now     <= rst_done & ~rst_done_p1;// Rising Edge Detect

    if (rst_cnt != FREQ / 1000 * 200 / 1000) begin      // count to 200 us
        rst_cnt  <= rst_cnt[15:0] + 1;
        rst_done <= 1'b0;
        cfg_busy <= 1'b1;
    end else begin
        rst_done <= 1'b1;
        cfg_busy <= 1'b0;
    end

    if (~resetn) begin
        rst_cnt  <= 16'd0;
        rst_done <= 1'b0;
        cfg_busy <= 1'b1;
    end
end

// --------------------
// Generate trans_cnt
// --------------------
always @(posedge clk)
    if(~resetn)
        trans_cnt_en <= 1'b0;
    else if(state==IDLE)
        trans_cnt_en <= 1'b0;
    else if(trans_cnt == len_buf)
        trans_cnt_en <= 1'b0;
    else if(cmd_ack)
        trans_cnt_en <= 1'b1;
        
always @(posedge clk)
    if(state==IDLE)
        trans_cnt <= 4'h0;
    else if( cmd_ack )
        trans_cnt <= 4'h1;
    else if(trans_cnt_en)
        trans_cnt <= trans_cnt + 4'h1;

// --------------------
// Generate trcd_cnt
// --------------------
always @(posedge clk)
    if( (state==IDLE)&cmd_en )
        trcd_cnt <= 3'b001;
    else if(trcd_cnt != T_RCD)
        trcd_cnt <= trcd_cnt + 3'b001;

// --------------------
// count cas latency
// --------------------
always @(posedge clk)
    if( state==IDLE )
        cl_cnt <= 4'h0;
    else if( cmd_ack )
        cl_cnt <= 4'h1;
    else if(cl_cnt_en) begin
        cl_cnt <= cl_cnt + 4'h1;
    end
always @(posedge clk)
    if( state==IDLE )
        cl_cnt_en <= 1'b0;
    else if( cmd_ack&(~cmd) )
        cl_cnt_en <= 1'b1;
    else if(cl_cnt_en & (cl_cnt==CAS))
        cl_cnt_en <= 1'b0;
// ---------------------------------------
// rd_data_valid_cnt / rd_data_valid
// ---------------------------------------
always @(posedge clk)
    if(~resetn)
        get_dq_en <= 1'b0;
    else if(cl_cnt_en&(cl_cnt==CAS))
        get_dq_en <= 1'b1;
    else if(get_dq_en&(get_dq_cnt==readlen_buf2))
        get_dq_en <= 1'b0;

always @(posedge clk)
    if(~resetn)
        get_dq_en2 <= 1'b0;
    else
        get_dq_en2 <= get_dq_en;
always @(posedge clk)
    if(~resetn)
        get_dq_en3 <= 1'b0;
    else
        get_dq_en3 <= get_dq_en2;
generate
if(FREQ > GET_DQ_1CYCDLY) begin
always @(posedge clk)
    if(~resetn)
        rd_data_valid <= 1'b0;
    else
        rd_data_valid <= get_dq_en3;
end
else begin
always @(posedge clk)
    if(~resetn)
        rd_data_valid <= 1'b0;
    else
        rd_data_valid <= get_dq_en2;
end

endgenerate

always @(posedge clk)
    if(~resetn)
        get_dq_cnt <= 4'h0;
    else if(cl_cnt_en&(cl_cnt==CAS))
        get_dq_cnt <= 4'h0;
    else if(get_dq_en)
        get_dq_cnt <= get_dq_cnt + 4'h1;

// ---------------------------------------
// rd_data
// ---------------------------------------
generate
if(FREQ > GET_DQ_1CYCDLY) begin
    //always @(posedge clk_sdram)
    always @(posedge clk_capdq)
        if(get_dq_en2)
            get_dq <= dq_in;
    always @(posedge clk)
        if(get_dq_en3)
            rd_data <= get_dq;

end
else begin
    always @(posedge clk_capdq)
        if(get_dq_en)
            get_dq <= dq_in;
    always @(posedge clk)
        if(get_dq_en2)
            rd_data <= get_dq;
end
endgenerate

// ---------------------------------------
// readlen_buf2
// len_bufをCAS latency後、再ラッチ
// ---------------------------------------
always @(posedge clk)
    if(cl_cnt_en&(cl_cnt==CAS))
        readlen_buf2 <= len_buf;


// ---------------------------------------
// Generate auto refresh request
// 4096 refresh cycles in 64ms. Once per 15us.
// ---------------------------------------
wire [12:0] REFRESH_CYCLE=(FREQ/1000000)*15;
reg [12:0] ref_cnt;

always @(posedge clk)
    if(state==CONFIG)
        ref_cnt <= 13'h0000;
    else if (ref_cnt == REFRESH_CYCLE)
        ref_cnt <= 13'h0000;
    else
        ref_cnt <= ref_cnt + 13'h0001;
always @(posedge clk)
    if((~resetn)|(state==CONFIG))
        refresh_en <= 1'b0;
    else if(refresh_ack)
        refresh_en <= 1'b0;
    else if(ref_cnt == REFRESH_CYCLE)
        refresh_en <= 1'b1;

// ---------------------------------------
// cmd_en, refresh_en arbitration
// priority high : refresh_en
// ---------------------------------------

// ---------------------------------------
// cmd_ack
// ---------------------------------------
wire cmd_ack0;
reg  cmd_ack1;
assign cmd_ack0 = ((state==WRITE)|(state==READ))&(trcd_cnt == T_RCD);
always @(posedge clk)
    cmd_ack1 <= cmd_ack0;
assign cmd_ack =  cmd_ack0&(~cmd_ack1);

// ---------------------------------------
// refresh_ack
// ---------------------------------------
always @(posedge clk)
    if(~resetn)
        refresh_ack <= 1'b0;
    else if(refresh_ack)
        refresh_ack <= 1'b0;
    else if((state==IDLE)&refresh_en)
        refresh_ack <= 1'b1;
// 
endmodule