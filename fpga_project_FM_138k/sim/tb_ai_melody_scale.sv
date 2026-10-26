`timescale 1ns/1ps
module tb_ai_melody_scale;
    reg clk=0;always #10 clk=~clk;
    ai_melody_composer dut(.clk(clk),.reset_n(1'b0),.cfg_write(1'b0),.cfg_address(10'd0),.cfg_value(16'd0),
        .suspend(1'b0),.observe_data(32'd0),.observe_valid(1'b0),.out_ready(1'b1));
    integer key,minor,penta,n,k,pc,best,distance,got,total=0;
    function allowed(input integer x,input integer m,input integer p);
        begin
            if(p)allowed=m ? (x==0||x==3||x==5||x==7||x==10) : (x==0||x==2||x==4||x==7||x==9);
            else allowed=m ? (x==0||x==2||x==3||x==5||x==7||x==8||x==10) : (x==0||x==2||x==4||x==5||x==7||x==9||x==11);
        end
    endfunction
    initial begin
        for(key=0;key<12;key=key+1)for(minor=0;minor<2;minor=minor+1)for(penta=0;penta<2;penta=penta+1)for(n=48;n<=84;n=n+1)begin
            best=-1;distance=100;
            for(k=48;k<=84;k=k+1)begin pc=(k-key+120)%12;
                if(allowed(pc,minor,penta)&&((k>n?k-n:n-k)<distance))begin best=k;distance=k>n?k-n:n-k;end
            end
            got=n+$signed(dut.adjustment(dut.pitch_class(n-key),minor,penta,n));
            if(got!=best)$fatal(1,"Scale boundary key%0d minor%0d penta%0d note%0d got%0d expected%0d",key,minor,penta,n,got,best);
            total=total+1;
        end
        $display("PASS %0d exhaustive nearest-scale/range cases: all keys, major/minor, diatonic/pentatonic and both register boundaries",total);$finish;
    end
endmodule
