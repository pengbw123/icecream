// Independent Primer25K USB-MIDI -> UART bridge. No audio synthesis here.
module top_bridge #(
    parameter [6:0] KEY_VELOCITY_MIN=7'h00,
    parameter [6:0] KEY_VELOCITY_MAX=7'd80
) (
    input wire clk, input wire key_s2,
    input wire uart_rx_pin, output wire uart_tx_pin,
    inout wire usb_host_dp, usb_host_dn,
    output wire midi_bridge_tx
);
    wire usb_clk,bram_clk,pll_lock;
    usb_pll u_usb_pll (.clkin(clk),.clkout0(usb_clk),.clkout1(bram_clk),.lock(pll_lock));
    reg [15:0] startup=0;
    always @(posedge clk or posedge key_s2)
        if (key_s2) startup<=0;
        else if (!(&startup)) startup<=startup+1'b1;
    wire reset_n=&startup;
    wire uart_activity;
    reg [1:0] activity_sync,lock_sync;
    reg [27:0] alive_count;
    reg [22:0] hold_count;
    reg watchdog_reset;
    reg last_lock;
    reg [31:0] unlocks;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            activity_sync<=0;lock_sync<=0;alive_count<=0;hold_count<=0;
            watchdog_reset<=0;last_lock<=0;unlocks<=0;
        end else begin
            activity_sync<={activity_sync[0],uart_activity};
            lock_sync<={lock_sync[0],pll_lock};last_lock<=lock_sync[1];
            if (last_lock && !lock_sync[1]) unlocks<=unlocks+1'b1;
            if (!lock_sync[1]) begin alive_count<=0;hold_count<=0;watchdog_reset<=0;end
            else if (watchdog_reset) begin
                if (hold_count==23'd4999999) begin watchdog_reset<=0;hold_count<=0;alive_count<=0;end
                else hold_count<=hold_count+1'b1;
            end else if (activity_sync[1]) alive_count<=0;
            else if (alive_count==28'd149999999) begin watchdog_reset<=1;hold_count<=0;end
            else alive_count<=alive_count+1'b1;
        end
    end
    wire host_reset=~reset_n | ~pll_lock | watchdog_reset;
    wire [31:0] usb_event;
    wire usb_toggle,connected;
    reg ack_toggle;
    usb_midi_host u_host (
        .clk_48m(usb_clk),.clk_cpu_bram_96m(bram_clk),.reset(host_reset),
        .usb_dp(usb_host_dp),.usb_dn(usb_host_dn),
        .cpu_uart_tx(uart_tx_pin),.cpu_uart_rx(uart_rx_pin),
        .midi_event_data(usb_event),.midi_event_toggle(usb_toggle),
        .midi_event_ack_toggle(ack_toggle),.midi_connected(connected),
        .debug_pll_unlock_count(unlocks),.debug_reset_n(),.debug_cpu_fetch(),
        .debug_uart_write(uart_activity),.debug_cpu_addr()
    );
    reg [1:0] request_sync,connected_sync;
    reg connected_last;
    reg [1:0] panic_pending;
    wire tx_ready;
    wire event_pending=request_sync[1]!=ack_toggle;
    localparam [7:0] VELOCITY_SPAN=(KEY_VELOCITY_MAX>KEY_VELOCITY_MIN)
        ? KEY_VELOCITY_MAX-KEY_VELOCITY_MIN : 8'd1;
    localparam [15:0] VELOCITY_SLOPE=(16'd32512+(VELOCITY_SPAN>>1))/VELOCITY_SPAN;
    wire [7:0] delta={1'b0,usb_event[6:0]}-{1'b0,KEY_VELOCITY_MIN};
    wire [23:0] scaled=delta*VELOCITY_SLOPE+24'd128;
    wire [6:0] velocity=usb_event[6:0]<=KEY_VELOCITY_MIN ? 7'd0 :
        usb_event[6:0]>=KEY_VELOCITY_MAX ? 7'd127 : scaled[14:8];
    wire [31:0] calibrated=usb_event[23:16]==8'h90 && usb_event[6:0]!=0
        ? {usb_event[31:8],1'b0,velocity} : usb_event;
    wire [31:0] tx_event=panic_pending==2 ? 32'h00B04000 :
        panic_pending==1 ? 32'h00B07B00 : calibrated;
    wire tx_valid=panic_pending!=0 || (event_pending && !host_reset);
    midi_frame_tx u_tx (.clk(clk),.reset_n(reset_n),.event_data(tx_event),
        .event_valid(tx_valid),.event_ready(tx_ready),.tx(midi_bridge_tx));
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            request_sync<=0;connected_sync<=0;connected_last<=0;
            ack_toggle<=0;panic_pending<=0;
        end else begin
            connected_sync<={connected_sync[0],connected};connected_last<=connected_sync[1];
            if (host_reset) begin request_sync<=0;ack_toggle<=0;end
            else request_sync<={request_sync[0],usb_toggle};
            if (tx_valid && tx_ready) begin
                if (panic_pending!=0) panic_pending<=panic_pending-1'b1;
                else ack_toggle<=request_sync[1];
            end
            // Release the sustain pedal and all notes after physical disconnect.
            if (connected_last && !connected_sync[1]) panic_pending<=2;
        end
    end
endmodule
