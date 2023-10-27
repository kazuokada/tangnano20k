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


## SDRAMコントローラ　インターフェース仕様

|pin name|I/O|active|description|
|clk|I|-|main clock|
|clk_sdram|I|-|main clock|
|clk_capdq|I|-|main clock|


| No  | 都道府県 | 人 口      | 市町村数 |
| :---: | -------- | ---------: | -------: | 
| 1   | 東京都   | 13,942,856 | 39       | 
| 2   | 神奈川県 | 9,200,166  | 33       | 
| 3   | 大阪府   | 8,823,453  | 43       | 
| 4   | 愛知県   | 7,552,873  | 54       | 
| 5   | 埼玉県   | 7,337,330  | 63       | 