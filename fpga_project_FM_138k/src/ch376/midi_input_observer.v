// Passive registered copy of events accepted by the board input arbiter.
// Only one accept is asserted per clock. No ready/acknowledgement path here.
module midi_input_observer(
    input wire clk,reset_n,
    input wire [31:0] usb_data,bridge_data,ui_data,
    input wire usb_accept,bridge_accept,ui_accept,
    output reg [31:0] event_data,output reg event_valid,output reg [1:0] source
);
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin event_data<=0;event_valid<=0;source<=0;end
        else begin
            event_valid<=usb_accept||bridge_accept||ui_accept;
            if(usb_accept)begin event_data<=usb_data;source<=0;end
            else if(bridge_accept)begin event_data<=bridge_data;source<=1;end
            else if(ui_accept)begin event_data<=ui_data;source<=2;end
        end
    end
endmodule
