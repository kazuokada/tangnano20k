`timescale 1ns/1ps

module fifo_1rd1wr
  #(
    //---------------------------------------------------------------
    parameter   ADDR_WIDTH              =  8, // Addr  Width in bits : 2**ADDR_WIDTH = RAM Depth
    parameter   DATA_WIDTH              =  32  // Data  Width in bits
    //---------------------------------------------------------------
    ) (
        // write port
        input clkA,
        input enaA, 
        input weA,
        input [ADDR_WIDTH-1:0] addrA,
        input [DATA_WIDTH-1:0] dinA,
        //output reg [DATA_WIDTH-1:0] doutA,
       
        // read port
        input clkB,
        input enaB,
        input [ADDR_WIDTH-1:0] addrB,
        //input [DATA_WIDTH-1:0] dinB,
        output reg [DATA_WIDTH-1:0] doutB
        );

    reg [DATA_WIDTH-1:0]    ram_block [(2**ADDR_WIDTH)-1:0];

    always @(posedge clkA) 
        if (enaA&weA) begin
            ram_block[addrA] <= dinA;
        end
 
            
    always@(posedge clkB)
        if(enaB)
            doutB <= ram_block[addrB]; 

endmodule 


// Dual-Port memory
//

module DualPortMem
  #(
    //---------------------------------------------------------------
    parameter   ADDR_WIDTH              =  8, // Addr  Width in bits : 2**ADDR_WIDTH = RAM Depth
    parameter   DATA_WIDTH              =  32  // Data  Width in bits
    //---------------------------------------------------------------
    ) (
       input clkA,
       input enaA, 
       //input [3:0] weA,
       input weA,
       input [ADDR_WIDTH-1:0] addrA,
       input [DATA_WIDTH-1:0] dinA,
       output reg [DATA_WIDTH-1:0] doutA,
       
       input clkB,
       input enaB,
       input weB,
       input [ADDR_WIDTH-1:0] addrB,
       input [DATA_WIDTH-1:0] dinB,
       output reg [DATA_WIDTH-1:0] doutB
       );

    reg [DATA_WIDTH-1:0]    ram_block [(2**ADDR_WIDTH)-1:0];

    always @(posedge clkA) 
        if (enaA&weA) begin
            ram_block[addrA] <= dinA;
        end
    always@(posedge clkA)
        if(enaA&(~weA))
            doutA <= ram_block[addrA]; 

    always@(posedge clkB) 
        if (enaB&weB) 
            ram_block[addrB] <= dinB;
            
    always@(posedge clkB)
        if(enaB&(~weB))
            doutB <= ram_block[addrB]; 

endmodule 


//
// True-Dual-Port BRAM with Byte-wide Write Enable
//      No-Change mode
//
// bytewrite_tdp_ram_nc.v
//
// ByteWide Write Enable, - NO_CHANGE mode template - Vivado recomended

module bytewrite_tdp_ram_nc
  #(
    //---------------------------------------------------------------
    parameter   NUM_COL                 =   4,
    parameter   COL_WIDTH               =   8,
    parameter   ADDR_WIDTH              =  10, // Addr  Width in bits : 2**ADDR_WIDTH = RAM Depth
    parameter   DATA_WIDTH              =  NUM_COL*COL_WIDTH  // Data  Width in bits
    //---------------------------------------------------------------
    ) (
       input clkA,
       input enaA, 
       input [NUM_COL-1:0] weA,
       input [ADDR_WIDTH-1:0] addrA,
       input [DATA_WIDTH-1:0] dinA,
       output reg [DATA_WIDTH-1:0] doutA,
       
       input clkB,
       input enaB,
       input [NUM_COL-1:0] weB,
       input [ADDR_WIDTH-1:0] addrB,
       input [DATA_WIDTH-1:0] dinB,
       output reg [DATA_WIDTH-1:0] doutB
       );

   
   // Core Memory  
   reg [DATA_WIDTH-1:0]            ram_block [(2**ADDR_WIDTH)-1:0];
   
   // Port-A Operation
   generate
      genvar                       i;
      for(i=0;i<NUM_COL;i=i+1) begin
         always @ (posedge clkA) begin
            if(enaA) begin
               if(weA[i]) begin
                  ram_block[addrA][i*COL_WIDTH +: COL_WIDTH] <= dinA[i*COL_WIDTH +: COL_WIDTH];
               end
            end
         end
      end
   endgenerate
   
   always @ (posedge clkA) begin
      if(enaA) begin
         if (~|weA)
           doutA <= ram_block[addrA];
      end
   end
   
   
   // Port-B Operation:
   generate
      for(i=0;i<NUM_COL;i=i+1) begin
         always @ (posedge clkB) begin
            if(enaB) begin
               if(weB[i]) begin
                  ram_block[addrB][i*COL_WIDTH +: COL_WIDTH] <= dinB[i*COL_WIDTH +: COL_WIDTH];
               end
            end
         end
      end
   endgenerate
   
   always @ (posedge clkB) begin
      if(enaB) begin
         if (~|weB)
           doutB <= ram_block[addrB];
      end
   end
   
endmodule // bytewrite_tdp_ram_nc


module tdp_ram_nc
  #(
    //---------------------------------------------------------------
    parameter   ADDR_WIDTH              =  10, // Addr  Width in bits : 2**ADDR_WIDTH = RAM Depth
    parameter   DATA_WIDTH              =  32  // Data  Width in bits
    //---------------------------------------------------------------
    ) (
       input clkA,
       input enA, 
       input weA,
       input [ADDR_WIDTH-1:0] addrA,
       input [DATA_WIDTH-1:0] dinA,
       output reg [DATA_WIDTH-1:0] doutA,
       
       input clkB,
       input enB,
       input weB,
       input [ADDR_WIDTH-1:0] addrB,
       input [DATA_WIDTH-1:0] dinB,
       output reg [DATA_WIDTH-1:0] doutB
       );

   
   // Core Memory  
   reg [DATA_WIDTH-1:0]            ram_block [(2**ADDR_WIDTH)-1:0];
   
    // Port-A Operation
    always @ (posedge clkA) begin
        if(enA) begin
            if(weA) begin
                ram_block[addrA] <= dinA;
             end
         end
   end
   
    always @ (posedge clkA) begin
        if(enA) begin
            if (~weA)
                doutA <= ram_block[addrA];
        end
    end
   
   
    // Port-B Operation:
    always @ (posedge clkB) begin
        if(enB) begin
            if(weB) begin
                ram_block[addrB] <= dinB;
            end
        end
    end
   
    always @ (posedge clkB) begin
        if(enB) begin
            if (~weB)
                doutB <= ram_block[addrB];
        end
    end
   
endmodule


// Single-Port Block RAM No-Change Mode
// File: rams_sp_nc.v

module rams_sp_nc
  #(
    //---------------------------------------------------------------
    parameter   ADDR_WIDTH              =  10, // Addr  Width in bits
    parameter   DATA_WIDTH              =  16  // Data  Width in bits
    //---------------------------------------------------------------
    ) (

    input                   clk,
    input                   we,
    input                   en,
    //input [1:0]             ul_en,  // upper lower wen
    input [ADDR_WIDTH-1:0]  addr, 
    input [DATA_WIDTH-1:0]  di,
    output [DATA_WIDTH-1:0] dout
    )
     ;
    
    
reg	[DATA_WIDTH-1:0] RAM [(2**ADDR_WIDTH)-1:0];
reg	[DATA_WIDTH-1:0] dout;

always @(posedge clk) begin
  if (en) begin
    if (we) begin
        RAM[addr] <= di;
        //if(ul_en[1])
        //    RAM[addr][15:8] <= di[15:8];
        //if(ul_en[0])
        //    RAM[addr][7:0] <= di[7:0];
    end
    else
      dout <= RAM[addr];
  end
end
endmodule
