//reg [7:0] next_lru;    // wire
always@* begin   // Verilog 2001
    case({HIT_way,cur_lru})
        {4'b0001, 8'b11_10_01_00} : next_lru = 8'b00_11_10_01;
        {4'b0001, 8'b11_10_00_01} : next_lru = 8'b00_11_01_10;
        {4'b0001, 8'b11_01_10_00} : next_lru = 8'b00_10_11_01;
        {4'b0001, 8'b11_01_00_10} : next_lru = 8'b00_10_01_11;
        {4'b0001, 8'b11_00_10_01} : next_lru = 8'b00_01_11_10;
        {4'b0001, 8'b11_00_01_10} : next_lru = 8'b00_01_10_11;
        {4'b0001, 8'b10_11_01_00} : next_lru = 8'b00_11_10_01;
        {4'b0001, 8'b10_11_00_01} : next_lru = 8'b00_11_01_10;
        {4'b0001, 8'b01_11_10_00} : next_lru = 8'b00_11_10_01;
        {4'b0001, 8'b01_11_00_10} : next_lru = 8'b00_11_01_10;
        {4'b0001, 8'b00_11_10_01} : next_lru = 8'b00_11_10_01;
        {4'b0001, 8'b00_11_01_10} : next_lru = 8'b00_11_01_10;
        {4'b0001, 8'b10_01_11_00} : next_lru = 8'b00_10_11_01;
        {4'b0001, 8'b10_00_11_01} : next_lru = 8'b00_01_11_10;
        {4'b0001, 8'b01_10_11_00} : next_lru = 8'b00_10_11_01;
        {4'b0001, 8'b01_00_11_10} : next_lru = 8'b00_01_11_10;
        {4'b0001, 8'b00_10_11_01} : next_lru = 8'b00_10_11_01;
        {4'b0001, 8'b00_01_11_10} : next_lru = 8'b00_01_11_10;
        {4'b0001, 8'b10_01_00_11} : next_lru = 8'b00_10_01_11;
        {4'b0001, 8'b10_00_01_11} : next_lru = 8'b00_01_10_11;
        {4'b0001, 8'b01_10_00_11} : next_lru = 8'b00_10_01_11;
        {4'b0001, 8'b01_00_10_11} : next_lru = 8'b00_01_10_11;
        {4'b0001, 8'b00_10_01_11} : next_lru = 8'b00_10_01_11;
        {4'b0001, 8'b00_01_10_11} : next_lru = 8'b00_01_10_11;

        {4'b0010, 8'b11_10_01_00} : next_lru = 8'b11_00_10_01;
        {4'b0010, 8'b11_10_00_01} : next_lru = 8'b11_00_01_10;
        {4'b0010, 8'b11_01_10_00} : next_lru = 8'b11_00_10_01;
        {4'b0010, 8'b11_01_00_10} : next_lru = 8'b11_00_01_10;
        {4'b0010, 8'b11_00_10_01} : next_lru = 8'b11_00_10_01;
        {4'b0010, 8'b11_00_01_10} : next_lru = 8'b11_00_01_10;
        {4'b0010, 8'b10_11_01_00} : next_lru = 8'b11_00_10_01;
        {4'b0010, 8'b10_11_00_01} : next_lru = 8'b11_00_01_10;
        {4'b0010, 8'b01_11_10_00} : next_lru = 8'b10_00_11_01;
        {4'b0010, 8'b01_11_00_10} : next_lru = 8'b10_00_01_11;
        {4'b0010, 8'b00_11_10_01} : next_lru = 8'b01_00_11_10;
        {4'b0010, 8'b00_11_01_10} : next_lru = 8'b01_00_10_11;
        {4'b0010, 8'b10_01_11_00} : next_lru = 8'b10_00_11_01;
        {4'b0010, 8'b10_00_11_01} : next_lru = 8'b10_00_11_01;
        {4'b0010, 8'b01_10_11_00} : next_lru = 8'b10_00_11_01;
        {4'b0010, 8'b01_00_11_10} : next_lru = 8'b01_00_11_10;
        {4'b0010, 8'b00_10_11_01} : next_lru = 8'b01_00_11_10;
        {4'b0010, 8'b00_01_11_10} : next_lru = 8'b01_00_11_10;
        {4'b0010, 8'b10_01_00_11} : next_lru = 8'b10_00_01_11;
        {4'b0010, 8'b10_00_01_11} : next_lru = 8'b10_00_01_11;
        {4'b0010, 8'b01_10_00_11} : next_lru = 8'b10_00_01_11;
        {4'b0010, 8'b01_00_10_11} : next_lru = 8'b01_00_10_11;
        {4'b0010, 8'b00_10_01_11} : next_lru = 8'b01_00_10_11;
        {4'b0010, 8'b00_01_10_11} : next_lru = 8'b01_00_10_11;

        {4'b0100, 8'b11_10_01_00} : next_lru = 8'b11_10_00_01;
        {4'b0100, 8'b11_10_00_01} : next_lru = 8'b11_10_00_01;
        {4'b0100, 8'b11_01_10_00} : next_lru = 8'b11_10_00_01;
        {4'b0100, 8'b11_01_00_10} : next_lru = 8'b11_01_00_10;
        {4'b0100, 8'b11_00_10_01} : next_lru = 8'b11_01_00_10;
        {4'b0100, 8'b11_00_01_10} : next_lru = 8'b11_01_00_10;
        {4'b0100, 8'b10_11_01_00} : next_lru = 8'b10_11_00_01;
        {4'b0100, 8'b10_11_00_01} : next_lru = 8'b10_11_00_01;
        {4'b0100, 8'b01_11_10_00} : next_lru = 8'b10_11_00_01;
        {4'b0100, 8'b01_11_00_10} : next_lru = 8'b01_11_00_10;
        {4'b0100, 8'b00_11_10_01} : next_lru = 8'b01_11_00_10;
        {4'b0100, 8'b00_11_01_10} : next_lru = 8'b01_11_00_10;
        {4'b0100, 8'b10_01_11_00} : next_lru = 8'b11_10_00_01;
        {4'b0100, 8'b10_00_11_01} : next_lru = 8'b11_01_00_10;
        {4'b0100, 8'b01_10_11_00} : next_lru = 8'b10_11_00_01;
        {4'b0100, 8'b01_00_11_10} : next_lru = 8'b10_01_00_11;
        {4'b0100, 8'b00_10_11_01} : next_lru = 8'b01_11_00_10;
        {4'b0100, 8'b00_01_11_10} : next_lru = 8'b01_10_00_11;
        {4'b0100, 8'b10_01_00_11} : next_lru = 8'b10_01_00_11;
        {4'b0100, 8'b10_00_01_11} : next_lru = 8'b10_01_00_11;
        {4'b0100, 8'b01_10_00_11} : next_lru = 8'b01_10_00_11;
        {4'b0100, 8'b01_00_10_11} : next_lru = 8'b10_01_00_11;
        {4'b0100, 8'b00_10_01_11} : next_lru = 8'b01_10_00_11;
        {4'b0100, 8'b00_01_10_11} : next_lru = 8'b01_10_00_11;

        {4'b1000, 8'b11_10_01_00} : next_lru = 8'b11_10_01_00;
        {4'b1000, 8'b11_10_00_01} : next_lru = 8'b11_10_01_00;
        {4'b1000, 8'b11_01_10_00} : next_lru = 8'b11_01_10_00;
        {4'b1000, 8'b11_01_00_10} : next_lru = 8'b11_10_01_00;
        {4'b1000, 8'b11_00_10_01} : next_lru = 8'b11_01_10_00;
        {4'b1000, 8'b11_00_01_10} : next_lru = 8'b11_01_10_00;
        {4'b1000, 8'b10_11_01_00} : next_lru = 8'b10_11_01_00;
        {4'b1000, 8'b10_11_00_01} : next_lru = 8'b10_11_01_00;
        {4'b1000, 8'b01_11_10_00} : next_lru = 8'b01_11_10_00;
        {4'b1000, 8'b01_11_00_10} : next_lru = 8'b10_11_01_00;
        {4'b1000, 8'b00_11_10_01} : next_lru = 8'b01_11_10_00;
        {4'b1000, 8'b00_11_01_10} : next_lru = 8'b01_11_10_00;
        {4'b1000, 8'b10_01_11_00} : next_lru = 8'b10_01_11_00;
        {4'b1000, 8'b10_00_11_01} : next_lru = 8'b10_01_11_00;
        {4'b1000, 8'b01_10_11_00} : next_lru = 8'b01_10_11_00;
        {4'b1000, 8'b01_00_11_10} : next_lru = 8'b10_01_11_00;
        {4'b1000, 8'b00_10_11_01} : next_lru = 8'b01_10_11_00;
        {4'b1000, 8'b00_01_11_10} : next_lru = 8'b01_10_11_00;
        {4'b1000, 8'b10_01_00_11} : next_lru = 8'b11_10_01_00;
        {4'b1000, 8'b10_00_01_11} : next_lru = 8'b11_01_10_00;
        {4'b1000, 8'b01_10_00_11} : next_lru = 8'b10_11_01_00;
        {4'b1000, 8'b01_00_10_11} : next_lru = 8'b10_01_11_00;
        {4'b1000, 8'b00_10_01_11} : next_lru = 8'b01_11_10_00;
        {4'b1000, 8'b00_01_10_11} : next_lru = 8'b01_10_11_00;

// MISSの場合、LRU=3が書き換え対象
        {4'b0000, 8'b11_10_01_00} : next_lru = 8'b00_11_10_01;
        {4'b0000, 8'b11_10_00_01} : next_lru = 8'b00_11_01_10;
        {4'b0000, 8'b11_01_10_00} : next_lru = 8'b00_10_11_01;
        {4'b0000, 8'b11_01_00_10} : next_lru = 8'b00_10_01_11;
        {4'b0000, 8'b11_00_10_01} : next_lru = 8'b00_01_11_10;
        {4'b0000, 8'b11_00_01_10} : next_lru = 8'b00_01_10_11;
        {4'b0000, 8'b10_11_01_00} : next_lru = 8'b11_00_10_01;
        {4'b0000, 8'b10_11_00_01} : next_lru = 8'b11_00_01_10;
        {4'b0000, 8'b01_11_10_00} : next_lru = 8'b10_00_11_01;
        {4'b0000, 8'b01_11_00_10} : next_lru = 8'b10_00_01_11;
        {4'b0000, 8'b00_11_10_01} : next_lru = 8'b01_00_11_10;
        {4'b0000, 8'b00_11_01_10} : next_lru = 8'b01_00_10_11;
        {4'b0000, 8'b10_01_11_00} : next_lru = 8'b11_10_00_01;
        {4'b0000, 8'b10_00_11_01} : next_lru = 8'b11_01_00_10;
        {4'b0000, 8'b01_10_11_00} : next_lru = 8'b10_11_00_01;
        {4'b0000, 8'b01_00_11_10} : next_lru = 8'b10_01_00_11;
        {4'b0000, 8'b00_10_11_01} : next_lru = 8'b01_11_00_10;
        {4'b0000, 8'b00_01_11_10} : next_lru = 8'b01_10_00_11;
        {4'b0000, 8'b10_01_00_11} : next_lru = 8'b11_10_01_00;
        {4'b0000, 8'b10_00_01_11} : next_lru = 8'b11_01_10_00;
        {4'b0000, 8'b01_10_00_11} : next_lru = 8'b10_11_01_00;
        {4'b0000, 8'b01_00_10_11} : next_lru = 8'b10_01_11_00;
        {4'b0000, 8'b00_10_01_11} : next_lru = 8'b01_11_10_00;
        {4'b0000, 8'b00_01_10_11} : next_lru = 8'b01_10_11_00;

        default : next_lru = 8'b00_00_00_00;
    endcase
end
