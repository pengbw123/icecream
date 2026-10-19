// Small RV32I controller for GT911/GT9147 polling and menu actions.
// It changes control registers only. Audio synthesis and pixel rendering
// never wait for firmware, I2C, UART diagnostics or touch events.
module touch_ui_controller (
    input wire clk, input wire reset_n,
    inout wire tp_scl, tp_sda, tp_int,
    output wire tp_rst,
    output wire uart_tx,
    output reg [31:0] midi_event_data,
    output reg midi_event_valid,
    input wire midi_event_ready,
    input wire [31:0] monitor_event,
    input wire monitor_event_valid,
    input wire [4:0] preset_index, algorithm, active_voices,
    output wire touch_present,
    output wire signed [3:0] keyboard_octave,
    output wire [6:0] master_volume,
    output wire visual_mode,
    output wire [6:0] xy_delay_samples
);
    wire reset_ready,int_o,int_t;
    gt9147_reset u_gt_reset(.clk(clk),.reset_n(reset_n),.tp_int_o(int_o),
        .tp_int_t(int_t),.tp_rst(tp_rst),.ready(reset_ready));
    assign tp_int=int_t ? 1'bz : int_o;
    reg [1:0] i2c_drive;
    assign tp_sda=i2c_drive[0] ? 1'b0 : 1'bz;
    assign tp_scl=i2c_drive[1] ? 1'b0 : 1'bz;
    reg [1:0] pins_meta,pins_sync;
    always @(posedge clk) begin
        pins_meta<={tp_scl,tp_sda};pins_sync<=pins_meta;
    end
    reg [5:0] us_div;
    reg [31:0] microseconds;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n)begin us_div<=0;microseconds<=0;end
        else if(us_div==49)begin us_div<=0;microseconds<=microseconds+1'b1;end
        else us_div<=us_div+1'b1;
    end
    wire [31:0] address,write_data,read_data;
    wire [1:0] request;
    wire write_en=request==2'b01;
    wire read_en=request==2'b00;
    wire uart_select=address[31:8]==24'h200000;
    wire ui_select=address[31:8]==24'h230000;
    wire [31:0] uart_data;
    reg [31:0] ui_data,ui_state;
    reg [6:0] volume;
    assign touch_present=ui_state[0];
    assign keyboard_octave=ui_state[11:8];
    assign master_volume=volume;
    assign visual_mode=ui_state[12];
    assign xy_delay_samples=ui_state[22:16];
    RV32I #(.FIRMWARE_FILE("src/ui_firmware/firmware.hex")) u_cpu (
        .CLK(clk),.RST_X(reset_n),.w_mic_addr(address),.w_data(read_data),
        .w_mic_wdata(write_data),.w_mic_req(request),.w_mic_ctrl(),.w_stall(1'b0)
    );
    usb_debug_uart #(.BAUD_COUNT(434)) u_debug_uart (
        .clk_i(clk),.reset_n(reset_n),.m_select(uart_select),
        .m_addr(address[5:2]),.m_data_i(write_data),.m_data_o(uart_data),
        .m_read(read_en),.m_write(write_en),.uart_rx(1'b1),.uart_tx(uart_tx)
    );
    assign read_data=uart_select ? uart_data : ui_select ? ui_data : 32'd0;
    always @* begin
        case(address[5:2])
            0:ui_data={23'd0,reset_ready,6'd0,pins_sync};
            1:ui_data=microseconds;
            2:ui_data={31'd0,!midi_event_valid};
            3:ui_data=midi_event_data;
            4:ui_data={10'd0,active_voices,algorithm,preset_index,volume};
            5:ui_data=ui_state;
            default:ui_data=0;
        endcase
    end
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n)begin
            i2c_drive<=0;midi_event_data<=0;midi_event_valid<=0;ui_state<=0;volume<=96;
        end else begin
            if(midi_event_valid&&midi_event_ready)midi_event_valid<=0;
            if(monitor_event_valid && monitor_event[23:20]==4'hB && monitor_event[14:8]==20)
                volume<=monitor_event[6:0];
            if(ui_select&&write_en)begin
                case(address[5:2])
                    0:i2c_drive<=write_data[1:0];
                    3:if(!midi_event_valid||midi_event_ready)begin
                        midi_event_data<=write_data;midi_event_valid<=1;
                    end
                    5:ui_state<=write_data;
                    default:;
                endcase
            end
        end
    end
endmodule
