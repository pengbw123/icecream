`timescale 1ns/1ps
module score_capacity_case #(parameter integer CAPACITY=8192)(output reg finished=0);
    reg clk=0;
    always #10 clk=~clk;
    reg reset_n=0, cmd_valid=0;
    reg [7:0] cmd_command=0;
    reg [63:0] cmd_payload=0;
    wire score_done,score_error,midi_event_valid,volume_event_valid,loaded,playing,flush_active;
    wire [31:0] midi_event_data,volume_event_data;
    wire [127:0] guide_mask;
    integer cycles=0, received=0, flushes=0, expected_count=0;
    reg checking=0, held=0;
    reg [31:0] held_data;
    wire ready=(cycles%11>=3); // Repeatable downstream back pressure.
    score_player #(.RAM_DEPTH(CAPACITY),.MAX_EVENTS(CAPACITY),.CLK_HZ(50000)) dut(
        .clk(clk),.reset_n(reset_n),.cmd_valid(cmd_valid),.cmd_command(cmd_command),.cmd_payload(cmd_payload),
        .score_done(score_done),.score_error(score_error),.midi_event_data(midi_event_data),
        .midi_event_valid(midi_event_valid),.midi_event_ready(ready),
        .volume_event_data(volume_event_data),.volume_event_valid(volume_event_valid),.volume_event_ready(1'b1),
        .guide_mask(guide_mask),.loaded(loaded),.playing(playing),.flush_active(flush_active));

    function automatic [7:0] note_at(input integer i);
        return 8'(36+(i/2)%64);
    endfunction
    function automatic [7:0] vel_at(input integer i);
        return (i%2==0)?8'(1+(i/128)%127):8'd0;
    endfunction
    function automatic [31:0] crc_event(input [31:0] current,input [47:0] bytes);
        reg [31:0] v;
        v=current;
        for(integer b=0;b<6;b++) for(integer k=0;k<8;k++)
            v=(v>>1)^((v[0]^bytes[b*8+k])?32'hedb88320:32'd0);
        return v;
    endfunction
    always @(posedge clk) if(reset_n) begin
        cycles<=cycles+1;
        if(held && (!midi_event_valid || held_data!==midi_event_data))
            $fatal(1,"capacity=%0d changed stalled MIDI",CAPACITY);
        held<=midi_event_valid && !ready;
        held_data<=midi_event_data;
        if(midi_event_valid && ready) begin
            if(!checking) $fatal(1,"unsolicited event");
            if(received<expected_count) begin
                if(midi_event_data!=={vel_at(received)==0?8'h08:8'h09,
                    vel_at(received)==0?8'h80:8'h90,note_at(received),vel_at(received)})
                    $fatal(1,"capacity=%0d playback order mismatch index=%0d data=%h",CAPACITY,received,midi_event_data);
                received<=received+1;
            end else begin
                if(flushes>=2 || midi_event_data!=={8'h0b,8'hb0,flushes==0?8'd64:8'd123,8'd0})
                    $fatal(1,"wrong final CC pair capacity=%0d data=%h",CAPACITY,midi_event_data);
                flushes<=flushes+1;
            end
        end
    end
    task automatic command(input [7:0] cmd,input [63:0] payload,input bit reject);
        integer guard;
        @(negedge clk);cmd_command=cmd;cmd_payload=payload;cmd_valid=1;
        @(negedge clk);cmd_valid=0;
        guard=0;
        while(!score_done && !score_error && guard<100) begin @(negedge clk);guard++;end
        if(guard==100 || score_error!=reject || score_done==reject)
            $fatal(1,"capacity=%0d command=%h result error=%0d done=%0d expected reject=%0d",CAPACITY,cmd,score_error,score_done,reject);
        @(negedge clk);
    endtask
    task automatic count_case(input integer n);
        reg [31:0] crc;
        integer guard;
        if(n>CAPACITY) begin
            command(8'h50,{40'd0,8'd1,16'(n)},1);
            $display("CAPACITY_BOUNDARY_REJECT_OK capacity=%0d count=%0d",CAPACITY,n);
        end else begin
            command(8'h50,{40'd0,8'd1,16'(n)},0);
            if(dut.event_count!=n || dut.upload_index!=0 || loaded) $fatal(1,"BEGIN count truncated n=%0d",n);
            crc=32'hffffffff;
            for(integer i=0;i<n;i++) begin
                command(8'h51,{vel_at(i),note_at(i),32'd0,16'(i)},0);
                crc=crc_event(crc,{vel_at(i),note_at(i),32'd0});
                if(dut.upload_index!=i+1) $fatal(1,"upload index wrapped n=%0d i=%0d",n,i);
            end
            // One-past-end and a duplicate must not change RAM/CRC/count.
            command(8'h51,{8'd90,8'd60,32'd0,16'(n)},1);
            command(8'h51,{8'd90,8'd60,32'd0,16'(n-1)},1);
            command(8'h52,{8'd0,8'd1,16'(n),(~crc)^32'd1},1);
            if(loaded || dut.upload_index!=n) $fatal(1,"bad CRC accepted or count changed");
            command(8'h52,{8'd0,8'd1,16'(n),~crc},0);
            if(!loaded) $fatal(1,"good CRC rejected");
            received=0;flushes=0;expected_count=n;checking=1;
            command(8'h53,0,0);
            guard=0;
            while((playing || flush_active) && guard<n*30+100) begin @(negedge clk);guard++;end
            if(playing || flush_active || received!=n || flushes!=2 || guide_mask!=0 || dut.cur_index!=n-1)
                $fatal(1,"playback count/last index/flush mismatch capacity=%0d n=%0d got=%0d cc=%0d",CAPACITY,n,received,flushes);
            checking=0;
            $display("CAPACITY_BOUNDARY_PLAY_CRC_OK capacity=%0d count=%0d last_index=%0d final_CC=2",CAPACITY,n,dut.cur_index);
        end
    endtask
    initial begin
        repeat(5) @(negedge clk);reset_n=1;
        command(8'h55,0,CAPACITY<2048);
        command(8'h50,{40'd0,8'd1,16'd0},1);
        count_case(1);count_case(2048);count_case(3140);count_case(4095);
        count_case(4096);count_case(4097);count_case(8191);count_case(8192);count_case(8193);
        command(8'h50,{40'd0,8'd1,16'hffff},1);
        $display("SCORE_CAPACITY_PROFILE_OK capacity=%0d",CAPACITY);
        finished=1;
    end
endmodule

module tb_score_capacity;
    wire a,b,c,d;
    score_capacity_case #(.CAPACITY(2048)) p2048(a);
    score_capacity_case #(.CAPACITY(4096)) p4096(b);
    score_capacity_case #(.CAPACITY(8192)) p8192(c);
    score_capacity_case #(.CAPACITY(3)) p_nonpower(d);
    initial begin wait(a&&b&&c&&d);$display("SCORE_CAPACITY_ALL_PROFILES_OK");$finish;end
    initial begin #100000000;$fatal(1,"capacity watchdog");end
endmodule
