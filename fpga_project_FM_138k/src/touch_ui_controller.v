// Small RV32I controller for GT911/GT9147 polling and menu actions.
// It changes control registers only. Audio synthesis and pixel rendering
// never wait for firmware, I2C, UART diagnostics or touch events.
module touch_ui_controller #(parameter integer VOICE_CAPACITY=32) (
    input wire clk, input wire reset_n,
    inout wire tp_scl, tp_sda, tp_int,
    output wire tp_rst,
    output wire sd_cs_n,sd_clk,sd_mosi,input wire sd_miso,
    output wire uart_tx,
    output wire [31:0] midi_event_data,
    output wire midi_event_valid,
    input wire midi_event_ready,
    input wire [31:0] monitor_event,
    input wire monitor_event_valid,
    input wire [6:0] preset_index,
    input wire [4:0] algorithm,input wire [7:0] active_voices,
    output wire touch_present,
    output wire signed [3:0] keyboard_octave,
    output wire [6:0] master_volume,
    output wire visual_mode,
    output wire spectrum_enable,
    output wire headphone_select,
    output wire [6:0] xy_delay_samples,
    output wire display_auto_gain,
    output reg command_valid,output reg [7:0] command,output reg [63:0] command_payload,input wire command_ready,
    output wire text_write,output wire [11:0] text_address,output wire [15:0] text_data,
    output wire palette_write,output wire [3:0] palette_index,output wire [23:0] palette_data,
    output wire [3:0] menu_page,output reg [23:0] background_color,wave_color,xy_color,output reg text_enable,output reg eg_we,output reg [7:0] eg_addr,output reg [8:0] eg_data,
    output reg algo_we,output reg [14:0] algo_addr,output reg [7:0] algo_data,output reg algo_enable,
    output reg eg2_we,output reg [9:0] eg2_addr,output reg [7:0] eg2_data,output reg eg2_enable,
    output wire fx_write,output wire [3:0] fx_index,output wire [31:0] fx_value,input wire [31:0] fx_read_value,
    output reg [31:0] numeric_display,
    output reg [159:0] arp_config,input wire [31:0] arp_status,input wire [127:0] arp_notes,
    output wire sequencer_active,
    output wire [31:0] lesson_state,
    output reg lesson_bank,output reg [7:0] lesson_count,
    output wire lesson_write,output wire [6:0] lesson_address,output wire [31:0] lesson_data,
    // 0x69 readback results from the synth (registers 14/15).
    input wire [15:0] patch_read_data,input wire patch_read_valid,
    input wire [31:0] perf_data,output reg [4:0] perf_index,
    output wire perf_snapshot,perf_clear
);
    reg [127:0] arp_timing_shadow;
    wire [31:0] address,write_data,read_data;
    wire [1:0] request;
    wire write_en=request==2'b01;
    wire read_en=request==2'b00;
    wire uart_select=address[31:8]==24'h200000;
    wire ui_select=address[31:8]==24'h230000;
    assign perf_snapshot=ui_select&&write_en&&address[7:2]==58&&write_data[0];
    assign perf_clear=ui_select&&write_en&&address[7:2]==58&&write_data[1];
    reg [31:0] fw_data;
    reg fw_valid;
    wire fw_ready=midi_event_ready;
    wire [31:0] lesson_midi,lesson_status;
    wire lesson_valid;
    wire [31:0] seq_midi,seq_status,seq_edit_data;
    wire [6:0] seq_edit_address;
    wire seq_valid;
    reg [127:0] seq_timing;
    reg [31:0] seq_control;
    reg [6:0] seq_read_address;
    // Editing/initializing RAM is not transport ownership.
    assign sequencer_active=seq_status[0]||seq_status[1]||seq_status[3]||seq_valid;
    assign midi_event_data=fw_valid?fw_data:lesson_valid?lesson_midi:seq_midi;
    assign midi_event_valid=fw_valid||lesson_valid||seq_valid;
    reg [15:0] lesson_end;
    reg [6:0] upload_address;
    reg [7:0] upload_count;
    reg uploading,upload_error;
    reg [16:0] upload_end;
    wire [16:0] entry_end={1'b0,write_data[31:16]}+{8'd0,write_data[15:7]};
    wire entry_ok=uploading&&!lesson_state[16]&&upload_count<128&&
        {1'b0,upload_address}==upload_count&&write_data[6:0]>=48&&write_data[6:0]<=72&&
        write_data[15:7]!=0&&{1'b0,write_data[31:16]}>=upload_end&&!entry_end[16];
    assign lesson_write=ui_select&&write_en&&address[7:2]==33&&entry_ok&&!upload_error;
    assign lesson_address=upload_address;
    assign lesson_data=write_data;
    lesson_player u_lesson(.clk(clk),.reset_n(reset_n),
        .control_write(ui_select&&write_en&&address[7:2]==28&&!uploading),.control_data(write_data),
        .score_bank(lesson_bank),.score_count(lesson_count),.score_end(lesson_end),
        .score_write(lesson_write),.score_address(lesson_address),.score_data(lesson_data),
        .human_event(monitor_event),.human_valid(monitor_event_valid),
        .midi_data(lesson_midi),.midi_valid(lesson_valid),.midi_ready(midi_event_ready&&!fw_valid),
        .status(lesson_status),.view_state(lesson_state));
    step_sequencer u_sequencer(.clk(clk),.reset_n(reset_n),.suspend(lesson_state[16]),
        .control_write(ui_select&&write_en&&address[7:2]==46),.control_data(write_data),.timing_data(seq_timing),
        .address_write(ui_select&&write_en&&address[7:2]==47),.address_data(write_data[6:0]),.read_address(seq_read_address),
        .step_write(ui_select&&write_en&&address[7:2]==48),.step_data(write_data),
        .clear_pattern(ui_select&&write_en&&address[7:2]==54&&write_data[0]),
        .edit_address(seq_edit_address),.edit_data(seq_edit_data),.human_event(monitor_event),.human_valid(monitor_event_valid),
        .midi_data(seq_midi),.midi_valid(seq_valid),.midi_ready(midi_event_ready&&!fw_valid&&!lesson_valid),.status(seq_status));
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
    wire [31:0] uart_data;
    reg [31:0] ui_data,ui_state;
    reg [15:0] readback_value;
    reg readback_ready;
    reg [9:0]  eg2_base;
    reg [31:0] eg2_word;
    reg [1:0]  eg2_byte;
    reg        eg2_burst;
    reg [14:0] algo_base;
    reg [31:0] algo_word;
    reg [1:0]  algo_byte;
    reg        algo_burst;
    reg [6:0] volume;
    assign touch_present=ui_state[0];
    assign keyboard_octave=ui_state[11:8];
    assign master_volume=volume;
    assign visual_mode=ui_state[12];
    assign spectrum_enable=ui_state[14];
    assign headphone_select=ui_state[13];
    assign xy_delay_samples=ui_state[22:16];
    // Bit 31 disables display gain. Zero-initialized/legacy firmware defaults
    // to useful quiet-signal visibility without depending on touch detection.
    assign display_auto_gain=!ui_state[31];
    assign menu_page=ui_state[27:24];
    assign text_write=ui_select&&write_en&&address[7:2]==6;
    // Cell word: {attr[3:0], palette[3:0], char[7:0]} in write_data[31:16];
    // address is the flat cell index {row[4:0], col[6:0]}.
    assign text_address=write_data[11:0];assign text_data=write_data[31:16];
    assign palette_write=ui_select&&write_en&&address[7:2]==16;
    assign palette_index=write_data[27:24];assign palette_data=write_data[23:0];
    wire fx_select=address[31:8]==24'h250000;
    assign fx_write=fx_select&&write_en;assign fx_index=address[5:2];assign fx_value=write_data;
    RV32I #(.FIRMWARE_FILE("src/ui_firmware/firmware.hex"),
        .FIRMWARE_HIGH_FILE("src/ui_firmware/firmware_high.hex"),.DATA_BYTES(98304)) u_cpu (
        .CLK(clk),.RST_X(reset_n),.w_mic_addr(address),.w_data(read_data),
        .w_mic_wdata(write_data),.w_mic_req(request),.w_mic_ctrl(),.w_stall(1'b0)
    );
    usb_debug_uart #(.BAUD_COUNT(434)) u_debug_uart (
        .clk_i(clk),.reset_n(reset_n),.m_select(uart_select),
        .m_addr(address[5:2]),.m_data_i(write_data),.m_data_o(uart_data),
        .m_read(read_en),.m_write(write_en),.uart_rx(1'b1),.uart_tx(uart_tx)
    );
    wire sd_select=address[31:8]==24'h260000;
    wire [31:0] sd_read_data;
    sd_spi_byte u_sd_spi(.clk(clk),.reset_n(reset_n),.select(sd_select),.write_en(write_en),
        .address(address[3:2]),.write_data(write_data),.read_data(sd_read_data),
        .cs_n(sd_cs_n),.sck(sd_clk),.mosi(sd_mosi),.miso(sd_miso));
    assign read_data=uart_select ? uart_data : sd_select?sd_read_data:fx_select?fx_read_value:ui_select ? ui_data : 32'd0;
    always @* begin
        case(address[7:2])
            0:ui_data={23'd0,reset_ready,6'd0,pins_sync};
            1:ui_data=microseconds;
            2:ui_data={31'd0,!fw_valid};
            3:ui_data=fw_data;
            // Preserve every legacy field. High voice-count bits occupy the
            // formerly reserved [26:24], separate from preset [23:22].
            4:ui_data={5'd0,active_voices[7:5],preset_index[6:5],active_voices[4:0],algorithm,preset_index[4:0],volume};
            59:ui_data=VOICE_CAPACITY;
            5:ui_data=ui_state;
            9:ui_data={31'd0,command_ready&&!command_valid};
            17:ui_data={31'd0,text_enable};
            14:ui_data={16'd0,readback_value};
            15:ui_data={31'd0,readback_ready};
            55:ui_data={25'd0,seq_read_address};
            56:ui_data={27'd0,perf_index};
            57:ui_data=perf_data;
            46:ui_data=seq_control;
            47:ui_data={25'd0,seq_edit_address};
            48:ui_data=seq_edit_data;
            49:ui_data=seq_status;
            50:ui_data=seq_timing[31:0];
            51:ui_data=seq_timing[63:32];
            52:ui_data=seq_timing[95:64];
            53:ui_data=seq_timing[127:96];
            36:ui_data=arp_config[31:0];
            37:ui_data=arp_timing_shadow[31:0];
            38:ui_data=arp_timing_shadow[63:32];
            39:ui_data=arp_timing_shadow[95:64];
            40:ui_data=arp_timing_shadow[127:96];
            41:ui_data=arp_status;
            42:ui_data=arp_notes[31:0];
            43:ui_data=arp_notes[63:32];
            44:ui_data=arp_notes[95:64];
            45:ui_data=arp_notes[127:96];
            28:ui_data=lesson_status;
            29:ui_data=lesson_state;
            30:ui_data={lesson_end,7'd0,lesson_bank,lesson_count};
            31:ui_data={22'd0,upload_count,upload_error,uploading};
            default:ui_data=0;
        endcase
    end
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n)begin
            perf_index<=0;
            seq_timing<={32'd87500,32'd87500,32'd125000,32'd125000};seq_control<=32'h3c0;seq_read_address<=0;
            arp_timing_shadow<={32'd175000,32'd175000,32'd250000,32'd250000};
            arp_config<={32'd175000,32'd175000,32'd250000,32'd250000,32'h00006000};
            lesson_bank<=0;lesson_count<=42;lesson_end<=1664;
            upload_address<=0;upload_count<=0;uploading<=0;upload_error<=0;upload_end<=0;
            i2c_drive<=0;fw_data<=0;fw_valid<=0;ui_state<=0;volume<=5;
            command_valid<=0;command<=0;command_payload<=0;text_enable<=1'b0;eg_we<=1'b0;eg_addr<=8'd0;eg_data<=9'd0;
            algo_we<=1'b0;algo_addr<=15'd0;algo_data<=8'd0;algo_enable<=1'b0;
    algo_base<=15'd0;algo_word<=32'd0;algo_byte<=2'd0;algo_burst<=1'b0;
        eg2_we<=1'b0;eg2_addr<=10'd0;eg2_data<=8'd0;eg2_enable<=1'b0;
        eg2_base<=10'd0;eg2_word<=32'd0;eg2_byte<=2'd0;eg2_burst<=1'b0;
            readback_value<=16'd0;readback_ready<=1'b0;
            background_color<=24'h080D18;wave_color<=24'h40EAD0;xy_color<=24'hFFB95A;numeric_display<=0;
        end else begin
            if(patch_read_valid)begin
                readback_value<=patch_read_data;readback_ready<=1'b1;
            end
            if(fw_valid&&fw_ready)fw_valid<=0;
            if(command_valid&&command_ready)command_valid<=0;
            if(monitor_event_valid && monitor_event[23:20]==4'hB && monitor_event[14:8]==20)
                volume<=monitor_event[6:0];
            eg_we<=1'b0;algo_we<=1'b0;
            if(eg2_burst)begin
                eg2_addr<=eg2_base+{8'd0,eg2_byte};
                eg2_data<=eg2_word[{eg2_byte,3'b000} +: 8];
                eg2_we<=1'b1;
                if(eg2_byte==2'd3)begin eg2_burst<=1'b0;eg2_base<=eg2_base+10'd4;end
                else eg2_byte<=eg2_byte+2'd1;
            end
            if(algo_burst)begin
                algo_addr<=algo_base+{13'd0,algo_byte};
                algo_data<=algo_word[{algo_byte,3'b000} +: 8];
                algo_we<=1'b1;
                if(algo_byte==2'd3)begin algo_burst<=1'b0;algo_base<=algo_base+15'd4;end
                else algo_byte<=algo_byte+2'd1;
            end
            if(ui_select&&write_en)begin
                case(address[7:2])
                    0:i2c_drive<=write_data[1:0];
                    3:if(!fw_valid||fw_ready)begin
                        fw_data<=write_data;fw_valid<=1;
                    end
                    5:ui_state<=write_data;
                    7:command_payload[31:0]<=write_data;
                    8:command_payload[63:32]<=write_data;
                    9:if(!command_valid||command_ready)begin command<=write_data[7:0];command_valid<=1;end
                    10:background_color<=write_data[23:0];
                    11:wave_color<=write_data[23:0];
                    12:xy_color<=write_data[23:0];
                    13:numeric_display<=write_data;
                    15:readback_ready<=1'b0;
                    17:text_enable<=write_data[0];
                    18:eg_addr<=write_data[7:0];
                    19:begin eg_data<=write_data[8:0];eg_we<=1'b1;end
                    20:algo_addr<=write_data[14:0];
                    21:begin algo_data<=write_data[7:0];algo_we<=1'b1;end
                    22:algo_enable<=write_data[0];
                    23:begin algo_base<=write_data[14:0];algo_burst<=1'b0;end
                    24:begin algo_word<=write_data;algo_byte<=2'd0;algo_burst<=1'b1;end
                25:begin eg2_base<=write_data[9:0];eg2_burst<=1'b0;end
                26:begin eg2_word<=write_data;eg2_byte<=2'd0;eg2_burst<=1'b1;end
                27:eg2_enable<=write_data[0];
                    55:seq_read_address<=write_data[6:0];
                    56:perf_index<=write_data[4:0];
                    46:seq_control<=write_data&32'h3ff;
                    50:seq_timing[31:0]<=write_data;
                    51:seq_timing[63:32]<=write_data;
                    52:seq_timing[95:64]<=write_data;
                    53:seq_timing[127:96]<=write_data;
                    36:arp_config<={arp_timing_shadow,write_data&32'h0001ffff};
                    37:arp_timing_shadow[31:0]<=write_data;
                    38:arp_timing_shadow[63:32]<=write_data;
                    39:arp_timing_shadow[95:64]<=write_data;
                    40:arp_timing_shadow[127:96]<=write_data;
                    31:if(!lesson_state[16]&&!lesson_status[5])begin
                        uploading<=write_data[0];upload_error<=0;upload_count<=0;upload_end<=0;
                        if(write_data[1])begin lesson_bank<=0;lesson_count<=42;lesson_end<=1664;end
                    end
                    32:upload_address<=write_data[6:0];
                    33:if(lesson_write)begin upload_count<=upload_count+1'b1;upload_end<=entry_end;end
                       else upload_error<=1;
                    34:if(uploading&&!upload_error&&!lesson_state[16]&&upload_count!=0&&
                        write_data[7:0]==upload_count&&{1'b0,write_data[31:16]}>=upload_end)begin
                        lesson_count<=upload_count;lesson_end<=write_data[31:16];lesson_bank<=1;uploading<=0;
                    end else upload_error<=1;
                    default:;
                endcase
            end
        end
    end
endmodule


