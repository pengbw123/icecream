// USB-MIDI 1.0 four-byte event, first USB byte in packet[7:0].
// Convert to the existing FM convention {cable/CIN,status,data1,data2}.
module usb_midi_event_decode #(
    parameter [6:0] KEY_VELOCITY_MIN=0,
    parameter [6:0] KEY_VELOCITY_MAX=7'd80
) (
    input wire [31:0] packet,
    output wire valid,
    output wire [31:0] event_data
);
    wire [7:0] header=packet[7:0],status=packet[15:8],d1=packet[23:16],d2=packet[31:24];
    wire [3:0] cin=header[3:0];
    wire three=(cin>=8 && cin<=11) || cin==14;
    wire two=cin==12 || cin==13;
    assign valid=(three || two) && status[7:4]==cin && !d1[7] && (two || !d2[7]);
    localparam [7:0] SPAN=KEY_VELOCITY_MAX>KEY_VELOCITY_MIN ? KEY_VELOCITY_MAX-KEY_VELOCITY_MIN : 8'd1;
    localparam [15:0] SLOPE=(16'd32512+({8'd0,SPAN}>>1))/{8'd0,SPAN};
    wire [7:0] delta={1'b0,d2[6:0]}-{1'b0,KEY_VELOCITY_MIN};
    wire [23:0] scaled=delta*SLOPE+24'd128;
    wire [6:0] velocity=d2[6:0]<=KEY_VELOCITY_MIN ? 7'd0 :
        d2[6:0]>=KEY_VELOCITY_MAX ? 7'd127 : scaled[14:8];
    wire [7:0] final_d2=two ? 8'd0 :
        status==8'h90 && d2!=0 ? {1'b0,velocity} : d2;
    assign event_data={header,status,d1,final_d2};
endmodule
