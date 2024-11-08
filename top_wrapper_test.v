
module top_wrapper_test (
    // Wishbone Slave ports (WB MI A)
    input wb_clk_i,
    input wbs_stb_i,
    input wbs_cyc_i,
    input wbs_we_i,
    input [31:0] wbs_dat_i,
    input [31:0] wbs_adr_i,
    output [31:0] wbs_dat_o,
    output reg wbs_ack_o,

    // Logic Analyzer Signals
    input  [127:0] la_data_in,
    output [127:0] la_data_out,
    input  [127:0] la_oenb,

    // IOs
    input  [31-1:0] io_in,
    output [31-1:0] io_out,
    output [31-1:0] io_oeb,

    // Independent clock (on independent integer divider)
    // TODO: check if to use this or wb_clk
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

    localparam NUM_FABRIC_USER_IOS = 16;
    localparam [31:0] BASE_WB_ADDRESS = 32'h3000_0000;
    localparam [31:0] CONFIG_DATA_WB_ADDRESS = BASE_WB_ADDRESS;
    localparam [31:0] TO_FABRIC_IOS_WB_ADDRESS = BASE_WB_ADDRESS + 4;

    // External USER ports
    //inout [16-1:0] PAD; // these are for Dirk and go to the pad ring
    wire [NUM_FABRIC_USER_IOS-1:0] I_top;
    wire [NUM_FABRIC_USER_IOS-1:0] T_top;
    wire [NUM_FABRIC_USER_IOS-1:0] O_top;
    wire [48-1:0] A_config_C;
    wire [48-1:0] B_config_C;

    wire CLK;  // This clock can go to the CPU (connects to the fabric LUT output flops

    // CPU configuration port
    wire SelfWriteStrobe;  // must decode address and write enable
    wire [32-1:0] SelfWriteData;  // configuration data write port

    // UART configuration port
    wire Rx;
    wire ComActive;
    wire ReceiveLED;

    // BitBang configuration port
    wire s_clk;
    wire s_data;

    //BlockRAM ports
    wire [192-1:0] RAM2FAB_D;
    wire [192-1:0] FAB2RAM_D;
    wire [96-1:0] FAB2RAM_A;
    wire [48-1:0] FAB2RAM_C;
    wire [48-1:0] Config_accessC;

    // Signal declarations
    wire [(NumberOfRows*FrameBitsPerRow)-1:0] FrameRegister;

    wire [(MaxFramesPerCol*NumberOfCols)-1:0] FrameSelect;

    wire [(FrameBitsPerRow*(NumberOfRows+2))-1:0] FrameData;

    wire [FrameBitsPerRow-1:0] FrameAddressRegister;
    wire LongFrameStrobe;
    wire [31:0] LocalWriteData;
    wire LocalWriteStrobe;
    wire [RowSelectWidth-1:0] RowSelect;

    wire external_clock;
    wire [1:0] clk_sel;

    wire config_strobe;
    wire fabric_strobe;
    reg [31:0] config_data;

    //latch for config_strobe
    reg latch_config_strobe = 0;
    reg config_strobe_reg1 = 0;
    reg config_strobe_reg2 = 0;
    reg config_strobe_reg3 = 0;
    wire latch_config_strobe_inverted1;
    wire latch_config_strobe_inverted2;

    // TODO: think about if the parameters have to be set
    eFPGA_top eFPGA_top_i ();


    always @(*) begin
        if (config_strobe_reg2) begin
            latch_config_strobe = 0;
        end else if (latch_config_strobe_inverted2) begin
            latch_config_strobe = 0;
        end else if(wbs_stb_i && wbs_cyc_i && wbs_we_i && !wbs_sta_o && (wbs_adr_i == CONFIG_DATA_WB_ADDRESS)) begin
            latch_config_strobe = 1;
        end
    end
    //assign latch_config_strobe_inverted1 = (!latch_config_strobe);            //This are the two inverters
    sky130_fd_sc_hd__inv latch_config_strobe_inv_0 (
        .Y(latch_config_strobe_inverted1),
        .A(latch_config_strobe)
    );
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


    //latch for fabric_strobe
    reg  latch_fabric_strobe = 0;
    reg  fabric_strobe_reg1 = 0;
    reg  fabric_strobe_reg2 = 0;
    reg  fabric_strobe_reg3 = 0;
    wire latch_fabric_strobe_inverted1;
    wire latch_fabric_strobe_inverted2;

    always @(*) begin
        if (fabric_strobe_reg2) begin
            latch_fabric_strobe = 0;
        end else if (latch_fabric_strobe_inverted2) begin
            latch_fabric_strobe = 0;
        end else if(wbs_stb_i && wbs_cyc_i && wbs_we_i && !wbs_sta_o && (wbs_adr_i == TO_FABRIC_IOS_WB_ADDRESS)) begin
            latch_fabric_strobe = 1;
        end
    end
    //assign latch_fabric_strobe_inverted1 = (!latch_fabric_strobe);            //This are the two inverters
    sky130_fd_sc_hd__inv latch_fabric_strobe_inv_0 (
        .Y(latch_fabric_strobe_inverted1),
        .A(latch_fabric_strobe)
    );
    //assign latch_fabric_strobe_inverted2 = (!latch_fabric_strobe_inverted1);
    sky130_fd_sc_hd__inv latch_fabric_strobe_inv_1 (
        .Y(latch_fabric_strobe_inverted2),
        .A(latch_fabric_strobe_inverted1)
    );
    always @(posedge CLK) begin
        fabric_strobe_reg1 <= latch_fabric_strobe;
        fabric_strobe_reg2 <= fabric_strobe_reg1;
        fabric_strobe_reg3 <= fabric_strobe_reg2;
    end

    //posedge pulse for config strobe
    assign fabric_strobe = (fabric_strobe_reg3 && (!fabric_strobe_reg2));

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



    //TODO: probably use io0 -> io2 for different stuff

    assign s_clk = io_in[3];
    assign s_data = io_in[4];
    assign Rx = io_in[5];
    assign io_out[6] = ReceiveLED;

    //TODO: double check, but should be fine
    assign io_oeb[6:3] = 4'b0111;

    assign SelfWriteStrobe = config_strobe;
    assign SelfWriteData = config_data;

    assign CLK = wb_clk_i;

    // TODO: rethink about these and connect more to the logic analyzers
    assign la_data_out[6:0] = {
        A_config_C[39], A_config_C[31], A_config_C[16], FAB2RAM_C[45], ReceiveLED, Rx, ComActive
    };

    // TODO: set correct size
    assign O_top[23:18] = io_in[30:25];
    assign io_out[30:7] = I_top;
    assign io_oeb[30:7] = T_top;
endmodule
