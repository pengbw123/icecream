package com.gowin.instrument;

/** Values use exactly the ranges and numbering of the 138K touch UI. */
final class FmToneSpec {
    static final String[] GROUPS={"预设音色", "总音量", "算法", "运算器", "运算器包络", "音高包络", "LFO 调制", "效果器"};
    static final String[] OPERATORS={"OP 1", "OP 2", "OP 3", "OP 4", "OP 5", "OP 6"};
    static final String[] EFFECTS={"滤波器 FILTER", "混响 REVERB", "延迟 DELAY", "失真 DIST", "合唱 CHORUS", "相位 PHASER"};
    static final class Param {
        final String name; final int row,min,max,offset;
        Param(String n,int r,int lo,int hi,int o){name=n;row=r;min=lo;max=hi;offset=o;}
        public String toString(){return name;}
        int raw(int displayed){if(displayed<min||displayed>max)throw new IllegalArgumentException("请输入 "+min+" 到 "+max);return displayed-offset;}
        int display(int raw){return raw+offset;}
    }
    private static Param p(String n,int row,int lo,int hi){return new Param(n,row,lo,hi,0);}
    private static Param[] all(String[] names,int lo,int hi){Param[] p=new Param[names.length];for(int i=0;i<names.length;i++)p[i]=p(names[i],i,lo,hi);return p;}
    static Param[] parameters(int group,int selector){
        switch(group){
            case 0:return new Param[]{new Param("预设音色",0,1,128,1)};
            case 1:return new Param[]{p("总音量",0,0,127)};
            case 2:return new Param[]{new Param("算法",0,1,32,1),p("反馈",1,0,7),p("振荡器同步 0关 / 1开",2,0,1),new Param("移调（半音）",3,-24,24,-24)};
            case 3:return new Param[]{p("频率模式 0比例 / 1固定",0,0,1),p("粗调（固定模式 0～3）",1,0,31),p("微调",2,0,99),new Param("失谐",3,-7,7,-7),p("输出电平",4,0,99),p("速率缩放",5,0,7),p("力度灵敏度",6,0,7),p("幅度调制灵敏度",7,0,3),p("键盘缩放分界点",8,0,99),p("左侧深度",9,0,99),p("右侧深度",10,0,99),p("左侧曲线",11,0,3),p("右侧曲线",12,0,3),p("运算器 0关 / 1开",13,0,1)};
            case 4:case 5:return all(new String[]{"速率 R1","速率 R2","速率 R3","速率 R4","电平 L1","电平 L2","电平 L3","电平 L4"},0,99);
            case 6:return new Param[]{p("波形",0,0,5),p("速度",1,0,99),p("延迟",2,0,99),p("音高调制深度",3,0,99),p("幅度调制深度",4,0,99),p("音高调制灵敏度",5,0,7),p("LFO 同步 0关 / 1开",6,0,1),p("振荡器同步 0关 / 1开",7,0,1)};
            case 7:
                if(selector<0||selector>5)throw new IllegalArgumentException("效果器无效");
                String[][] names={{"截止频率","共振 Q"},{"衰减","混合"},{"时间","衰减","混合"},{"增益","音色","混合"},{"频率","深度","混合"},{"频率","深度","混合"}};
                java.util.ArrayList<Param> fx=new java.util.ArrayList<>();
                fx.add(p("效果总开关 0关 / 1开",0,0,1));fx.add(p("此效果开关 0关 / 1开",1,0,1));
                if(selector<2)fx.add(p("效果类型",2,0,2));
                for(int i=0;i<names[selector].length;i++)fx.add(p(names[selector][i],3+i,0,99));
                return fx.toArray(new Param[0]);
            default:throw new IllegalArgumentException("音色分类无效");
        }
    }
    static int protocolGroup(int group){return new int[]{6,7,1,2,3,8,4,5}[group];}
    static int protocolSelector(int group,int selector){return group==3||group==4?5-selector:group==7?selector:0;}
    private FmToneSpec(){}
}
