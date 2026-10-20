// Fixed 8x16 character cells. Character ROM and font ROM each have a
// registered stage; their column/row/enable travel through the same stages.
// No writable character framebuffer or CPU rendering is involved.
module rtl_performance_text(
    input wire pclk,reset_n,enabled,
    input wire [10:0] h,input wire [9:0] v,
    input wire [4:0] preset,voices,algorithm,
    input wire [6:0] volume,delay_samples,
    input wire signed [3:0] octave,
    input wire touch_ok,auto_gain,
    output wire ink,output wire [23:0] color
);
    reg [7:0] font[0:2047];
    reg [7:0] names[0:319];
    initial begin
        $readmemh("src/generated/font8x16.mem",font);
        $readmemh("src/generated/fm_rom1a_names.mem",names);
    end
    reg [7:0] character;
    reg [10:0] local_x;
    reg [9:0] local_y;
    reg active;
    reg [23:0] tint;
    reg [127:0] label;
    integer column;
    always @*begin
        active=0;character=32;local_x=0;local_y=0;label=0;column=0;tint=24'hF0F5FA;
        if(h>=24&&h<152&&v>=8&&v<24)begin
            active=1;local_x=h-24;local_y=v-8;column=local_x>>3;
            label="FM SYNTH ACG720 ";character=label[127-column*8 -:8];tint=24'h5AE8D0;
        end else if(h>=24&&h<104&&v>=32&&v<48)begin
            active=1;local_x=h-24;local_y=v-32;column=local_x>>3;
            character=names[preset*10+column];
        end else if(h>=352&&h<456&&v>=24&&v<40)begin
            active=1;local_x=h-352;local_y=v-24;column=local_x>>3;
            case(column)
                0:character="P";1:character="0"+(preset+1)/10;2:character="0"+(preset+1)%10;
                4:character="V";5:character="0"+voices/10;6:character="0"+voices%10;
                8:character="A";9:character="0"+(algorithm+1)/10;10:character="0"+(algorithm+1)%10;
                default:character=32;
            endcase
        end else if(h>=648&&h<792)begin
            local_x=h-648;column=local_x>>3;
            if(v>=62&&v<78)begin active=1;local_y=v-62;label="PRESET          ";end
            else if(v>=120&&v<136)begin active=1;local_y=v-120;label="VOLUME          ";end
            else if(v>=176&&v<192)begin active=1;local_y=v-176;label="OCTAVE          ";end
            else if(v>=260&&v<276)begin active=1;local_y=v-260;label="     PANIC      ";end
            else if(v>=306&&v<322)begin active=1;local_y=v-306;
                label=touch_ok?"TOUCH OK        ":"TOUCH ERR       ";end
            else if(v>=326&&v<342)begin active=1;local_y=v-326;label="VIEW            ";end
            else if(v>=356&&v<372)begin active=1;local_y=v-356;label=" WAVE      XY   ";end
            else if(v>=384&&v<400)begin active=1;local_y=v-384;label="XY DELAY        ";end
            else if(v>=456&&v<472)begin active=1;local_y=v-456;
                label=auto_gain?"    AUTO ON     ":"    AUTO OFF    ";end
            if(column<16)character=label[127-column*8 -:8];
            if(v>=120&&v<136)case(column)
                9:character="0"+volume/100;10:character="0"+(volume/10)%10;11:character="0"+volume%10;
                default:;
            endcase
            if(v>=176&&v<192)case(column)
                9:character=octave<0?"-":"+";10:character="0"+(octave<0?-octave:octave);
                default:;
            endcase
            if(v>=384&&v<400)case(column)
                10:character="0"+delay_samples/100;11:character="0"+(delay_samples/10)%10;
                12:character="0"+delay_samples%10;default:;
            endcase
        end
    end
    reg [7:0] code,glyph_row;
    reg [3:0] row;
    reg [2:0] col1,col2;
    reg valid1,valid2;
    reg [23:0] color1,color2;
    always @(posedge pclk)begin
        code<=character;row<=local_y[3:0];col1<=local_x[2:0];
        valid1<=reset_n&&enabled&&active;color1<=tint;
        glyph_row<=font[{code[6:0],row}];col2<=col1;valid2<=valid1&&reset_n;color2<=color1;
    end
    assign ink=valid2&&glyph_row[7-col2];assign color=color2;
endmodule
