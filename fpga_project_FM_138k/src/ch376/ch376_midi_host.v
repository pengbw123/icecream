// ACG720 USB MIDI host via external CH376S. USB traffic is control/bulk only;
// audio remains in the existing FPGA FM engine. See docs/CH376_MIDI_HOST.md.
module ch376_midi_host #(
    parameter integer CLK_HZ=50000000,
    parameter integer SPI_HALF_PERIOD=20,
    parameter integer POWER_WAIT=CLK_HZ/10,
    parameter integer RESET_WAIT=CLK_HZ/20,
    parameter integer BUS_WAIT=CLK_HZ/50,
    parameter integer ATTACH_WAIT=CLK_HZ/10,
    parameter integer POLL_WAIT=CLK_HZ/1000,
    parameter integer CONTROL_TIMEOUT=CLK_HZ/2,
    parameter integer IRQ_TIMEOUT=CLK_HZ/20,
    parameter integer MAX_CONFIG_BYTES=4096
) (
    input wire clk,reset_n,
    output wire spi_cs_n,spi_sck,spi_mosi,
    input wire spi_miso,interrupt_n,
    output reg [31:0] midi_event_data,
    output reg midi_event_valid,
    input wire midi_event_ready,
    output reg module_present,configured,
    output reg [7:0] fault_code,
    output reg [15:0] vendor_id,product_id,ignored_words,nak_count
);
    localparam [7:0] BOOT=0,SOFT_RESET=1,AFTER_RESET=2,CHECK=3,CHECK_DONE=4,
        MODE5=5,MODE5_DONE=6,ATTACH=7,ATTACH_CHECK=8,RATE=9,RATE_CHECK=10,
        BUS_RESET=11,BUS_RESET_DONE=12,MODE6=13,MODE6_DONE=14,RETRY6=15,
        ADDRESS0=16,DRAIN6=17,DEVICE8=18,CHIP_ADDRESS=19,DEVICE18=20,
        CONFIG_HEADER=21,PARSE_RESULT=22,NEXT_CONFIG=23,START_POLL=24,
        BULK_TOKEN=25,BULK_IRQ=26,BULK_STATUS=27,BULK_READ=28,BULK_DATA=29,
        SEND=30,WAIT_COMMAND=31,DELAY=32,CONTROL_LAUNCH=33,CONTROL_WAIT=34,
        PANIC=35,UNSUPPORTED=36,UNSUPPORTED_CHECK=37,RETRY5=38,DRAIN5=39;
    localparam [3:0] DEV8=0,SET_ADDR=1,DEV18=2,CFG_HEAD=3,CFG_FULL=4,
        SET_CFG=5,SET_IF=6,CLEAR_HALT=7;
    reg [7:0] state,resume_state,after_delay,last_byte;
    reg [31:0] delay_count,irq_count;
    reg [7:0] host_command;
    reg [3:0] host_write_length;
    reg [71:0] host_write_data;
    reg [1:0] host_read_mode;
    reg [511:0] bulk_packet;
    reg [7:0] bulk_length,bulk_left;
    reg [1:0] panic_left,stall_retries;
    reg [3:0] transport_errors;
    reg in_toggle;
    reg [3:0] midi_endpoint;
    reg [6:0] midi_max_packet,ep0_size;
    reg [7:0] dev_bytes[0:17];
    reg [71:0] config_header;
    reg [7:0] config_index,config_count;
    reg [3:0] control_step;
    reg [63:0] control_setup;
    reg parser_start;
    reg [1:0] int_sync;
    integer i;
    always @(posedge clk or negedge reset_n)
        if(!reset_n) int_sync<=3;else int_sync<={int_sync[0],interrupt_n};

    wire ctrl_busy,ctrl_done,ctrl_success,ctrl_data_valid;
    wire [7:0] ctrl_error,ctrl_data_byte;
    wire [15:0] ctrl_data_address,ctrl_received;
    wire ctrl_command_valid,command_ready,command_done,response_overflow;
    wire [7:0] ctrl_command,response_length;
    wire [3:0] ctrl_write_length;
    wire [71:0] ctrl_write_data;
    wire [1:0] ctrl_read_mode;
    wire [511:0] response_data;
    wire controller_owns_bus=state==CONTROL_LAUNCH || state==CONTROL_WAIT;
    ch376_spi_command #(.CLK_HZ(CLK_HZ),.HALF_PERIOD(SPI_HALF_PERIOD)) u_spi (
        .clk(clk),.reset_n(reset_n),.request_valid(controller_owns_bus ? ctrl_command_valid : state==SEND),
        .request_ready(command_ready),.command(controller_owns_bus ? ctrl_command : host_command),
        .write_length(controller_owns_bus ? ctrl_write_length : host_write_length),
        .write_data(controller_owns_bus ? ctrl_write_data : host_write_data),
        .read_mode(controller_owns_bus ? ctrl_read_mode : host_read_mode),
        .done(command_done),.response_length(response_length),.response_data(response_data),
        .response_overflow(response_overflow),.spi_cs_n(spi_cs_n),.spi_sck(spi_sck),
        .spi_mosi(spi_mosi),.spi_miso(spi_miso)
    );
    ch376_control_transfer #(.CLK_HZ(CLK_HZ),.TIMEOUT_CYCLES(CONTROL_TIMEOUT),.RETRY_CYCLES(POLL_WAIT)) u_control (
        .clk(clk),.reset_n(reset_n),.start(state==CONTROL_LAUNCH && !ctrl_busy),
        .setup_packet(control_setup),.ep0_max_packet(ep0_size),.interrupt_n(int_sync[1]),
        .busy(ctrl_busy),.done(ctrl_done),.success(ctrl_success),.error_code(ctrl_error),
        .data_valid(ctrl_data_valid),.data_byte(ctrl_data_byte),.data_address(ctrl_data_address),.received_length(ctrl_received),
        .command_valid(ctrl_command_valid),.command_ready(command_ready && controller_owns_bus),
        .command(ctrl_command),.write_length(ctrl_write_length),.write_data(ctrl_write_data),.read_mode(ctrl_read_mode),
        .command_done(command_done),.response_length(response_length),.response_data(response_data),.response_overflow(response_overflow)
    );
    wire parser_done,parser_malformed,parser_found;
    wire [7:0] parser_config,parser_if,parser_alt;
    wire [3:0] parser_endpoint;
    wire [6:0] parser_mps;
    wire [15:0] parser_total;
    usb_midi_config_parser u_parser (
        .clk(clk),.reset_n(reset_n),.start(parser_start),
        .byte_valid(ctrl_data_valid && control_step==CFG_FULL),.byte_data(ctrl_data_byte),
        .finish(ctrl_done && control_step==CFG_FULL),.done(parser_done),.malformed(parser_malformed),.found(parser_found),
        .configuration_value(parser_config),.interface_number(parser_if),.alternate_setting(parser_alt),
        .endpoint_number(parser_endpoint),.endpoint_max_packet(parser_mps),.total_length(parser_total)
    );
    wire decoded_valid;
    wire [31:0] decoded_event;
    usb_midi_event_decode u_decode(.packet(bulk_packet[31:0]),.valid(decoded_valid),.event_data(decoded_event));
    function [63:0] setup_request;
        input [7:0] bm,req;
        input [15:0] value,index,n;
        begin setup_request={n,index,value,req,bm};end
    endfunction
    task issue;
        input [7:0] op;
        input [3:0] n;
        input [71:0] bytes;
        input [1:0] mode;
        input [7:0] resume;
        begin host_command<=op;host_write_length<=n;host_write_data<=bytes;
            host_read_mode<=mode;resume_state<=resume;state<=SEND;end
    endtask
    task wait_cycles;
        input [31:0] cycles;
        input [7:0] resume;
        begin delay_count<=cycles-1;after_delay<=resume;state<=DELAY;end
    endtask
    task control;
        input [3:0] step;
        input [63:0] request;
        begin control_step<=step;control_setup<=request;state<=CONTROL_LAUNCH;end
    endtask
    task recover;
        input [7:0] reason;
        begin fault_code<=reason;configured<=0;panic_left<=configured ? 2 : 0;state<=PANIC;end
    endtask
    wire [15:0] config_size=config_header[31:16];
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            state<=BOOT;resume_state<=BOOT;after_delay<=BOOT;last_byte<=0;
            delay_count<=0;irq_count<=0;host_command<=0;host_write_length<=0;
            host_write_data<=0;host_read_mode<=0;bulk_packet<=0;bulk_length<=0;bulk_left<=0;
            panic_left<=0;stall_retries<=0;transport_errors<=0;in_toggle<=0;midi_endpoint<=0;
            midi_max_packet<=64;ep0_size<=8;config_header<=0;config_index<=0;config_count<=0;
            control_step<=DEV8;control_setup<=0;parser_start<=0;
            midi_event_data<=0;midi_event_valid<=0;module_present<=0;configured<=0;
            fault_code<=0;vendor_id<=0;product_id<=0;ignored_words<=0;nak_count<=0;
            for(i=0;i<18;i=i+1) dev_bytes[i]<=0;
        end else begin
            parser_start<=0;
            if(midi_event_valid && midi_event_ready) midi_event_valid<=0;
            if(ctrl_data_valid) begin
                if((control_step==DEV8 || control_step==DEV18) && ctrl_data_address<18)
                    dev_bytes[ctrl_data_address[4:0]]<=ctrl_data_byte;
                if(control_step==CFG_HEAD && ctrl_data_address<9)
                    config_header[ctrl_data_address*8+:8]<=ctrl_data_byte;
            end
            case(state)
                BOOT: wait_cycles(POWER_WAIT,SOFT_RESET);
                SOFT_RESET: begin
                    configured<=0;ep0_size<=8;in_toggle<=0;stall_retries<=0;transport_errors<=0;
                    issue(8'h05,0,0,0,AFTER_RESET);
                end
                AFTER_RESET: wait_cycles(RESET_WAIT,CHECK);
                CHECK: issue(8'h06,1,72'h65,1,CHECK_DONE);
                CHECK_DONE: if(last_byte==8'h9a) begin module_present<=1;state<=MODE5;end
                    else begin module_present<=0;fault_code<=8'h81;wait_cycles(CLK_HZ,SOFT_RESET);end
                MODE5: issue(8'h15,1,72'h05,1,MODE5_DONE);
                MODE5_DONE: if(last_byte==8'h51) state<=RETRY5;else recover(8'h82);
                RETRY5: issue(8'h0b,2,72'h0325,0,DRAIN5);
                DRAIN5: issue(8'h22,0,0,1,ATTACH);
                ATTACH: issue(8'h16,0,0,1,ATTACH_CHECK);
                ATTACH_CHECK: if(last_byte==8'h15 || last_byte==8'h18) wait_cycles(ATTACH_WAIT,RATE);
                    else wait_cycles(POLL_WAIT*10,ATTACH);
                RATE: issue(8'h0a,1,72'h07,1,RATE_CHECK);
                RATE_CHECK: if(last_byte[4]) begin fault_code<=8'h90;state<=UNSUPPORTED;end
                    else state<=BUS_RESET;
                BUS_RESET: issue(8'h15,1,72'h07,1,BUS_RESET_DONE);
                BUS_RESET_DONE: if(last_byte==8'h51) wait_cycles(BUS_WAIT,MODE6);else recover(8'h83);
                MODE6: issue(8'h15,1,72'h06,1,MODE6_DONE);
                MODE6_DONE: if(last_byte==8'h51) wait_cycles(BUS_WAIT,RETRY6);else recover(8'h84);
                RETRY6: issue(8'h0b,2,72'h0325,0,ADDRESS0);
                ADDRESS0: issue(8'h13,1,0,0,DRAIN6);
                DRAIN6: issue(8'h22,0,0,1,DEVICE8);
                DEVICE8: control(DEV8,setup_request(8'h80,6,16'h0100,0,8));
                CHIP_ADDRESS: issue(8'h13,1,72'h01,0,DEVICE18);
                DEVICE18: control(DEV18,setup_request(8'h80,6,16'h0100,0,18));
                CONFIG_HEADER: control(CFG_HEAD,setup_request(8'h80,6,{8'h02,config_index},0,9));
                CONTROL_LAUNCH: if(!ctrl_busy) state<=CONTROL_WAIT;
                CONTROL_WAIT: if(ctrl_done) begin
                    if(!ctrl_success) recover(ctrl_error);
                    else case(control_step)
                        DEV8: if(ctrl_received!=8 || dev_bytes[0]!=18 || dev_bytes[1]!=1 ||
                            !(dev_bytes[7]==8 || dev_bytes[7]==16 || dev_bytes[7]==32 || dev_bytes[7]==64)) recover(8'h91);
                            else begin ep0_size<=dev_bytes[7][6:0];control(SET_ADDR,setup_request(0,5,1,0,0));end
                        SET_ADDR: wait_cycles(POLL_WAIT*2,CHIP_ADDRESS);
                        DEV18: if(ctrl_received!=18 || dev_bytes[0]!=18 || dev_bytes[1]!=1 || dev_bytes[17]==0) recover(8'h92);
                            else begin
                                vendor_id<={dev_bytes[9],dev_bytes[8]};product_id<={dev_bytes[11],dev_bytes[10]};
                                config_count<=dev_bytes[17];config_index<=0;state<=CONFIG_HEADER;
                            end
                        CFG_HEAD: if(ctrl_received!=9 || config_header[7:0]<9 || config_header[15:8]!=2 ||
                                     config_size<9 || {16'd0,config_size}>MAX_CONFIG_BYTES || config_header[47:40]==0)
                                state<=NEXT_CONFIG;
                            else begin
                                parser_start<=1;control(CFG_FULL,setup_request(8'h80,6,{8'h02,config_index},0,config_size));
                            end
                        CFG_FULL: state<=PARSE_RESULT;
                        SET_CFG: if(parser_alt!=0) control(SET_IF,setup_request(1,11,{8'd0,parser_alt},{8'd0,parser_if},0));
                            else begin configured<=1;fault_code<=0;in_toggle<=0;state<=START_POLL;end
                        SET_IF: begin configured<=1;fault_code<=0;in_toggle<=0;state<=START_POLL;end
                        CLEAR_HALT: begin in_toggle<=0;state<=START_POLL;end
                        default: recover(8'h93);
                    endcase
                end
                PARSE_RESULT: if(parser_done) begin
                    if(parser_malformed || !parser_found || parser_total!=config_size) state<=NEXT_CONFIG;
                    else begin
                        midi_endpoint<=parser_endpoint;midi_max_packet<=parser_mps;
                        control(SET_CFG,setup_request(0,9,{8'd0,parser_config},0,0));
                    end
                end
                NEXT_CONFIG: if(config_index+1<config_count && config_index<7) begin
                        config_index<=config_index+1'b1;state<=CONFIG_HEADER;
                    end else begin fault_code<=8'h94;state<=UNSUPPORTED;end
                START_POLL: if(!midi_event_valid || midi_event_ready) wait_cycles(POLL_WAIT,BULK_TOKEN);
                BULK_TOKEN: begin
                    irq_count<=0;issue(8'h4e,2,{56'd0,midi_endpoint,4'h9,(in_toggle ? 8'h80 : 8'h00)},0,BULK_IRQ);
                end
                BULK_IRQ: if(!int_sync[1]) issue(8'h22,0,0,1,BULK_STATUS);
                    else if(irq_count>=IRQ_TIMEOUT-1) recover(8'hc1);
                    else irq_count<=irq_count+1'b1;
                BULK_STATUS: if(last_byte==8'h14) begin
                        in_toggle<=!in_toggle;stall_retries<=0;transport_errors<=0;
                        issue(8'h27,0,0,2,BULK_READ);
                    end else if((last_byte & 8'h2f)==8'h2a) begin
                        if(nak_count!=16'hffff) nak_count<=nak_count+1'b1;state<=START_POLL;
                    end else if((last_byte & 8'h2f)==8'h2e && stall_retries<2) begin
                        stall_retries<=stall_retries+1'b1;
                        control(CLEAR_HALT,setup_request(2,1,0,{8'd0,4'h8,midi_endpoint},0));
                    end else if((last_byte==8'h23 || last_byte==8'h2b) && transport_errors<8) begin
                        transport_errors<=transport_errors+1'b1;state<=START_POLL;
                    end else recover(last_byte);
                BULK_READ: if(bulk_length>{1'b0,midi_max_packet} || bulk_length[1:0]!=0) recover(8'hc2);
                    else begin bulk_left<=bulk_length;state<=bulk_length==0 ? START_POLL : BULK_DATA;end
                BULK_DATA: if(!midi_event_valid || midi_event_ready) begin
                    if(decoded_valid) begin midi_event_data<=decoded_event;midi_event_valid<=1;end
                    else if(ignored_words!=16'hffff) ignored_words<=ignored_words+1'b1;
                    bulk_packet<=bulk_packet>>32;bulk_left<=bulk_left-4;
                    if(bulk_left<=4) state<=START_POLL;
                end
                SEND: if(command_ready) state<=WAIT_COMMAND;
                WAIT_COMMAND: if(command_done) begin
                    last_byte<=response_data[7:0];
                    if(host_read_mode==2) begin bulk_packet<=response_data;bulk_length<=response_length;end
                    if(response_overflow) recover(8'hc3);else state<=resume_state;
                end
                DELAY: if(delay_count!=0) delay_count<=delay_count-1'b1;else state<=after_delay;
                PANIC: if(!midi_event_valid || midi_event_ready) begin
                    if(panic_left!=0) begin
                        midi_event_data<=panic_left==2 ? 32'h00b04000 : 32'h00b07b00;
                        midi_event_valid<=1;panic_left<=panic_left-1'b1;
                    end else wait_cycles(RESET_WAIT,SOFT_RESET);
                end
                UNSUPPORTED: issue(8'h16,0,0,1,UNSUPPORTED_CHECK);
                UNSUPPORTED_CHECK: if(last_byte==8'h16) state<=SOFT_RESET;
                    else wait_cycles(POLL_WAIT*100,UNSUPPORTED);
                default: recover(8'hff);
            endcase
        end
    end
endmodule
