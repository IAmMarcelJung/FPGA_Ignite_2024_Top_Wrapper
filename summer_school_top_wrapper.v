
module summer_school_top_wrapper #(
    parameter NUM_OF_TOTAL_FABRIC_IOS = 30,  //TODO: TBD
    parameter NUM_OF_LOGIC_ANALYZER_BITS = 128,
    parameter WB_DATA_WIDTH = 32
) (
    // Wishbone Slave ports (WB MI A)
    input wb_clk_i,
    input wb_rst_i,
    input wbs_stb_i,
    input wbs_cyc_i,
    input wbs_we_i,
    input [WB_DATA_WIDTH-1:0] wbs_dat_i,
    input [WB_DATA_WIDTH-1:0] wbs_adr_i,
    output [WB_DATA_WIDTH-1:0] wbs_dat_o,
    output reg wbs_ack_o,

    // Logic Analyzer Signals
    input  [NUM_OF_LOGIC_ANALYZER_BITS-1:0] la_data_in,
    output [NUM_OF_LOGIC_ANALYZER_BITS-1:0] la_data_out,
    input  [NUM_OF_LOGIC_ANALYZER_BITS-1:0] la_oenb,

    // IOs
    input  [NUM_OF_TOTAL_FABRIC_IOS-1:0] io_in,
    output [NUM_OF_TOTAL_FABRIC_IOS-1:0] io_out,
    output [NUM_OF_TOTAL_FABRIC_IOS-1:0] io_oeb,

    // Independent clock (on independent integer divider)
    // NOTE: unused, we are using the wishbone clock
    input user_clock2
);



    // The number of IOs that can be used the FPGA user design
    localparam NUM_FABRIC_USER_IOS = 16;
    localparam [31:0] BASE_WB_ADDRESS = 32'h3000_0000;
    localparam [31:0] CONFIG_DATA_WB_ADDRESS = BASE_WB_ADDRESS;
    localparam [31:0] TO_FABRIC_IOS_WB_ADDRESS = BASE_WB_ADDRESS + 4;

    // Fabric IOs
    localparam RESETN_IO = 0;
    localparam SELECT_MODULE_IO = 1;
    localparam SEL_IO = 2;
    localparam S_CLK_IO = 3;
    localparam S_DATA_IO = 4;
    localparam EFPGA_UART_RX_IO = 5;
    localparam RECEIVE_LED_IO = 6;

    // eFPGA IOs
    localparam EFPGA_USED_NUM_IOS = 13;  // Due to pin count limitation, we don't use all eFPGA IOs
    localparam EFPGA_IO_LOWEST = 7;
    localparam EFPGA_IO_HIGHEST = EFPGA_IO_LOWEST + EFPGA_USED_NUM_IOS - 1;

    // VGA IOs
    localparam VGA_NUM_IOS = 8;
    localparam VGA_IO_LOWEST = EFPGA_IO_HIGHEST + 1;  // VGA is located after the eFPGA pins
    localparam VGA_IO_HIGHEST = VGA_IO_LOWEST + VGA_NUM_IOS - 1;

    // NOVACORE IOs
    localparam NOVACORE_UART_RX_IO = VGA_IO_HIGHEST + 1; // NOVACORE UART is located after the VGA pins
    localparam NOVACORE_UART_TX_IO = NOVACORE_UART_RX_IO + 1;



    wire [NUM_FABRIC_USER_IOS-1:0] I_top;
    wire [NUM_FABRIC_USER_IOS-1:0] T_top;
    wire [NUM_FABRIC_USER_IOS-1:0] O_top;

    wire CLK;  // This clock can go to the CPU (connects to the fabric LUT output flops)
    wire resetn;

    // CPU configuration port
    wire SelfWriteStrobe;  // must decode address and write enable
    wire [32-1:0] SelfWriteData;  // configuration data write port

    // Wishbone configuration signals
    wire config_strobe;
    wire fabric_strobe;
    reg [31:0] config_data;

    // UART configuration port
    wire efpga_uart_rx;
    wire ComActive;
    wire ReceiveLED;

    // BitBang configuration port
    wire s_clk;
    wire s_data;


    // Latch for config_strobe
    reg latch_config_strobe = 0;
    reg config_strobe_reg1 = 0;
    reg config_strobe_reg2 = 0;
    reg config_strobe_reg3 = 0;
    wire latch_config_strobe_inverted1;
    wire latch_config_strobe_inverted2;


    wire [17:0] UI0_TOP_UOUT_PAD;
    reg [39:0] UI0_TOP_UIN_PAD;
    wire [99:0] UI0_BOT_UOUT_PAD;
    reg [67:0] UI0_BOT_UIN_PAD;


    // TODO: think about if the parameters have to be set
    // TODO: TRIPLE (!!!) check everything here!!!
    flexbex_soc_top flexbex_eFPGA (
        .A_config_C(),  // NOTE: Dirk said to leave this empty since its not needed
        .B_config_C(),  // NOTE: Dirk said to leave this empty since its not needed
        .Config_accessC(),  // NOTE: Dirk said to leave this empty since its not needed

        .CLK(CLK),
        .resten(resetn),  //TODO: resetn still has to be connected to a pin, probably one of io0-2?
        .SelfWriteStrobe(SelfWriteStrobe),
        .SelfWriteData(SelfWriteData),
        .Rx(efpga_uart_rx),
        .ComActive(),  //Dirk said to not connect it
        .ReceiveLED(ReceiveLED),
        .s_clk(s_clk),
        .s_data(s_data),

        .I_top(I_top),
        .O_top(O_top),
        .T_top(T_top),

        .UI0_TOP_UOUT_PAD(UI0_TOP_UOUT_PAD),
        .UI0_TOP_UIN_PAD (UI0_TOP_UIN_PAD),
        .UI0_BOT_UOUT_PAD(UI0_BOT_UOUT_PAD),
        .UI0_BOT_UIN_PAD (UI0_BOT_UIN_PAD)

    );

    //posit co-processor (eFPGA and LA)
    // Define intermediate signals
    reg issue_valid;  // Signal for issue validity
    reg [31:0] issue_req_instr;  // Signal for issue request instruction (assuming 32-bit width)
    reg register_valid;  // Signal for register validity
    reg [31:0] register_rs[1:0];  // Signal for register sources (2 bits)
    reg [1:0] register_rs_valid;  // Signal for register sources validity
    reg result_ready;  // Signal for result readiness

    wire issue_ready;  // Signal for issue readiness
    wire issue_resp_accept;  // Signal for issue response accept
    wire issue_resp_writeback;  // Signal for issue response writeback
    wire [1:0] issue_resp_register_read;  // Signal for issue response register read (2 bits)
    wire register_ready;  // Signal for register readiness
    wire result_valid;  // Signal for result validity
    wire [31:0] result_data;  // Signal for result data (assuming 32-bit width)

    pau pau_inst (
        .clk(wb_clk_i),
        .rst(!resetn),
        .issue_valid(issue_valid),
        .issue_ready(issue_ready),
        .issue_req_instr(issue_req_instr),
        .issue_resp_accept(issue_resp_accept),
        .issue_resp_writeback(issue_resp_writeback),
        .issue_resp_register_read(issue_resp_register_read),
        .register_valid(register_valid),
        .register_ready(register_ready),
        .register_rs(register_rs),
        .register_rs_valid(register_rs_valid),
        .result_valid(result_valid),
        .result_ready(result_ready),
        .result_data(result_data)
    );

    // THE RING
    reg en;
    wire [7:0] d_out;
    ro_top ring_inst (
        .clk(wb_clk_i),
        .en(en),
        .d_out(d_out)
    );


    // VGA_Ignite
    reg sync;
    reg [2:0] mode;
    reg [7:0] data_i;
    reg stb_i;
    reg ack_o;

    wire [7:0] data_o;
    wire ack_i;
    wire [1:0] vga_r;
    wire [1:0] vga_g;
    wire [1:0] vga_b;

    wire hsync;
    wire vsync;

    ppu ppu_inst (
        .clk(wb_clk_i),
        .rst(!resetn),
        .sync(UI0_BOT_UOUT_PAD[0]),
        .mode(UI0_BOT_UOUT_PAD[2:1]),
        .data_i(UI0_BOT_UOUT_PAD[10:3]),
        .stb_i(UI0_BOT_UOUT_PAD[11]),
        .ack_i(UI0_BOT_UIN_PAD[0]),
        .data_o(data_o),
        .stb_o(), //indicates data of current pixel and is not currenly usedhttps://github.com/jhspuk/FPGAIgnite-VGA
        .ack_o(UI0_BOT_UOUT_PAD[12])
    );

    // Instantiate VGA Driver module
    assign io_oeb[VGA_IO_HIGHEST:VGA_IO_LOWEST] = 8'b00000000;
    assign io_out[VGA_IO_HIGHEST:VGA_IO_LOWEST] = {vga_r, vga_g, vga_b, hsync, vsync};

    vga_driver vga_driver_inst (
        .clk_pix(wb_clk_i),
        .rst_pix(!resetn),
        .wb_data(data_o),    // PPU's data output is written to VGA
        .vga_r  (vga_r),
        .vga_g  (vga_g),
        .vga_b  (vga_b),
        .sx     (),          //simulation signals
        .sy     (),          //simulation signals
        .hsync  (hsync),
        .vsync  (vsync),
        .de     ()           //simulation signals
    );

    //NOVACORE

    assign io_oeb[NOVACORE_UART_TX_IO] = 1'b0;
    assign io_oeb[NOVACORE_UART_RX_IO] = 1'b1;
    toplevel nova_core (
        .system_clk(wb_clk_i),
        .system_clk_locked(),
        .reset_n(resetn),
        .uart0_txd(io_out[NOVACORE_UART_TX_IO]),
        .uart_rxd(io_in[NOVACORE_UART_RX_IO])
    );



    wire select_module, sel;



    // Module Select
    always @(*) begin
        case (select_module)


            // THE RING
            1'b0: begin
                case (sel)

                    // Logic Analyzer
                    1: begin
                        if (la_oenb[7:0]) la_data_in[7:0] <= d_out;
                        else en <= la_data_out[8];
                    end

                    default: //eFPGA
                 begin
                        //inputs
                        en <= UIO_BOT_UOUT_PAD[13];
                        //outputs
                        UIO_BOT_UIN_PAD[8:1] <= d_out;
                    end
                endcase
            end


            default: //posit coprocessor
                begin
                case (sel)

                    // LA
                    1: begin
                        //inputs
                        if (la_oenb[101:1])
                            {issue_valid,issue_req_instr,register_valid,register_rs[1],register_rs[0],register_rs_valid,result_ready} <= la_data_in[101:1]; // !!! Double check this
                        else
                            la_data_out[39:1] <= {
                                issue_ready,
                                issue_resp_accept,
                                issue_resp_writeback,
                                issue_resp_register_read,
                                register_ready,
                                result_valid,
                                result_data
                            };
                    end

                    default: // eFPGA
            begin
                        // inputs
                        {issue_req_instr[31:18],issue_valid,issue_req_instr,register_valid,register_rs[1],register_rs[0],register_rs_valid,result_ready} <= UIO_BOT_UOUT_PAD[95:13];
                        issue_req_instr[17:0] <= UIO_TOP_UOUT_PAD[17:0];

                        //outputs
                        UIO_BOT_UIN_PAD[39:1] <= {
                            issue_ready,
                            issue_resp_accept,
                            issue_resp_writeback,
                            issue_resp_register_read,
                            register_ready,
                            result_valid,
                            result_data
                        };
                    end
                endcase
            end
        endcase
    end



    always @(*) begin
        if (config_strobe_reg2) begin
            latch_config_strobe = 0;
        end else if (latch_config_strobe_inverted2) begin
            latch_config_strobe = 0;
        end else if(wbs_stb_i && wbs_cyc_i && wbs_we_i && !wbs_sta_o && (wbs_adr_i == CONFIG_DATA_WB_ADDRESS)) begin
            latch_config_strobe = 1;
        end
    end

    //These are the two inverters
    //NOTE: keep the comment for reference
    //assign latch_config_strobe_inverted1 = (!latch_config_strobe);
    sky130_fd_sc_hd__inv latch_config_strobe_inv_0 (
        .Y(latch_config_strobe_inverted1),
        .A(latch_config_strobe)
    );

    //NOTE: keep the comment for reference
    //assign latch_config_strobe_inverted2 = (!latch_config_strobe_inverted1);
    sky130_fd_sc_hd__inv latch_config_strobe_inv_1 (
        .Y(latch_config_strobe_inverted2),
        .A(latch_config_strobe_inverted1)
    );
    always @(posedge CLK) begin
        config_strobe_reg1 <= latch_config_strobe;
        config_strobe_reg2 <= config_strobe_reg1;
        config_strobe_reg3 <= config_strobe_reg2;
    end
    assign config_strobe = (config_strobe_reg3 && (!config_strobe_reg2)); //posedge pulse for config strobe

    //config data register
    always @(posedge wb_clk_i) begin
        if (wbs_stb_i && wbs_cyc_i && wbs_we_i && !wbs_sta_o && (wbs_adr_i == CONFIG_DATA_WB_ADDRESS)) begin
            config_data = wbs_dat_i;
        end
    end

    // acks
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) wbs_ack_o <= 0;
        else
            // return ack immediately
            wbs_ack_o <= (wbs_stb_i && !wbs_sta_o && (wbs_adr_i == CONFIG_DATA_WB_ADDRESS));
    end


    // TODO: this needs to be checked thoroughly

    assign resetn = io_in[RESETN_IO];
    assign select_module = io_in[SELECT_MODULE_IO];
    assign sel = io_in[SEL_IO];
    assign s_clk = io_in[S_CLK_IO];
    assign s_data = io_in[S_DATA_IO];
    assign efpga_uart_rx = io_in[EFPGA_UART_RX_IO];
    assign io_out[RECEIVE_LED_IO] = ReceiveLED;

    //TODO: double check, but should be fine
    assign io_oeb[RESETN_IO] = 1'b1;
    assign io_oeb[SELECT_MODULE_IO] = 1'b1;
    assign io_oeb[SEL_IO] = 1'b1;
    assign io_oeb[S_CLK_IO] = 1'b1;
    assign io_oeb[S_DATA_IO] = 1'b1;
    assign io_oeb[EFPGA_UART_RX_IO] = 1'b1;
    assign io_oeb[RECEIVE_LED_IO] = 1'b0;  // The only output of the fabric IOs

    assign SelfWriteStrobe = config_strobe;
    assign SelfWriteData = config_data;

    assign CLK = wb_clk_i;

    assign la_data_out[103:102] = {ReceiveLED, efpga_uart_rx};

    assign O_top[EFPGA_USED_NUM_IOS-1:0] = io_in[EFPGA_IO_HIGHEST:EFPGA_IO_LOWEST];
    assign io_out[EFPGA_IO_HIGHEST:EFPGA_IO_LOWEST] = I_top[EFPGA_USED_NUM_IOS-1:0];
    assign io_oeb[EFPGA_IO_HIGHEST:EFPGA_IO_LOWEST] = T_top[EFPGA_USED_NUM_IOS-1:0];
endmodule
