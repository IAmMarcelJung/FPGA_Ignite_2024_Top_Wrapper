# Summer School Pinout

| Caravel MPRJ | Top Wrapper Pin     | Fabulous Board |  Function           |
|--------------|---------------------|----------------|---------------------|
|  7           | 0                   | Middle Pin J8  | Reset (active low)  |
|  8           | 1                   | Middle Pin J11 | Select module       |
|  9           | 2                   | Middle Pin J13 | Sel (Find a better description) |
|  10          | 3                   |                | Bitbang serial clock|
|  11          | 4                   |                | Bitbang serial data |
|  12          | 5                   |                | eFPGA UART RX       |
|  13          | 6                   | LED D1         | RX LED              |
|  14-26       | 7-19                | 0-12           | eFPGA IOs           |
|  27          | 20                  | 13             | VGA V-SYNC          |
|  28          | 21                  | 14             | VGA H-SYNC          |
|  29 + 30     | 22 + 23             | 15 + 17        | VGA Blue (2 bit)     |
|  31 + 32     | 24 + 25             | 17 + 19        | VGA Green (2 bit)   |
|  33 + 34     | 26 + 27             | 19 + 21        | VGA Red (2 bit)    |
|  35          | 28                  | 21             | NOVACORE UART RX    |
|  36          | 29                  | 22             | NOVACORE UART TX    |
|  37          | 30                  | 23             | Clock select UART TX</br> 0: user_clock_2, 1: WB clock|


