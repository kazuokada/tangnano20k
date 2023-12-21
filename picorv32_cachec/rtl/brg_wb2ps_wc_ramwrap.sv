`timescale 1ns/1ps

module DPRAM_WRAP
  #(
    //---------------------------------------------------------------
    parameter   ADDR_WIDTH              =  4, // Addr  Width in bits : 2**ADDR_WIDTH = RAM Depth
    parameter   DATA_WIDTH              =  15  // Data  Width in bits
    //---------------------------------------------------------------
    ) (
       input clkA,
       input enA, 
       input weA,
       input [ADDR_WIDTH-1:0] addrA,
       input [DATA_WIDTH-1:0] dinA,
       output wire [DATA_WIDTH-1:0] doutA,
       
       input clkB,
       input enB,
       input weB,
       input [ADDR_WIDTH-1:0] addrB,
       input [DATA_WIDTH-1:0] dinB,
       output wire [DATA_WIDTH-1:0] doutB
       );

`ifdef  behav_sim
tdp_ram_nc #(
    .ADDR_WIDTH (4),        // 16word
    .DATA_WIDTH (1+1+13)      // dirty,valid, adr[22:10]
    ) dpram
    (
    .clkA(clkA),
    .weA(weA),
    .enA(enA),
    .addrA(addrA),
    .dinA(dinA),
    .doutA(doutA),

    .clkB(clkB),
    .weB(weB),
    .enB(enB),
    .addrB(addrB),
    .dinB(dinB),
    .doutB(doutB)
    );

`else
// read bypass /  write Normal
/*
    Gowin_DPB_tag dpram(
        .douta(doutA),  //output [14:0] douta
        .doutb(doutB),  //output [14:0] doutb
        .clka(clkA),    //input clka
        .ocea(1'b0),    //input ocea  A port 出力enable, bypassでは無効
        .cea(enA),      //input cea
        .reseta(1'b0),  //input reseta  リセット未使用
        .wrea(weA),     //input wrea
        .clkb(clkB),    //input clkb
        .oceb(1'b0),    //input oceb
        .ceb(enB),      //input ceb
        .resetb(1'b0),  //input resetb
        .wreb(weB),     //input wreb
        .ada(addrA),    //input [3:0] ada
        .dina(dinA),    //input [14:0] dina
        .adb(addrB),    //input [3:0] adb
        .dinb(dinB)     //input [14:0] dinb
    );
*/
DualPortMem  #(
    .ADDR_WIDTH (4),        // 16word
    .DATA_WIDTH (1+1+13)      // dirty,valid, adr[22:10]
    ) u_tagram (
    .clkA(clkA),
    .weA(weA),
    .enaA(enA),
    .addrA(addrA),
    .dinA(dinA),
    .doutA(doutA),

    .clkB(clkB),
    .weB(weB),
    .enaB(enB),
    .addrB(addrB),
    .dinB(dinB),
    .doutB(doutB)
);
   
`endif

endmodule

module DPRAM_BYTEW_WRAP
  #(
    //---------------------------------------------------------------
    parameter   NUM_COL                 =  4,
    parameter   COL_WIDTH               =  8,
    parameter   ADDR_WIDTH              =  8, // Addr  Width in bits : 2**ADDR_WIDTH = RAM Depth
    parameter   DATA_WIDTH              =  NUM_COL*COL_WIDTH  // Data  Width in bits
    //---------------------------------------------------------------
    ) (
       input clkA,
       input enaA, 
       input [NUM_COL-1:0] weA,
       input [ADDR_WIDTH-1:0] addrA,
       input [DATA_WIDTH-1:0] dinA,
       output wire [DATA_WIDTH-1:0] doutA,
       
       input clkB,
       input enaB,
       input [NUM_COL-1:0] weB,
       input [ADDR_WIDTH-1:0] addrB,
       input [DATA_WIDTH-1:0] dinB,
       output wire [DATA_WIDTH-1:0] doutB
       );

`ifdef  behav_sim
bytewrite_tdp_ram_nc #(
    .NUM_COL(4),    // 32bitを4分割(=byte write)
    .COL_WIDTH(8),  // 8bit単位でライト
    .ADDR_WIDTH(8)  // 16line x (64/4) = 256 -> 8bit
    ) dpram_bytew
    (
     .clkA(clkA),
     .enaA(enaA),    // WHITのみ
     .weA(weA),
     .addrA(addrA),
     .dinA(dinA),
     .doutA(doutA),
     
     .clkB(clkB),
     .enaB(enaB),
     .weB(weB),
     .addrB(addrB),
     .dinB(dinB),
     .doutB(doutB)
    );

`else
// ロジックアナライザ―用RAMを確保するため
//assign doutA = 0;
//assign doutB = 0;

// ロジックアナライザOFFの時は以下を有効化する
DualPortMem  #(
    .ADDR_WIDTH(8),
    .DATA_WIDTH(32)
    ) dpram
    (
     .clkA(clkA),
     .enaA(enaA),    // WHITのみ
     .weA(|weA),
     .addrA(addrA),
     .dinA(dinA),
     .doutA(doutA),
     
     .clkB(clkB),
     .enaB(enaB),
     .weB(|weB),
     .addrB(addrB),
     .dinB(dinB),
     .doutB(doutB)
    );

/*
    Gowin_DPB_data_dpram dpram(
        .douta(doutA), //output [7:0] douta
        .doutb(doutB), //output [7:0] doutb
        .clka(clkA), //input clka
        .ocea(1'b0), //input ocea :A port 出力enable, bypassでは無効
        .cea(enaA), //input cea
        .reseta(1'b0), //input reseta
        .wrea(|weA), //input wrea
        .clkb(clkB), //input clkb
        .oceb(1'b0), //input oceb
        .ceb(enaB), //input ceb
        .resetb(1'b0), //input resetb
        .wreb(|weB), //input wreb
        .ada(addrA), //input [7:0] ada
        .dina(dinA), //input [7:0] dina
        .adb(addrB), //input [7:0] adb
        .dinb(dinB) //input [7:0] dinb
    );
*/

/*
    Gowin_DPB_data_dpram dpram_bytew0(
        .douta(doutA[7:0]), //output [7:0] douta
        .doutb(doutB[7:0]), //output [7:0] doutb
        .clka(clkA), //input clka
        .ocea(1'b0), //input ocea :A port 出力enable, bypassでは無効
        .cea(enaA), //input cea
        .reseta(1'b0), //input reseta
        .wrea(weA[0]), //input wrea
        .clkb(clkB), //input clkb
        .oceb(1'b0), //input oceb
        .ceb(enaB), //input ceb
        .resetb(1'b0), //input resetb
        .wreb(weB[0]), //input wreb
        .ada(addrA), //input [7:0] ada
        .dina(dinA[7:0]), //input [7:0] dina
        .adb(addrB), //input [7:0] adb
        .dinb(dinB[7:0]) //input [7:0] dinb
    );
    Gowin_DPB_data_dpram dpram_bytew1(
        .douta(doutA[15:8]), //output [7:0] douta
        .doutb(doutB[15:8]), //output [7:0] doutb
        .clka(clkA), //input clka
        .ocea(1'b0), //input ocea :A port 出力enable, bypassでは無効
        .cea(enaA), //input cea
        .reseta(1'b0), //input reseta
        .wrea(weA[1]), //input wrea
        .clkb(clkB), //input clkb
        .oceb(1'b0), //input oceb
        .ceb(enaB), //input ceb
        .resetb(1'b0), //input resetb
        .wreb(weB[1]), //input wreb
        .ada(addrA), //input [7:0] ada
        .dina(dinA[15:8]), //input [7:0] dina
        .adb(addrB), //input [7:0] adb
        .dinb(dinB[15:8]) //input [7:0] dinb
    );
    Gowin_DPB_data_dpram dpram_bytew2(
        .douta(doutA[23:16]), //output [7:0] douta
        .doutb(doutB[23:16]), //output [7:0] doutb
        .clka(clkA), //input clka
        .ocea(1'b0), //input ocea :A port 出力enable, bypassでは無効
        .cea(enaA), //input cea
        .reseta(1'b0), //input reseta
        .wrea(weA[2]), //input wrea
        .clkb(clkB), //input clkb
        .oceb(1'b0), //input oceb
        .ceb(enaB), //input ceb
        .resetb(1'b0), //input resetb
        .wreb(weB[2]), //input wreb
        .ada(addrA), //input [7:0] ada
        .dina(dinA[23:16]), //input [7:0] dina
        .adb(addrB), //input [7:0] adb
        .dinb(dinB[23:16]) //input [7:0] dinb
    );
    Gowin_DPB_data_dpram dpram_bytew3(
        .douta(doutA[31:24]), //output [7:0] douta
        .doutb(doutB[31:24]), //output [7:0] doutb
        .clka(clkA), //input clka
        .ocea(1'b0), //input ocea :A port 出力enable, bypassでは無効
        .cea(enaA), //input cea
        .reseta(1'b0), //input reseta
        .wrea(weA[3]), //input wrea
        .clkb(clkB), //input clkb
        .oceb(1'b0), //input oceb
        .ceb(enaB), //input ceb
        .resetb(1'b0), //input resetb
        .wreb(weB[3]), //input wreb
        .ada(addrA), //input [7:0] ada
        .dina(dinA[31:24]), //input [7:0] dina
        .adb(addrB), //input [7:0] adb
        .dinb(dinB[31:24]) //input [7:0] dinb
    );
*/    
`endif

endmodule

