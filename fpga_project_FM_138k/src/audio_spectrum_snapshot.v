// Each display owns a separate pair of 64-column snapshots. A busy/slow or
// unlocked display drops a whole analyzer frame and cannot stall the other.
module audio_spectrum_snapshot #(parameter integer ADDRESS_BITS=6) (
    input wire clk,reset_n,bin_write,
    input wire [ADDRESS_BITS-1:0] bin_address,
    input wire [13:0] bin_data,
    input wire pixel_clk,video_reset_n,frame_latch,
    input wire [ADDRESS_BITS-1:0] pixel_address,
    output wire [6:0] level,peak,
    output reg valid
);
    reg [13:0] snapshots[0:(1<<(ADDRESS_BITS+1))-1];
    reg write_bank,publish_toggle,video_ack,copying,waiting;
    reg [1:0] ack_sync;
    wire ready=!waiting;
    wire start=bin_write&&bin_address==0&&ready;
    always @(posedge clk)if(reset_n&&bin_write&&(copying||start))
        snapshots[{write_bank,bin_address}]<=bin_data;
    always @(posedge clk or negedge reset_n)
        if(!reset_n)begin write_bank<=0;publish_toggle<=0;ack_sync<=0;copying<=0;waiting<=0;end
        else begin
            ack_sync<={ack_sync[0],video_ack};
            if(start)copying<=1;
            if(bin_write&&copying&&(&bin_address))begin copying<=0;publish_toggle<=~publish_toggle;waiting<=1;end
            // Only return to the other bank after the pixel domain releases it.
            if(waiting&&ack_sync[1]==publish_toggle)begin write_bank<=~write_bank;waiting<=0;end
        end
    reg display_bank;
    reg [1:0] publish_sync,bank_sync;
    reg [13:0] pixel_data;
    always @(posedge pixel_clk)pixel_data<=snapshots[{display_bank,pixel_address}];
    assign {peak,level}=valid?pixel_data:14'd0;
    always @(posedge pixel_clk or negedge video_reset_n)
        if(!video_reset_n)begin publish_sync<=0;bank_sync<=0;display_bank<=1;valid<=0;video_ack<=0;end
        else begin
            publish_sync<={publish_sync[0],publish_toggle};bank_sync<={bank_sync[0],write_bank};
            if(frame_latch&&publish_sync[1]!=video_ack)begin
                display_bank<=bank_sync[1];valid<=1;video_ack<=publish_sync[1];
            end
        end
endmodule
