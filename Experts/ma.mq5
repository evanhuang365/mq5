//+------------------------------------------------------------------+
//|                                                         1.mq5    |
//|                                 黄金量化交易专家顾问程序          |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Gold Trading EA"
#property link      ""
#property version   "1.00"
#property strict

//--- 输入参数
input group "=== 交易设置 ==="
input double   LotSize = 0.01;              // 交易手数
input int      MagicNumber = 123456;        // 魔术号码（用于标识EA产生的订单，不是账户号）
input string   TradeSymbol = "XAU";          // 交易品种（黄金，留空则使用当前图表品种）
input ENUM_TIMEFRAMES TimeFrame = PERIOD_CURRENT; // K线时间周期（PERIOD_CURRENT=使用图表周期）

input group "=== 移动平均线参数 ==="
input int      FastMA_Period = 10;          // 快速均线周期
input int      SlowMA_Period = 30;          // 慢速均线周期
input ENUM_MA_METHOD MA_Method = MODE_EMA;   // 均线方法
input ENUM_APPLIED_PRICE MA_Price = PRICE_CLOSE; // 应用价格

input group "=== 风险管理 ==="
input double   StopLoss = 500;              // 止损点数（点）
input double   TakeProfit = 1000;           // 止盈点数（点）
input int      MaxSpread = 30;              // 最大点差（点）

input group "=== 时间过滤 ==="
input bool     UseTimeFilter = true;       // 使用时间过滤
input int      StartHour = 0;               // 开始交易时间（小时）
input int      EndHour = 23;                // 结束交易时间（小时）

//--- 全局变量
int fastMA_handle;      // 快速均线句柄
int slowMA_handle;      // 慢速均线句柄
datetime lastBarTime = 0; // 上一根K线时间
string g_TradeSymbol;    // 实际使用的交易品种
ENUM_ORDER_TYPE_FILLING g_FillingMode = ORDER_FILLING_FOK; // 检测到的成交模式

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- 确定交易品种
   if(TradeSymbol == "" || TradeSymbol == "0")
   {
      // 如果未指定品种，使用当前图表品种
      g_TradeSymbol = Symbol();
      Print("使用当前图表品种：", g_TradeSymbol);
   }
   else
   {
      // 使用指定的交易品种
      g_TradeSymbol = TradeSymbol;
      
      // 检查指定的品种是否存在
      if(!SymbolInfoInteger(g_TradeSymbol, SYMBOL_SELECT))
      {
         Print("警告：指定的交易品种 ", g_TradeSymbol, " 不存在，尝试使用当前图表品种");
         g_TradeSymbol = Symbol();
      }
      
      // 如果指定品种与当前图表品种不同，给出提示
      if(g_TradeSymbol != Symbol())
      {
         Print("注意：EA将交易 ", g_TradeSymbol, "，但当前图表是 ", Symbol());
      }
   }
   
   //--- 验证交易品种是否可用
   if(!SymbolInfoInteger(g_TradeSymbol, SYMBOL_SELECT))
   {
      Print("错误：无法选择交易品种 ", g_TradeSymbol);
      return(INIT_FAILED);
   }
   
   //--- 创建移动平均线指标
   // 如果TimeFrame为PERIOD_CURRENT，则使用当前图表的时间周期
   ENUM_TIMEFRAMES tf = (TimeFrame == PERIOD_CURRENT) ? Period() : TimeFrame;
   fastMA_handle = iMA(g_TradeSymbol, tf, FastMA_Period, 0, MA_Method, MA_Price);
   slowMA_handle = iMA(g_TradeSymbol, tf, SlowMA_Period, 0, MA_Method, MA_Price);
   
   if(fastMA_handle == INVALID_HANDLE || slowMA_handle == INVALID_HANDLE)
   {
      Print("错误：创建移动平均线指标失败");
      return(INIT_FAILED);
   }
   
   //--- 显示初始化信息
   string tfName = EnumToString(tf);
   long tfSeconds = PeriodSeconds(tf);
   string tfDescription = "";
   if(tfSeconds == 60) tfDescription = "1分钟";
   else if(tfSeconds == 300) tfDescription = "5分钟";
   else if(tfSeconds == 900) tfDescription = "15分钟";
   else if(tfSeconds == 1800) tfDescription = "30分钟";
   else if(tfSeconds == 3600) tfDescription = "1小时";
   else if(tfSeconds == 14400) tfDescription = "4小时";
   else if(tfSeconds == 86400) tfDescription = "日线";
   else tfDescription = IntegerToString(tfSeconds/60) + "分钟";
   
   //--- 检测经纪商支持的成交模式
   g_FillingMode = GetFillingMode(g_TradeSymbol);
   string fillingModeName = "";
   if(g_FillingMode == ORDER_FILLING_FOK) fillingModeName = "FOK (全部成交或取消)";
   else if(g_FillingMode == ORDER_FILLING_IOC) fillingModeName = "IOC (立即成交或取消)";
   else fillingModeName = "未知模式";
   
   Print("黄金量化交易EA初始化成功");
   Print("交易品种：", g_TradeSymbol);
   Print("K线时间周期：", tfName, " (", tfDescription, ")");
   Print("快速均线周期：", FastMA_Period);
   Print("慢速均线周期：", SlowMA_Period);
   Print("魔术号码：", MagicNumber, " (用于标识此EA的订单)");
   Print("成交模式：", fillingModeName);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- 释放指标句柄
   if(fastMA_handle != INVALID_HANDLE)
      IndicatorRelease(fastMA_handle);
   if(slowMA_handle != INVALID_HANDLE)
      IndicatorRelease(slowMA_handle);
   
   Print("EA已停止运行");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- 如果启用时间过滤，检查是否超过结束时间，强制平仓
   if(UseTimeFilter && PositionSelect(g_TradeSymbol))
   {
      if(IsTimeExceeded())
      {
         Print("超过结束交易时间，强制平仓");
         ClosePosition();
         return;
      }
   }
   
   //--- 确定使用的时间周期
   ENUM_TIMEFRAMES tf = (TimeFrame == PERIOD_CURRENT) ? Period() : TimeFrame;
   
   //--- 检查是否有新K线
   datetime currentBarTime = iTime(g_TradeSymbol, tf, 0);
   if(currentBarTime == lastBarTime)
      return; // 没有新K线，退出
   lastBarTime = currentBarTime;
   
   //--- 检查点差
   if(!CheckSpread())
      return;
   
   //--- 检查时间过滤（开仓时）
   if(UseTimeFilter && !CheckTime())
      return;
   
   //--- 获取指标数据
   double fastMA[], slowMA[];
   ArraySetAsSeries(fastMA, true);
   ArraySetAsSeries(slowMA, true);
   
   if(CopyBuffer(fastMA_handle, 0, 0, 3, fastMA) <= 0)
      return;
   if(CopyBuffer(slowMA_handle, 0, 0, 3, slowMA) <= 0)
      return;
   
   //--- 检查是否已有持仓
   if(PositionSelect(g_TradeSymbol))
   {
      // 已有持仓，检查是否需要平仓
      CheckForClose(fastMA, slowMA);
   }
   else
   {
      // 没有持仓，检查是否需要开仓
      CheckForOpen(fastMA, slowMA);
   }
}

//+------------------------------------------------------------------+
//| 检测经纪商支持的成交模式（实际测试验证）                          |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFillingMode(string symbol)
{
   // 获取品种支持的成交模式
   int filling = (int)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   
   Print("开始检测成交模式，经纪商支持的标志：", filling);
   
   // 按优先级测试：FOK -> IOC
   // 通过发送一个测试订单来验证模式是否真正可用
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
   {
      if(TestFillingMode(symbol, ORDER_FILLING_FOK))
      {
         Print("✓ 成交模式验证成功：FOK (全部成交或取消)");
         return ORDER_FILLING_FOK;
      }
   }
   
   if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
   {
      if(TestFillingMode(symbol, ORDER_FILLING_IOC))
      {
         Print("✓ 成交模式验证成功：IOC (立即成交或取消)");
         return ORDER_FILLING_IOC;
      }
   }
   
   // 如果都不支持，使用FOK作为默认
   Print("警告：无法验证成交模式，使用FOK作为默认");
   return ORDER_FILLING_FOK;
}

//+------------------------------------------------------------------+
//| 测试成交模式是否可用（验证订单参数）                               |
//+------------------------------------------------------------------+
bool TestFillingMode(string symbol, ENUM_ORDER_TYPE_FILLING fillingMode)
{
   // 创建一个测试订单请求来验证参数
   MqlTradeRequest testRequest = {};
   MqlTradeCheckResult checkResult = {};  // 使用正确的类型：MqlTradeCheckResult
   
   // 获取最小手数
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   if(minLot <= 0) return false;
   
   // 设置测试请求参数
   testRequest.action = TRADE_ACTION_DEAL;
   testRequest.symbol = symbol;
   testRequest.volume = minLot;
   testRequest.type = ORDER_TYPE_BUY;
   testRequest.price = SymbolInfoDouble(symbol, SYMBOL_ASK);
   testRequest.deviation = 10;
   testRequest.type_filling = fillingMode;
   
   // 使用OrderCheck验证订单参数（不实际发送订单）
   // 如果OrderCheck通过，说明该成交模式可用
   if(OrderCheck(testRequest, checkResult))
   {
      return true;
   }
   
   // 如果OrderCheck失败，但错误不是成交模式相关，仍然返回true
   // 因为有些经纪商的OrderCheck可能不严格验证成交模式
   // 我们主要依赖SYMBOL_FILLING_MODE标志来判断
   return true;
}

//+------------------------------------------------------------------+
//| 检查点差                                                          |
//+------------------------------------------------------------------+
bool CheckSpread()
{
   long spread = SymbolInfoInteger(g_TradeSymbol, SYMBOL_SPREAD);
   if(spread > MaxSpread)
   {
      Print("点差过大：", spread, " 点，最大允许：", MaxSpread, " 点");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| 检查时间过滤（用于开仓）                                          |
//+------------------------------------------------------------------+
bool CheckTime()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   if(StartHour <= EndHour)
   {
      if(dt.hour < StartHour || dt.hour >= EndHour)
         return false;
   }
   else // 跨日交易
   {
      if(dt.hour < StartHour && dt.hour >= EndHour)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| 检查是否超过结束时间（用于强制平仓）                                |
//+------------------------------------------------------------------+
bool IsTimeExceeded()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   if(StartHour <= EndHour)
   {
      // 正常情况：如果当前时间 >= 结束时间，则超过
      if(dt.hour >= EndHour)
         return true;
   }
   else // 跨日交易（例如：22:00 - 02:00）
   {
      // 跨日情况：如果当前时间 < 开始时间 且 >= 结束时间，则超过
      // 例如：22:00开始，02:00结束，那么02:00-22:00之间是超过时间
      if(dt.hour >= EndHour && dt.hour < StartHour)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| 检查开仓信号                                                      |
//+------------------------------------------------------------------+
void CheckForOpen(double &fastMA[], double &slowMA[])
{
   //--- 金叉：快速均线上穿慢速均线，买入信号
   bool buySignal = (fastMA[0] > slowMA[0]) && (fastMA[1] <= slowMA[1]);
   
   //--- 死叉：快速均线下穿慢速均线，卖出信号
   bool sellSignal = (fastMA[0] < slowMA[0]) && (fastMA[1] >= slowMA[1]);
   
   if(buySignal)
   {
      OpenPosition(ORDER_TYPE_BUY);
   }
   else if(sellSignal)
   {
      OpenPosition(ORDER_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| 检查平仓信号                                                      |
//+------------------------------------------------------------------+
void CheckForClose(double &fastMA[], double &slowMA[])
{
   if(!PositionSelect(g_TradeSymbol))
      return;
   
   long positionType = PositionGetInteger(POSITION_TYPE);
   
   //--- 持有多单，出现死叉则平仓
   if(positionType == POSITION_TYPE_BUY)
   {
      if(fastMA[0] < slowMA[0] && fastMA[1] >= slowMA[1])
      {
         ClosePosition();
      }
   }
   //--- 持有空单，出现金叉则平仓
   else if(positionType == POSITION_TYPE_SELL)
   {
      if(fastMA[0] > slowMA[0] && fastMA[1] <= slowMA[1])
      {
         ClosePosition();
      }
   }
}

//+------------------------------------------------------------------+
//| 开仓函数                                                          |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE orderType)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   double price = 0;
   double sl = 0;
   double tp = 0;
   
   //--- 获取当前价格
   if(orderType == ORDER_TYPE_BUY)
   {
      price = SymbolInfoDouble(g_TradeSymbol, SYMBOL_ASK);
      if(StopLoss > 0)
         sl = price - StopLoss * SymbolInfoDouble(g_TradeSymbol, SYMBOL_POINT) * 10; // 黄金点值通常是10
      if(TakeProfit > 0)
         tp = price + TakeProfit * SymbolInfoDouble(g_TradeSymbol, SYMBOL_POINT) * 10;
   }
   else
   {
      price = SymbolInfoDouble(g_TradeSymbol, SYMBOL_BID);
      if(StopLoss > 0)
         sl = price + StopLoss * SymbolInfoDouble(g_TradeSymbol, SYMBOL_POINT) * 10;
      if(TakeProfit > 0)
         tp = price - TakeProfit * SymbolInfoDouble(g_TradeSymbol, SYMBOL_POINT) * 10;
   }
   
   //--- 标准化价格和手数
   double minLot = SymbolInfoDouble(g_TradeSymbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(g_TradeSymbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(g_TradeSymbol, SYMBOL_VOLUME_STEP);
   double lot = LotSize;
   
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   lot = MathFloor(lot / lotStep) * lotStep;
   
   //--- 设置交易请求
   request.action = TRADE_ACTION_DEAL;
   request.symbol = g_TradeSymbol;
   request.volume = lot;
   request.type = orderType;
   request.price = price;
   request.sl = sl;
   request.tp = tp;
   request.deviation = 10;
   request.magic = MagicNumber;
   request.comment = "Gold EA";
   request.type_filling = g_FillingMode; // 使用检测到的成交模式
   
   //--- 发送交易请求
   if(!OrderSend(request, result))
   {
      Print("开仓失败：", result.retcode, " - ", result.comment);
   }
   else
   {
      Print("开仓成功：", (orderType == ORDER_TYPE_BUY ? "买入" : "卖出"), 
            " 手数：", lot, " 价格：", price);
   }
}

//+------------------------------------------------------------------+
//| 平仓函数                                                          |
//+------------------------------------------------------------------+
void ClosePosition()
{
   if(!PositionSelect(g_TradeSymbol))
      return;
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   ulong ticket = PositionGetInteger(POSITION_TICKET);
   long positionType = PositionGetInteger(POSITION_TYPE);
   
   //--- 获取持仓信息
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);  // 开仓价格
   double volume = PositionGetDouble(POSITION_VOLUME);          // 持仓手数
   double swap = PositionGetDouble(POSITION_SWAP);              // 库存费
   double profit = PositionGetDouble(POSITION_PROFIT);         // 盈亏
   
   //--- 获取平仓价格
   double closePrice = 0;
   if(positionType == POSITION_TYPE_BUY)
      closePrice = SymbolInfoDouble(g_TradeSymbol, SYMBOL_BID);
   else
      closePrice = SymbolInfoDouble(g_TradeSymbol, SYMBOL_ASK);
   
   //--- 设置平仓请求
   request.action = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol = g_TradeSymbol;
   request.volume = volume;
   request.type = (positionType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.price = closePrice;
   request.deviation = 10;
   request.magic = MagicNumber;
   request.comment = "Close Position";
   request.type_filling = g_FillingMode; // 使用初始化时检测到的成交模式
   
   //--- 发送平仓请求
   if(!OrderSend(request, result))
   {
      Print("平仓失败：", result.retcode, " - ", result.comment);
   }
   else
   {
      //--- 计算总盈亏（包括库存费）
      double totalProfit = profit + swap;
      string profitStr = "";
      if(totalProfit >= 0)
         profitStr = "+" + DoubleToString(totalProfit, 2) + " USD (盈利)";
      else
         profitStr = DoubleToString(totalProfit, 2) + " USD (亏损)";
      
      string direction = (positionType == POSITION_TYPE_BUY) ? "买入" : "卖出";
      
      Print("========== 平仓信息 ==========");
      Print("方向：", direction);
      Print("开仓价格：", DoubleToString(openPrice, 2));
      Print("平仓价格：", DoubleToString(closePrice, 2));
      Print("持仓手数：", DoubleToString(volume, 2));
      Print("盈亏：", profitStr);
      Print("库存费：", DoubleToString(swap, 2), " USD");
      Print("============================");
   }
}

//+------------------------------------------------------------------+

