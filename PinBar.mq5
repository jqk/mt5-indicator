//+------------------------------------------------------------------+
//|                                                       PinBar.mq5 |
//|                                 jqk - 组合K线 pinbar / 十字星信号 |
//|                                 规格说明见同目录 pinbar.md          |
//+------------------------------------------------------------------+
// 业务逻辑总览（详见 pinbar.md）：
//   · 把最近的 n 根K线合并成一根“组合K线” CB（combined bar）。
//   · 判断 CB 是“底 pinbar(吊颈线)/ 顶 pinbar(锤子线)/ 十字星”。
//   · 只有当 CB 的极值(最高/最低价)同时是回看窗口 m 的极值时才算合格，给出买入/卖出信号。
//   · 只在 K 线收盘时判断 → 信号一旦出现就不会变（不重绘）。
//   · 信号用 Wingdings 符号画在信号K线上下：K线下方=买入，K线上方=卖出，
//     用颜色区分 CB 组合数：红=1根、桔红=2根、黄=3根（颜色见 plot 定义）。
//+------------------------------------------------------------------+
#property copyright   "jqk"
#property link        ""
#property version     "1.20"
#property description "组合K线(CB) 底/顶 pinbar 与十字星信号：收盘判定、不重绘。规格见 pinbar.md。"
#property indicator_chart_window   // 画在主图窗口（叠加在K线上），而非子窗口
#property indicator_buffers 7      // 指标缓冲总数（用于存放计算结果供EA/图表读取）
#property indicator_plots   7      // 绘图序列数，与缓冲一一对应

//--- 关于“怎么画信号符号”的重要说明：
//   MT5 的指标缓冲绘制样式 DRAW_ARROW 只能使用 Wingdings 符号字体渲染，
//   字符码 0-255 会被解释成 Wingdings 里对应的图形（不是文字数字）。
//   例如 49/50/51('1/2/3') 在 Wingdings 里会渲染成“文件夹”等图形，而不是数字，
//   所以这里不追求画文字数字，而是改用【符号 + 颜色】双重区分：
//     · 位置：K线下方=买入、K线上方=卖出；
//     · 颜色：红=CB 由 1 根组成、桔红=2 根、黄=3 根。
//   上下买卖用同一个符号(●实心圆点)，保证买卖两端大小一致、视觉统一。

//--- plot 0-2: 买入(画在信号K线下方)，按 k 分色：1红 2桔红 3黄
#property indicator_label1  "买入1根"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrRed
#property indicator_width1  1
#property indicator_label2  "买入2根"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrOrange
#property indicator_width2  1
#property indicator_label3  "买入3根"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrYellow
#property indicator_width3  1
//--- plot 3-5: 卖出(画在信号K线上方)，同样按 k 分色：1红 2桔红 3黄
#property indicator_label4  "卖出1根"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrRed
#property indicator_width4  1
#property indicator_label5  "卖出2根"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrOrange
#property indicator_width5  1
#property indicator_label6  "卖出3根"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrYellow
#property indicator_width6  1
//--- plot 6: 信号类型（给 EA 用的“隐藏信号码”，本身不绘制）
#property indicator_label7  "信号类型"
#property indicator_type7   DRAW_NONE

//--- 信号类型取值（此编码写进 TypeBuffer，供 EA 用 iCustom 读取后自行判断）
#define SIG_NONE        0.0  // 无信号
#define SIG_BOTTOM_PIN  1.0  // 底 pinbar（吊颈线）
#define SIG_TOP_PIN     2.0  // 顶 pinbar（锤子线）
#define SIG_DOJI        3.0  // 十字星
#define SIG_PIN_BOTH    4.0  // 底+顶 pinbar 同时成立（影线等长且双极值）

//--- 信号符号：Wingdings 108 = ● 实心圆点。
//   买卖统一用一个符号(而不是上下三角)，这样两端渲染大小一致。
//   说明：之所以不用数字 49/50/51，是因为 DRAW_ARROW 固定按 Wingdings 渲染，
//   49/50/51 在 Wingdings 里是“文件夹”等图形而非数字。
#define ARROW_MARK  108       // ● 实心圆点

//--- 每种组合数 k 对应的颜色：红=1根、桔红=2根、黄=3根（k 见 SIG 组合数）
#define COLOR_K1  clrRed      // 1 根CB组成 → 红
#define COLOR_K2  clrOrange   // 2 根CB组成 → 桔红
#define COLOR_K3  clrYellow   // 3 根CB组成 → 黄

//--- MQL5 输入参数：`input` 语句写出的参数会显示在“输入”对话框并可随时修改，
//   修改后指标自动重新加载(OnInit 重新执行)。`input group "..."` 只是参数分组显示。
//--- 组合与极值
input group "=== 组合与极值 ==="
input int    InpCbBars         = 1;       // 组合K线数量 n (1-3)：几根K线合成一根CB
input int    InpLookbackBars   = 8;       // 回看周期 m (须大于 n)：CB 极值要与最近m根比较
//--- 计算范围
input group "=== 计算范围 ==="
input int    InpMaxBars        = 1000;    // 最多计算的K线数 (>=1)：只对最近若干根已收盘K线判断
//--- ATR 过滤
input group "=== ATR 过滤 ==="
input int    InpAtrPeriod      = 14;      // ATR 周期：计算平均波幅用
input double InpMinAtrPct      = 80.0;    // 最小ATR比例 %（CB高度/CB周期ATR均值）：过短柱体没意义，剔除
//--- 形态判定
input group "=== 形态判定 ==="
input double InpMaxHeadPct     = 33.0;    // 锤头比例上限 %（预定义有效值）：锤头太长就不算 pinbar
input bool   InpHeadWeighted   = false;   // 锤头比例按ATR加权：true 时允许长柱体用更宽松的比例
input double InpMaxDojiBodyPct = 5.0;     // 十字星实体比例上限 %
//--- 显示
input group "=== 显示 ==="
input int    InpArrowWidth     = 1;       // 信号符号线宽（粗细）
input int    InpArrowShiftPx   = 10;      // 信号与K线的垂直间距（像素）：买入向下、卖出向上偏移
//说明：信号颜色不用输入——按组合数 k 固定：1=红、2=桔红、3=黄（见 COLOR_K1..K3）。

//--- 报警（预留：启用时取消本行与 EvaluateBar 中报警代码的注释）
// input bool InpAlerts = false;  // 收盘信号弹窗报警

//--- 全局缓冲数组声明。注意：MQL5 中下标默认 0 是“最旧”K线（非序列），
//   我们主动用 ArraySetAsSeries(...,false) 固定这一约定，全程用同一套索引，避免混乱。
//--- 指标缓冲：买入/卖出各 3 个，分别对应符号颜色 红(1根)/桔红(2根)/黄(3根)(k=CB组合数)。
//   里面存的是“CB极值价”（买入=CB最低价、卖出=CB最高价），价处即画符号处，也供 EA 读取数值。
double BuyDigit1[], BuyDigit2[], BuyDigit3[];     // 买入：存 CB 最低价，按 k 分到 1/2/3(即红/桔红/黄)
double SellDigit1[], SellDigit2[], SellDigit3[];  // 卖出：存 CB 最高价，按 k 分到 1/2/3(即红/桔红/黄)
double TypeBuffer[];                              // 信号类型编码，取值见 SIG_*
//--- Wilder ATR（非序列索引：0 = 最旧一根），在指标内部算好备用
double g_atr[];

//+------------------------------------------------------------------+
//| 自定义指标初始化 OnInit                                           |
//| MQL5：指标第一次加载、或任何输入参数被修改后，都会重新走一遍本函数。   |
//| 这里只做“一次性”的准备：校验参数、绑定缓冲、设置空值/绘制起点等。      |
//| 返回 INIT_SUCCEEDED 才会继续调用 OnCalculate。                         |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- 参数校验：不合法直接返回 INIT_PARAMETERS_INCORRECT，这样指标就不会被加载，
   //   避免带着坏参数去跑。每个分支都会 Print 出具体原因，方便排查。
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

   //--- 把全局数组绑定到“指标缓冲”→ 之后对数组的读写就等价于对图表缓冲的读写。
   //   顺序必须与 indicator_plots 一一对应：0-2 买入1/2/3，3-5 卖出1/2/3，6 信号类型。
   SetIndexBuffer(0, BuyDigit1,  INDICATOR_DATA);
   SetIndexBuffer(1, BuyDigit2,  INDICATOR_DATA);
   SetIndexBuffer(2, BuyDigit3,  INDICATOR_DATA);
   SetIndexBuffer(3, SellDigit1, INDICATOR_DATA);
   SetIndexBuffer(4, SellDigit2, INDICATOR_DATA);
   SetIndexBuffer(5, SellDigit3, INDICATOR_DATA);
   SetIndexBuffer(6, TypeBuffer, INDICATOR_DATA);

   //--- 为 6 个信号 plot 设置：使用的符号、颜色、线宽、垂直偏移。
   //   PLOT_ARROW    = 信号用的 Wingdings 字符（这里统一用 ● 实心圆点）；
   //   PLOT_LINE_COLOR = 按 k 分色：plot0/3 红(1根)、1/4 桔红(2根)、2/5 黄(3根)；
   //   PLOT_ARROW_SHIFT = 像素垂直偏移：（正值向下、负值向上）
   //       买入(0-2) 向下偏移 → 符号画在K线低点下方；卖出(3-5) 向上偏移 → 画在高点上方。
   for(int p = 0; p < 3; p++)                    // 买入 0-2
     {
      PlotIndexSetInteger(p, PLOT_ARROW, ARROW_MARK);
      PlotIndexSetInteger(p, PLOT_LINE_WIDTH, InpArrowWidth);
      PlotIndexSetInteger(p, PLOT_ARROW_SHIFT, InpArrowShiftPx);   // 正=向下
      PlotIndexSetInteger(p, PLOT_LINE_COLOR, 0,
                          (p == 0) ? COLOR_K1 : (p == 1) ? COLOR_K2 : COLOR_K3);
     }
   for(int p = 3; p < 6; p++)                    // 卖出 3-5
     {
      PlotIndexSetInteger(p, PLOT_ARROW, ARROW_MARK);
      PlotIndexSetInteger(p, PLOT_LINE_WIDTH, InpArrowWidth);
      PlotIndexSetInteger(p, PLOT_ARROW_SHIFT, -InpArrowShiftPx);  // 负=向上
      PlotIndexSetInteger(p, PLOT_LINE_COLOR, 0,
                          (p == 3) ? COLOR_K1 : (p == 4) ? COLOR_K2 : COLOR_K3);
     }

   //--- 空值约定：没有信号的K线，6个信号缓冲填 EMPTY_VALUE（绘制时自动跳过），
   //   信号类型缓冲填 0（SIG_NONE）。PLOT_EMPTY_VALUE 告诉平台“什么值算空”。
   for(int p = 0; p < 6; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(6, PLOT_EMPTY_VALUE, 0.0);

   //--- 绘制起点：前 draw_begin 根K线属于“预热/回看不足”区域，不画信号，
   //   避免在数据不足时产生误导性的早期信号。所有 plot 都从这个起点开始。
   int draw_begin = MathMax(InpLookbackBars, InpAtrPeriod + InpCbBars);
   for(int plot = 0; plot < 7; plot++)
      PlotIndexSetInteger(plot, PLOT_DRAW_BEGIN, draw_begin);

   //--- 指标在“数据窗口”显示的短名，以及价格显示精度（位数跟随当前品种 _Digits）
   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("PinBar(%d,%d)", InpCbBars, InpLookbackBars));
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| 真实波幅 TR（True Range）                                          |
//| 单根K线的真实波幅 = 以下三个中的最大值：                           |
//|   1) 本根高点-低点，2) 高点-昨收绝对值，3) 低点-昨收绝对值。        |
//| 作用是过滤“跳空”；它也是 ATR 的基础。                              |
//+------------------------------------------------------------------+
double TrueRange(const int i, const double &high[], const double &low[],
                 const double &close[])
  {
   if(i <= 0)                                  // 最旧那根没有“昨收”，只能用高低差
      return(high[0] - low[0]);
   return(MathMax(high[i] - low[i],
                  MathMax(MathAbs(high[i] - close[i-1]),
                          MathAbs(low[i]  - close[i-1]))));
  }

//+------------------------------------------------------------------+
//| Wilder ATR（增量更新，非序列索引 0=最旧一根）                        |
//| MQL5 特性：指标每次有新K线/新tick，OnCalculate 都会重跑，           |
//| 但通过 prev_calculated 可以只重算“新增”的部分，避免每次都全量算。    |
//| 这里用 Wilder 平滑（更接近 MT 自带 ATR 的算法），而不是简单移动平均。 |
//+------------------------------------------------------------------+
void UpdateAtr(const int rates_total, const int prev_calculated,
               const double &high[], const double &low[], const double &close[])
  {
   ArrayResize(g_atr, rates_total);            // 缓冲长度跟随当前K线总数
   int period = InpAtrPeriod;
   //--- 增量起点：上次已算到 prev_calculated-1，这次从那里接着算（-1 是为了从上一根带出递归值）
   int begin  = (prev_calculated > 0) ? prev_calculated - 1 : 0;

   for(int i = begin; i < rates_total; i++)
     {
      if(i < period)                       // 前 period 根是预热期，还没有足够的TR，置 0
        {
         g_atr[i] = 0.0;
         continue;
        }
      if(i == period)                      // 首个有效值：取前 period 个 TR 的简单平均作为起点
        {
         double sum = 0.0;
         for(int j = 1; j <= period; j++)
            sum += TrueRange(j, high, low, close);
         g_atr[i] = sum / period;
         continue;
        }
      //--- Wilder 递推：新值 = (旧值×(period-1) + 当前TR) / period
      g_atr[i] = (g_atr[i-1] * (period - 1) + TrueRange(i, high, low, close)) / period;
     }
  }

//+------------------------------------------------------------------+
//| 把一根K线的信号按 k 写入对应“颜色”缓冲                              |
//| buy=true → 写入买入缓冲(存 CB 最低价)；buy=false → 写入卖出缓冲(CB 最高价)。|
//| k = CB 组合K线数(1..3)，决定写进 红(1)/桔红(2)/黄(3) 哪个缓冲，     |
//| 而图上的符号/颜色是由“绘图序列”固定设定的，所以只要价写进对了缓冲，就自动变色。|
//+------------------------------------------------------------------+
void SetDigit(const int i, const bool buy, const int k, const double price)
  {
   if(buy)
     {
      if(k == 1)      BuyDigit1[i]  = price;   // 1根 → 红
      else if(k == 2) BuyDigit2[i]  = price;   // 2根 → 桔红
      else            BuyDigit3[i]  = price;   // 3根 → 黄
     }
   else
     {
      if(k == 1)      SellDigit1[i] = price;
      else if(k == 2) SellDigit2[i] = price;
      else            SellDigit3[i] = price;
     }
  }

//+------------------------------------------------------------------+
//| 清空索引 i 上所有信号缓冲与类型                                     |
//| 等价于“把这一根K线恢复成无信号状态”，供 OnCalculate 每根K线先清再评。 |
//+------------------------------------------------------------------+
void ClearDigits(const int i)
  {
   BuyDigit1[i]  = EMPTY_VALUE;
   BuyDigit2[i]  = EMPTY_VALUE;
   BuyDigit3[i]  = EMPTY_VALUE;
   SellDigit1[i] = EMPTY_VALUE;
   SellDigit2[i] = EMPTY_VALUE;
   SellDigit3[i] = EMPTY_VALUE;
   TypeBuffer[i] = SIG_NONE;
  }

//+------------------------------------------------------------------+
//| 对已收盘K线 i 做信号评估（k = 1..n，命中即止）                        |
//| 这是核心业务逻辑：对信号K线 i，先看它自己(k=1)，          |
//| 不达标就把它与前面一根合成 CB(k=2)，再不行加一根(k=3)，依此类推。    |
//| 任一 k 通过了全部流程就给出信号并 return（不再尝试更大的 k）。       |
//+------------------------------------------------------------------+
void EvaluateBar(const int i, const int rates_total, const bool live,
                 const double &open[], const double &high[],
                 const double &low[],  const double &close[])
  {
   for(int k = 1; k <= InpCbBars; k++)
     {
      //--- 本 k 对应的 CB：从“信号K线 i 往前数 k 根”，i0 是 CB 首根
      int i0 = i - k + 1;
      //--- 合并规则见 pinbar.md 2.1：
      //   CB 开盘=首根开盘，CB 收盘=末根(信号K线)收盘，CB 高低=这一组中的最高/最低
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
         continue;                            // 流程第 1 步：一字线(高度为0)不合格，试下一个 k

      //--- 流程第 2 步：ATR 过滤。
      //   ATR比例 = CB高度 / CB 中每根K线的ATR平均值。
      //   比例太小说明这根CB太“短小”，没有变形意义，舍弃。
      double atrAvg = 0.0;
      for(int j = i0; j <= i; j++)
         atrAvg += g_atr[j];
      atrAvg /= k;
      if(atrAvg <= 0.0)
         continue;                            // ATR 未准备好(预热期)，跳过该 k
      double atrRatio = cbHeight / atrAvg;
      if(atrRatio < InpMinAtrPct / 100.0)
         continue;

      //--- 流程第 3 步：形态判定（先判 pinbar，再判十字星；两者都成立按 pinbar 算）
      double headThr = InpMaxHeadPct / 100.0;          // 锤头比例阈值
      if(InpHeadWeighted)                              // 加权：阈值 × ATR比例的平方根，上限50%
         headThr = MathMin(headThr * MathSqrt(atrRatio), 0.50);

      //--- 拆出实体、上/下影线（相对 CB 的开收盘）
      double body  = MathAbs(cbClose - cbOpen);                 // 实体=开收盘差
      double upper = cbHigh - MathMax(cbOpen, cbClose);         // 上影线
      double lower = MathMin(cbOpen, cbClose) - cbLow;          // 下影线
      //   锤头=实体+较短影线；锤头比例=锤头/CB高度。越小说明“针”越突出，越是pinbar。
      bool isPin  = (body + MathMin(upper, lower)) / cbHeight <= headThr;
      //   十字星：实体比例很小（开盘≈收盘）
      bool isDoji = body / cbHeight <= InpMaxDojiBodyPct / 100.0;
      if(!isPin && !isDoji)
         continue;

      //--- 流程第 4 步：位置判定——CB 的极值必须是回看窗口 m 的极值才合格。
      //   回看窗口：以信号K线 i 为最后一根、往回数 m 根(含CB占用的那几根)。
      int    w0    = i - InpLookbackBars + 1;
      double wLow  = low[w0];
      double wHigh = high[w0];
      for(int j = w0 + 1; j <= i; j++)
        {
         if(low[j]  < wLow)  wLow  = low[j];
         if(high[j] > wHigh) wHigh = high[j];
        }
      //   窗口包含CB自身，所以 cbLow==wLow 就是“CB是最低点”；用 ≤ 等价处理并列。
      bool lowExtreme  = (cbLow  <= wLow);
      bool highExtreme = (cbHigh >= wHigh);

      //--- 根据形态，决定买入/卖出：
      //   · pinbar：针在下(下影线≥上影线)且是低点 → 买；针在上且是高点 → 卖（等长则两侧都判）
      //   · 十字星：低点极值→买，高点极值→卖（可同时）
      bool buy  = false;
      bool sell = false;
      if(isPin)
        {
         if(lower >= upper && lowExtreme)  buy  = true;  // 底 pinbar：针在下
         if(upper >= lower && highExtreme) sell = true;  // 顶 pinbar：针在上
        }
      else
        {
         if(lowExtreme)  buy  = true;           // 十字星低点极值 → 买
         if(highExtreme) sell = true;           // 十字星高点极值 → 卖（可与上面同时）
        }
      if(!buy && !sell)
         continue;                            // 位置不合格，继续试下一个 k

      //--- 流程第 5 步：写入信号缓冲（图上据此画符号）并记录信号类型。
      //   符号统一是 ●；颜色由 k 决定（1红/2桔红/3黄，由 plot 序列颜色自动呈现）。
      //   买入价写进“买入”缓冲 → 符号画在 CB 最低价下方；卖出写进“卖出”缓冲 → 画在上方。
      if(buy)
         SetDigit(i, true,  k, cbLow);
      if(sell)
         SetDigit(i, false, k, cbHigh);
      //--- 信号类型写进 TypeBuffer 供 EA 读取（SIG_* 编码见文件头）
      TypeBuffer[i] = isPin ? (buy && sell ? SIG_PIN_BOTH
                                           : (buy ? SIG_BOTTOM_PIN : SIG_TOP_PIN))
                            : SIG_DOJI;

      //--- 报警（预留功能：取消本段与文件头部 InpAlerts 的注释即可启用）
      // if(live && InpAlerts)
      //    Alert(_Symbol, " ", EnumToString(Period()), ": PinBar ",
      //          buy && sell ? "BUY+SELL 双向" : (buy ? "BUY" : "SELL"),
      //          " @ ", DoubleToString(cbClose, _Digits));

      return;                                   // 跨 k 命中即止：本K线已完成，不再试更大的 k
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
      ArrayInitialize(BuyDigit1,  EMPTY_VALUE);
      ArrayInitialize(BuyDigit2,  EMPTY_VALUE);
      ArrayInitialize(BuyDigit3,  EMPTY_VALUE);
      ArrayInitialize(SellDigit1, EMPTY_VALUE);
      ArrayInitialize(SellDigit2, EMPTY_VALUE);
      ArrayInitialize(SellDigit3, EMPTY_VALUE);
      ArrayInitialize(TypeBuffer, SIG_NONE);
      start = MathMax(warmup, rates_total - 1 - InpMaxBars);   // 2.8：只算最近 InpMaxBars 根
     }
   else
      start = MathMax(prev_calculated - 1, warmup);

   for(int i = start; i <= rates_total - 2; i++)
     {
      ClearDigits(i);
      EvaluateBar(i, rates_total, prev_calculated > 0, open, high, low, close);
     }

   //--- 正在形成的K线保持空值
   ClearDigits(rates_total - 1);

   return(rates_total);
  }
//+------------------------------------------------------------------+
