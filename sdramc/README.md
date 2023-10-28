# 概要

TnagNano20Kに内蔵されているSDRAMのコントローラです。  
3chのアービタを同梱しています。  
これにより最大で3つまでのマスターがSDRAMへアクセス可能です。

nand2marioさんが公開されているSDRAMコントローラ  
[https://github.com/nand2mario/sdram-tang-nano-20k](https://github.com/nand2mario/sdram-tang-nano-20k)  
をベースに  

- バースト転送対応
- トランザクション毎にバースト長の変更
- インターフェースをTangNano9KのPSRAMコントローラに似せた  
- 166MHz動作  

といった変更を行っています。

## rtl  
- src/sdramc.v  
  SDRAMコントローラ本体  

- src/sdram_arb.v  
  cmd ifアービタ―

## example
- tb/test_sdramc.v

本サンプルはアービタは利用していません。  


# SDRAMコントローラ　インターフェース仕様  


| pin name  | I/O | active | description
| ---       | --- | ---    | ---
|**system**||
| resetn    | I   | N      | reset
| clk       | I   | -      | main clock
| clk_sdram | I   | -      | main clock(*1)
| clk_capdq | I   | -      | DQ capture clock(*2)
|**commnad i/f**||
|cmd_en     | I   | P      | request for transaction
|cmd        | I   | -      | 0: Read, 1:Write
|addr[22:0] | I   | -      | address in byte
|cmd_len[3:0] | I | -      | burst length
|cmd_ack    | O   | P      | accept for transaction
|rd_data[31:0] | O| -      | read data
|rd_data_valid | O| -      | read data valid
|wr_data[31:0] | I| -      | write data
|wr_mask[3:0]  | I| -      | write data mask

\*1 : clk端子に入力するクロックと同一のものを入力してください。  
\*2 : 166MHz動作(近辺)においてはclk端子に入力するクロックと同一のものを入力してください。周波数を遅くした場合にはclkより位相をずらしたものをPLLで生成してDQを正しく取り込めるタイミングを調整する必要があります。  

## command i/f タイミング図
![read timing](images/timing_cmdif_read.PNG "read timing")  

![write timing](images/timing_cmdif_write.PNG "write timing")  

