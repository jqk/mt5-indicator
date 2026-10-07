//+------------------------------------------------------------------+
//|                                                       PinBar.mq5 |
//|                                 jqk - 组合K线 pinbar / 十字星信号 |
//|                                 规格说明见同目录 pinbar.md          |
//+------------------------------------------------------------------+
#property copyright   "jqk"
#property link        ""
#property version     "1.00"
#property description "组合K线(CB) 底/顶 pinbar 与十字星信号：收盘判定、不重绘。规格见 pinbar.md。"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3

//--- plot 0: 买入三角（信号K线低点下方）
#property indicator_label1  "买入"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  1
//--- plot 1: 卖出三角（信号K线高点上方）
#property indicator_label2  "卖出"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  1
//--- plot 2: 信号类型（不可见，供 EA 通过 iCustom 读取）
#property indicator_label3  "信号类型"
#property indicator_type3   DRAW_NONE

//--- plot 2 的信号类型取值
#define SIG_NONE        0.0  // 无信号
#define SIG_BOTTOM_PIN  1.0  // 底 pinbar（吊颈线）
#define SIG_TOP_PIN     2.0  // 顶 pinbar（锤子线）
#define SIG_DOJI        3.0  // 十字星
#define SIG_PIN_BOTH    4.0  // 底+顶 pinbar 同时成立（影线等长且双极值）

//--- Wingdings 三角符号
#define ARROW_BUY  115     // ▲ 向上三角
#define ARROW_SELL 116     // ▼ 向下三角

//--- 组合与极值
input group "=== 组合与极值 ==="
input int    InpCbBars         = 1;       // 组合K线数量 n (1-3)
input int    InpLookbackBars   = 8;       // 回看周期 m (须大于 n)
//--- 计算范围
input group "=== 计算范围 ==="
input int    InpMaxBars        = 1000;    // 最多计算的K线数 (>=1)
//--- ATR 过滤
input group "=== ATR 过滤 ==="
input int    InpAtrPeriod      = 14;      // ATR 周期
input double InpMinAtrPct      = 80.0;    // 最小ATR比例 %（CB高度/CB周期ATR均值）
//--- 形态判定
input group "=== 形态判定 ==="
input double InpMaxHeadPct     = 33.0;    // 锤头比例上限 %（预定义有效值）
input bool   InpHeadWeighted   = false;   // 锤头比例按ATR加权
input double InpMaxDojiBodyPct = 5.0;     // 十字星实体比例上限 %
//--- 显示
input group "=== 显示 ==="
input color  InpBuyColor       = clrLime; // 买入三角颜色
input color  InpSellColor      = clrRed;  // 卖出三角颜色
input int    InpArrowWidth     = 1;       // 三角线宽
input int    InpArrowShiftPx   = 10;      // 三角与K线的垂直间距（像素）

//--- 报警（预留：启用时取消本行与 EvaluateBar 中报警代码的注释）
// input bool InpAlerts = false;  // 收盘信号弹窗报警

//--- 指标缓冲
double BuyBuffer[];    // 买入三角：锚定 CB 最低价
double SellBuffer[];   // 卖出三角：锚定 CB 最高价
double TypeBuffer[];   // 信号类型，取值见 SIG_*
//--- Wilder ATR（非序列索引：0 = 最旧一根）
double g_atr[];

//+------------------------------------------------------------------+
//| 自定义指标初始化                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- 输入校验：不合格直接拒绝加载
   if(InpCbBars < 1 || InpCbBars > 3)
     { Print("参数错误：组合K线数量 n 必须在 1-3 之间"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpLookbackBars <= InpCbBars)
     { Print("参数错误：回看周期 m 必须大于组合数量 n"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpMaxBars < 1)
     { Print("参数错误：最多计算的K线数必须不小于 1"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpAtrPeriod < 1)
     { Print("参数错误：ATR 周期必须不小于 1"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpMinAtrPct < 0.0)
     { Print("参数错误：最小ATR比例不能为负"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpMaxHeadPct < 1.0 || InpMaxHeadPct > 50.0)
     { Print("参数错误：锤头比例上限必须在 1-50 之间"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpMaxDojiBodyPct < 0.0 || InpMaxDojiBodyPct > 10.0)
     { Print("参数错误：十字比例必须在 0-10 之间"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpArrowWidth < 1)
     { Print("参数错误：三角线宽必须不小于 1"); return(INIT_PARAMETERS_INCORRECT); }

   //--- 缓冲区
   SetIndexBuffer(0, BuyBuffer,  INDICATOR_DATA);
   SetIndexBuffer(1, SellBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, TypeBuffer, INDICATOR_DATA);

   //--- 三角符号与像素位移（PLOT_ARROW_SHIFT 正值向下、负值向上）
   PlotIndexSetInteger(0, PLOT_ARROW, ARROW_BUY);
   PlotIndexSetInteger(1, PLOT_ARROW, ARROW_SELL);
   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT,  InpArrowShiftPx);   // 买入：低点下方
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, -InpArrowShiftPx);   // 卖出：高点上方

   //--- 空值约定：箭头用 EMPTY_VALUE，信号类型用 0
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0.0);

   //--- 颜色与线宽（以输入参数为准，属性默认值仅是后备）
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, InpBuyColor);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, 0, InpSellColor);
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, InpArrowWidth);
   PlotIndexSetInteger(1, PLOT_LINE_WIDTH, InpArrowWidth);

   //--- 预热期之前不绘制
   int draw_begin = MathMax(InpLookbackBars, InpAtrPeriod + InpCbBars);
   for(int plot = 0; plot < 3; plot++)
      PlotIndexSetInteger(plot, PLOT_DRAW_BEGIN, draw_begin);

   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("PinBar(%d,%d)", InpCbBars, InpLookbackBars));
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| 真实波幅 TR                                                        |
//+------------------------------------------------------------------+
double TrueRange(const int i, const double &high[], const double &low[],
                 const double &close[])
  {
   if(i <= 0)
      return(high[0] - low[0]);
   return(MathMax(high[i] - low[i],
                  MathMax(MathAbs(high[i] - close[i-1]),
                          MathAbs(low[i]  - close[i-1]))));
  }

//+------------------------------------------------------------------+
//| Wilder ATR：增量更新（非序列索引，0 = 最旧一根）                      |
//+------------------------------------------------------------------+
void UpdateAtr(const int rates_total, const int prev_calculated,
               const double &high[], const double &low[], const double &close[])
  {
   ArrayResize(g_atr, rates_total);
   int period = InpAtrPeriod;
   int begin  = (prev_calculated > 0) ? prev_calculated - 1 : 0;

   for(int i = begin; i < rates_total; i++)
     {
      if(i < period)                       // 预热期无 ATR，置 0
        {
         g_atr[i] = 0.0;
         continue;
        }
      if(i == period)                      // 首个有效值：前 period 个 TR 的简单平均
        {
         double sum = 0.0;
         for(int j = 1; j <= period; j++)
            sum += TrueRange(j, high, low, close);
         g_atr[i] = sum / period;
         continue;
        }
      g_atr[i] = (g_atr[i-1] * (period - 1) + TrueRange(i, high, low, close)) / period;
     }
  }

//+------------------------------------------------------------------+
//| 对已收盘K线 i 做信号评估（k = 1..n，命中即止）                        |
//+------------------------------------------------------------------+
void EvaluateBar(const int i, const int rates_total, const bool live,
                 const double &open[], const double &high[],
                 const double &low[],  const double &close[])
  {
   for(int k = 1; k <= InpCbBars; k++)
     {
      int i0 = i - k + 1;                     // CB 首根
      double cbOpen  = open[i0];
      double cbClose = close[i];
      double cbHigh  = high[i0];
      double cbLow   = low[i0];
      for(int j = i0 + 1; j <= i; j++)
        {
         if(high[j] > cbHigh) cbHigh = high[j];
         if(low[j]  < cbLow)  cbLow  = low[j];
        }
      double cbHeight = cbHigh - cbLow;
      if(cbHeight <= 0.0)
         continue;                            // 流程第 1 步：一字线不合格

      //--- 流程第 2 步：ATR 比例 = CB 高度 / CB 各根 ATR 均值
      double atrAvg = 0.0;
      for(int j = i0; j <= i; j++)
         atrAvg += g_atr[j];
      atrAvg /= k;
      if(atrAvg <= 0.0)
         continue;
      double atrRatio = cbHeight / atrAvg;
      if(atrRatio < InpMinAtrPct / 100.0)
         continue;

      //--- 流程第 3 步：形态判定（pinbar 优先于十字星）
      double headThr = InpMaxHeadPct / 100.0;
      if(InpHeadWeighted)                      // 加权：×√ATR比例，上限 50%
         headThr = MathMin(headThr * MathSqrt(atrRatio), 0.50);

      double body  = MathAbs(cbClose - cbOpen);
      double upper = cbHigh - MathMax(cbOpen, cbClose);   // 上影线
      double lower = MathMin(cbOpen, cbClose) - cbLow;    // 下影线
      bool isPin  = (body + MathMin(upper, lower)) / cbHeight <= headThr;
      bool isDoji = body / cbHeight <= InpMaxDojiBodyPct / 100.0;
      if(!isPin && !isDoji)
         continue;

      //--- 流程第 4 步：位置判定（回看窗口含 CB 自身，极值并列算合格）
      int    w0    = i - InpLookbackBars + 1;
      double wLow  = low[w0];
      double wHigh = high[w0];
      for(int j = w0 + 1; j <= i; j++)
        {
         if(low[j]  < wLow)  wLow  = low[j];
         if(high[j] > wHigh) wHigh = high[j];
        }
      bool lowExtreme  = (cbLow  <= wLow);     // 窗口含 CB，故 ≤ 等价于 ==
      bool highExtreme = (cbHigh >= wHigh);

      bool buy  = false;
      bool sell = false;
      if(isPin)
        {
         if(lower >= upper && lowExtreme)  buy  = true;  // 针在下（等长时两侧均判定）
         if(upper >= lower && highExtreme) sell = true;  // 针在上（等长时两侧均判定）
        }
      else
        {
         if(lowExtreme)  buy  = true;           // 十字星低点极值
         if(highExtreme) sell = true;           // 十字星高点极值（可同时）
        }
      if(!buy && !sell)
         continue;

      //--- 流程第 5 步：画三角并记录类型
      if(buy)
         BuyBuffer[i] = cbLow;
      if(sell)
         SellBuffer[i] = cbHigh;
      TypeBuffer[i] = isPin ? (buy && sell ? SIG_PIN_BOTH
                                           : (buy ? SIG_BOTTOM_PIN : SIG_TOP_PIN))
                            : SIG_DOJI;

      //--- 报警（预留功能：取消本段与文件头部 InpAlerts 的注释即可启用）
      // if(live && InpAlerts)
      //    Alert(_Symbol, " ", EnumToString(Period()), ": PinBar ",
      //          buy && sell ? "BUY+SELL 双向" : (buy ? "BUY" : "SELL"),
      //          " @ ", DoubleToString(cbClose, _Digits));

      return;                                   // 跨 k 命中即止
     }
  }

//+------------------------------------------------------------------+
//| 自定义指标迭代函数                                                  |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < 2)
      return(0);

   //--- 统一按非序列索引处理（0 = 最旧一根）
   ArraySetAsSeries(open,  false);
   ArraySetAsSeries(high,  false);
   ArraySetAsSeries(low,   false);
   ArraySetAsSeries(close, false);

   UpdateAtr(rates_total, prev_calculated, high, low, close);

   //--- 只评估已收盘K线：最后一根正在形成的K线永不评估 → 不重绘
   int warmup = MathMax(InpLookbackBars - 1, InpAtrPeriod + InpCbBars - 1);
   int start;
   if(prev_calculated <= 0)
     {
      ArrayInitialize(BuyBuffer,  EMPTY_VALUE);
      ArrayInitialize(SellBuffer, EMPTY_VALUE);
      ArrayInitialize(TypeBuffer, SIG_NONE);
      start = MathMax(warmup, rates_total - 1 - InpMaxBars);   // 2.8：只算最近 InpMaxBars 根
     }
   else
      start = MathMax(prev_calculated - 1, warmup);

   for(int i = start; i <= rates_total - 2; i++)
     {
      BuyBuffer[i]  = EMPTY_VALUE;
      SellBuffer[i] = EMPTY_VALUE;
      TypeBuffer[i] = SIG_NONE;
      EvaluateBar(i, rates_total, prev_calculated > 0, open, high, low, close);
     }

   //--- 正在形成的K线保持空值
   BuyBuffer[rates_total-1]  = EMPTY_VALUE;
   SellBuffer[rates_total-1] = EMPTY_VALUE;
   TypeBuffer[rates_total-1] = SIG_NONE;

   return(rates_total);
  }
//+------------------------------------------------------------------+
