`timescale 1ns/1ps
// Behavioral external CH376 + USB MIDI device. Checks the actual SPI pins,
// USB setup/status stages, endpoint addresses and DATA0/DATA1 sequencing.
module ch376_usb_model (
    input wire cs_n,sck,mosi,
    output reg miso=1,
    input wire attached,
    output reg interrupt_n=1
);
    byte unsigned config_desc[$],device_desc[$],usb_words_bytes[$];
    byte unsigned host_data[$],read_packet[$],descriptor_tail[$];
    byte unsigned cmd=0,spi_in=0,spi_out=0,flags=0,status=0;
    int bit_count=0,byte_count=0,write_goal=0;
    int mode=0,chip_address=0,usb_address=0,configuration=0,alternate=0;
    int request_type=0,request_code=0,request_value=0,request_index=0,request_length=0,cursor=0;
    bit control_active=0,ep0_toggle=1,bulk_toggle=0;
    bit control_nak_used=0;
    bit stall_request=0,suppress_irq=0,low_speed=0;
    int nak_budget=2,reset_count=0,enumerations=0,clear_count=0,full_descriptor_reads=0;
    int retries=8'h8f;
    int forced_read_length=-1;
    time command_time,cs_rise=0,last_edge=0;
    // CH376 shifts SDO on falling edges; allow 25 ns output propagation.
    always @(negedge sck or negedge cs_n or posedge cs_n)
        if(cs_n)miso<=1;else miso<=#25 spi_out[7-bit_count];
    initial begin
        device_desc={18,1,8'h10,1,0,0,0,8,8'h34,8'h12,8'h78,8'h56,0,1,0,0,0,1};
        config_desc={9,2,0,0,3,5,0,8'h80,50,
            9,4,0,0,1,3,1,1,0,7,5,8'h81,3,8,0,10,
            9,4,1,0,0,1,1,0,0};
        config_desc.push_back(30);config_desc.push_back(8'hff);repeat(28)config_desc.push_back(0);
        descriptor_tail={9,4,2,0,0,1,3,0,0,
            9,4,2,1,1,1,3,0,0,
            7,8'h24,1,0,1,22,0,
            6,8'h24,2,1,1,0,
            9,8'h24,3,1,2,1,1,1,0,
            9,5,8'h83,2,64,0,0,0,0,
            5,8'h25,1,1,2};
        foreach(descriptor_tail[j])config_desc.push_back(descriptor_tail[j]);
        config_desc[2]=byte'(config_desc.size());config_desc[3]=byte'(config_desc.size()>>8);
    end
    task queue_event(input logic[31:0] word);
        for(int j=0;j<4;j++)usb_words_bytes.push_back(word[j*8+:8]);
    endtask
    task interrupt_status(input byte unsigned value);
        status=value;if(!suppress_irq)interrupt_n=0;
    endtask
    always @(negedge attached) begin
        configuration=0;alternate=0;control_active=0;usb_words_bytes.delete();interrupt_status(8'h16);
    end
    task usb_token(input byte unsigned token);
        int endpoint,pid,n;
        byte unsigned ignored;
        begin : token_body
        endpoint=token>>4;pid=token & 15;
        assert(mode==6 && retries[7]==0) else $fatal(1,"host mode/SOF or NAK retry not configured mode=%0d retries=%02x token=%02x",mode,retries,token);
        if(!attached) begin interrupt_status(8'h16);disable token_body;end
        assert(chip_address==usb_address) else $fatal(1,"USB address not updated after status stage");
        if(endpoint==0 && pid==13) begin
            assert(flags==0 && host_data.size()==8) else $fatal(1,"SETUP must be DATA0/eight bytes");
            request_type=host_data[0];request_code=host_data[1];
            request_value=host_data[2]|(int'(host_data[3])<<8);
            request_index=host_data[4]|(int'(host_data[5])<<8);
            request_length=host_data[6]|(int'(host_data[7])<<8);
            cursor=0;control_active=1;ep0_toggle=1;
            if(request_code==6 && request_value==16'h0200 && request_length>64)full_descriptor_reads++;
            interrupt_status(8'h14);
        end else if(endpoint==0 && pid==9) begin
            assert(control_active && flags==(ep0_toggle ? 8'h80 : 0)) else $fatal(1,"EP0 IN PID wrong");
            read_packet.delete();
            if(request_type[7]) begin
                if(request_value==16'h0200 && request_length>64 && cursor==64 && !control_nak_used) begin
                    control_nak_used=1;interrupt_status(8'h2a);disable token_body;
                end
                n=request_length-cursor;if(n>int'(device_desc[7]))n=int'(device_desc[7]);
                for(int j=0;j<n;j++)begin
                    if(request_value==16'h0100)read_packet.push_back(device_desc[cursor+j]);
                    else if(request_value==16'h0200)read_packet.push_back(config_desc[cursor+j]);
                    else $fatal(1,"unexpected descriptor request");
                end
                cursor+=n;ep0_toggle=!ep0_toggle;
            end else begin
                assert(request_length==0 && flags==8'h80) else $fatal(1,"bad IN status stage");
                case(request_code)
                    5: begin assert(request_value==1);usb_address=1;end
                    9: begin assert(request_value==5);configuration=5;bulk_toggle=0;enumerations++;end
                    11:begin assert(request_value==1 && request_index==2);alternate=1;end
                    1: begin assert(request_type==2 && request_index==8'h83);bulk_toggle=0;clear_count++;end
                    default:$fatal(1,"unexpected no-data USB request %0d",request_code);
                endcase
                control_active=0;
            end
            interrupt_status(8'h14);
        end else if(endpoint==0 && pid==1) begin
            assert(control_active && request_type[7] && flags==8'h40 && host_data.size()==0 && cursor==request_length)
                else $fatal(1,"bad OUT status stage");
            control_active=0;interrupt_status(8'h14);
        end else if(endpoint==3 && pid==9) begin
            assert(configuration==5 && alternate==1 && flags==(bulk_toggle ? 8'h80 : 0))
                else $fatal(1,"bulk endpoint/alternate/DATA PID incorrect");
            read_packet.delete();
            if(stall_request)begin stall_request=0;interrupt_status(8'h2e);disable token_body;end
            if(nak_budget>0)begin nak_budget--;interrupt_status(8'h2a);disable token_body;end
            if(usb_words_bytes.size()==0)begin interrupt_status(8'h2a);disable token_body;end
            n=usb_words_bytes.size();if(n>64)n=64;
            repeat(n)begin ignored=usb_words_bytes.pop_front();read_packet.push_back(ignored);end
            bulk_toggle=!bulk_toggle;interrupt_status(8'h14);
        end else $fatal(1,"unexpected USB endpoint/PID %02x",token);
        end
    endtask
    task received_byte(input byte unsigned value);
        if(byte_count==0) begin
            cmd=value;command_time=$time;spi_out=0;
            case(cmd)
                8'h05:begin
                    reset_count++;mode=0;chip_address=0;usb_address=0;configuration=0;alternate=0;
                    control_active=0;bulk_toggle=0;interrupt_n=1;status=0;retries=8'h8f;
                end
                8'h16:spi_out=attached ? (usb_address==0 ? 8'h15 : 8'h18) : 8'h16;
                8'h22:begin spi_out=status;interrupt_n=1;end
                8'h27:begin
                    spi_out=forced_read_length>=0 ? byte'(forced_read_length) : byte'(read_packet.size());
                    forced_read_length=-1;
                end
                8'h06,8'h15,8'h0a,8'h0b,8'h13,8'h2c,8'h4e:;
                default:$fatal(1,"unimplemented/unexpected CH376 command %02x",cmd);
            endcase
        end else begin
            assert($time-command_time>=2000) else $fatal(1,"CH376 opcode busy time ignored");
            case(cmd)
                8'h06:if(byte_count==1)spi_out=~value;
                8'h15:if(byte_count==1)begin
                    mode=value;spi_out=8'h51;retries=8'h8f;
                    if(mode==7)begin usb_address=0;configuration=0;alternate=0;end
                    if(attached)interrupt_status(8'h15);
                end else assert($time-command_time>=30000) else $fatal(1,"USB mode return read too early");
                8'h0a:if(byte_count==1)begin assert(value==7);spi_out=low_speed ? 8'h10 : 0;end
                8'h0b:if(byte_count==1)begin assert(value==8'h25);end else if(byte_count==2)retries=value;
                8'h13:if(byte_count==1)chip_address=value;
                8'h2c:if(byte_count==1)begin write_goal=value;host_data.delete();end
                    else if(byte_count<write_goal+2)host_data.push_back(value);
                8'h4e:if(byte_count==1)flags=value;else if(byte_count==2)usb_token(value);
                8'h27:if(byte_count<=read_packet.size())spi_out=read_packet[byte_count-1];
                default:;
            endcase
        end
        byte_count++;
    endtask
    always @(negedge cs_n) begin
        assert($time-cs_rise>=120 || cs_rise==0) else $fatal(1,"SPI CS recovery too short");
        bit_count=0;byte_count=0;spi_in=0;spi_out=0;
    end
    always @(posedge sck) if(!cs_n)begin
        spi_in={spi_in[6:0],mosi};
        if(bit_count==7)begin received_byte(spi_in);bit_count=0;end
        else bit_count++;
    end
    always @(posedge cs_n)begin
        if(byte_count>0)assert(bit_count==0) else $fatal(1,"partial SPI byte");
        cs_rise=$time;
    end
endmodule
