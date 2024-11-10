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
|  14-27       | 7-20                | 0-13           | eFPGA IOs           |
|  28          | 21                  | 14             | VGA V-SYNC          |
|  29          | 22                  | 15             | VGA H-SYNC          |
|  30 + 30     | 23 + 24             | 16 + 17        | VGA Red (2 bit)     |
|  32 + 33     | 25 + 26             | 18 + 19        | VGA Green (2 bit)   |
|  34 + 35     | 27 + 28             | 20 + 21        | VGA Blue (2 bit)    |
|  36          | 29                  | 22             | NOVACORE UART RX    |
|  37          | 30                  | 23             | NOVACORE UART TX    |
