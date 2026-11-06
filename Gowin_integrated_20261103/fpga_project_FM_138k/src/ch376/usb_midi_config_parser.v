// USB MIDI 1.0 configuration descriptor stream; descriptors may cross packets.
// USB class 01/subclass 03/protocol 00, bulk IN, full-speed MPS <=64.
// No assumption that the MIDI interface or its endpoint has a fixed number.
module usb_midi_config_parser (
    input wire clk, reset_n, start,
    input wire byte_valid,
    input wire [7:0] byte_data,
    input wire finish,
    output reg done, malformed, found,
    output reg [7:0] configuration_value, interface_number, alternate_setting,
    output reg [3:0] endpoint_number,
    output reg [6:0] endpoint_max_packet,
    output reg [15:0] total_length
);
    reg [15:0] received;
    reg [7:0] position, length, dtype;
    reg [7:0] if_number, if_alt, if_class, if_subclass, if_protocol;
    reg [7:0] ep_address, ep_attributes;
    reg [15:0] ep_size;
    reg midi_interface;
    reg active;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            done<=0;malformed<=0;found<=0;configuration_value<=0;interface_number<=0;
            alternate_setting<=0;endpoint_number<=0;endpoint_max_packet<=0;total_length<=0;
            received<=0;position<=0;length<=0;dtype<=0;if_number<=0;if_alt<=0;
            if_class<=0;if_subclass<=0;if_protocol<=0;ep_address<=0;ep_attributes<=0;
            ep_size<=0;midi_interface<=0;active<=0;
        end else begin
            done<=0;
            if (start) begin
                malformed<=0;found<=0;configuration_value<=0;total_length<=0;
                received<=0;position<=0;length<=0;dtype<=0;midi_interface<=0;active<=1;
                interface_number<=0;alternate_setting<=0;endpoint_number<=0;endpoint_max_packet<=0;
            end else if (active) begin
                if (byte_valid) begin
                    received<=received+1'b1;
                    if (received==16'hffff) malformed<=1;
                    if (position==0) begin
                        length<=byte_data;position<=1;
                        if (byte_data<2) malformed<=1;
                    end else begin
                        if (position==1) begin
                            dtype<=byte_data;
                            if (received==1 && (byte_data!=2 || length<9)) malformed<=1;
                            if (byte_data==4) begin
                                midi_interface<=0;
                                if (length<9) malformed<=1;
                            end
                            if (byte_data==5 && length<7) malformed<=1;
                        end
                        // First descriptor must be the configuration header.
                        if (received<9) case (received)
                            2:total_length[7:0]<=byte_data;
                            3:total_length[15:8]<=byte_data;
                            5:configuration_value<=byte_data;
                            default:;
                        endcase
                        if (dtype==4 && position>=2) case (position)
                            2:if_number<=byte_data;
                            3:if_alt<=byte_data;
                            5:if_class<=byte_data;
                            6:if_subclass<=byte_data;
                            7:if_protocol<=byte_data;
                            default:;
                        endcase
                        if (dtype==5 && position>=2) case (position)
                            2:ep_address<=byte_data;
                            3:ep_attributes<=byte_data;
                            4:ep_size[7:0]<=byte_data;
                            5:ep_size[15:8]<=byte_data;
                            default:;
                        endcase
                        if (position+1>=length) begin
                            position<=0;
                            if (dtype==4 && length>=9)
                                midi_interface<=if_class==1 && if_subclass==3 && if_protocol==0;
                            if (dtype==5 && length>=7 && midi_interface && !found &&
                                ep_address[7] && ep_address[6:4]==0 && ep_address[3:0]!=0 &&
                                ep_attributes==2 && (ep_size==8 || ep_size==16 || ep_size==32 || ep_size==64)) begin
                                found<=1;interface_number<=if_number;alternate_setting<=if_alt;
                                endpoint_number<=ep_address[3:0];endpoint_max_packet<=ep_size[6:0];
                            end
                        end else position<=position+1'b1;
                    end
                end
                if (finish) begin
                    active<=0;done<=1;
                    if (position!=0 || received<9 || received!=total_length ||
                        total_length<9 || configuration_value==0) begin malformed<=1;found<=0;end
                    else if (malformed) found<=0;
                end
            end
        end
    end
endmodule
