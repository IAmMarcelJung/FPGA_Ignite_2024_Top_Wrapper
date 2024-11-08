
module top_wrapper_test #(
    parameter NUM_OF_TOTAL_FABRIC_IOS = 32,  //TODO: TBD
    parameter NUM_OF_LOGIC_ANALYZER_BITS = 128,
    parameter WB_DATA_WIDTH = 32
) (
    // Wishbone Slave ports (WB MI A)
    input wb_clk_i,
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

    localparam include_eFPGA = 1;
    localparam NumberOfRows = 12;
    localparam NumberOfCols = 10;
    localparam FrameBitsPerRow = 32;
    localparam MaxFramesPerCol = 20;
    localparam desync_flag = 20;
    localparam FrameSelectWidth = 5;
    localparam RowSelectWidth = 5;

    // The number of IOs that can be used the FPGA user design
    localparam NUM_FABRIC_USER_IOS = 16;
    localparam [31:0] BASE_WB_ADDRESS = 32'h3000_0000;
    localparam [31:0] CONFIG_DATA_WB_ADDRESS = BASE_WB_ADDRESS;
    localparam [31:0] TO_FABRIC_IOS_WB_ADDRESS = BASE_WB_ADDRESS + 4;

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
    wire Rx;
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

    // TODO: think about if the parameters have to be set
    // TODO: TRIPLE (!!!) check everything here!!!
    eFPGA_top eFPGA_top_i (
        .A_config_C(),  // NOTE: Dirk said to leave this empty since its not needed
        .B_config_C(),  // NOTE: Dirk said to leave this empty since its not needed
        .Config_accessC(),  // NOTE: Dirk said to leave this empty since its not needed
        .I_top(I_top),
        .O_top(O_top),
        .T_top(T_top),
        .UIO_BOT_UIN(),  //TODO: TBD
        .UIO_BOT_UOUT(),  //TODO: TBD
        .UIO_TOP_UIN(),  //TODO: TBD
        .UIO_TOP_UOUT(),  //TODO TBD
        .CLK(CLK),
        .resten(resetn),  //TODO: resetn still has to be connected to a pin, probably one of io0-2?
        .SelfWriteStrobe(SelfWriteStrobe),
        .SelfWriteData(SelfWriteData),
        .Rx(Rx),
        .ComActive(ComActive),
        .ReceiveLED(ReceiveLED),
        .s_clk(s_clk),
        .s_data(s_data)
    );


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

    // TODO: probably use io0 -> io1 for different stuff

    // TODO: think about if this is the best pin, but it should be fine
    // An alternative could be to use io_in[0] since 1 and 2 are quite close
    // together on the board
    assign resetn = io_in[2];


    // NOTE: this was just taken from the previous shuttles
    assign s_clk = io_in[3];
    assign s_data = io_in[4];
    assign Rx = io_in[5];
    assign io_out[6] = ReceiveLED;

    //TODO: double check, but should be fine
    assign io_oeb[6:2] = 5'b01111;

    assign SelfWriteStrobe = config_strobe;
    assign SelfWriteData = config_data;

    assign CLK = wb_clk_i;

    // TODO: rethink about these and connect more to the logic analyzers
    assign la_data_out[6:0] = {
        A_config_C[39], A_config_C[31], A_config_C[16], FAB2RAM_C[45], ReceiveLED, Rx, ComActive
    };

    // TODO: set correct size
    // TODO: These have to be multiplexed with the user modules
    assign O_top[23:0] = io_in[30:7];
    assign io_out[30:7] = I_top;
    assign io_oeb[30:7] = T_top;
endmodule
