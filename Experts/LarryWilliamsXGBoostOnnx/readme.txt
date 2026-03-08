https://www.mql5.com/zh/code/68424?utm_campaign=codebase.list&utm_medium=special&utm_source=mt5terminal&utm_campaign=mql5.register&utm_source=web.installer

用户手册：拉里-威廉姆斯人工智能过滤 EA
此智能交易系统 (EA) 将经典的 Larry Williams Outside Bar 策略与 人工智能 (ONNX) 过滤器相结合。 它使用机械价格行为来寻找设置，并使用人工智能来预测成功交易的概率。

1.文件准备（至关重要）
为使 EA 正确初始化， 您必须将预训练的机器学习模型放在正确的目录中：

文件名： larry_model.onnx （或输入中指定的名称）。

路径： MQL5 > 文件 > larry_model.onnx

要求： 如果该文件夹中缺少该文件 ，EA 将无法启动 ( INIT_FAILED) 。


2.输入参数
参数	说明
输入魔法	EA 的唯一 ID，用于管理自己的交易而不影响其他交易。
输入手数	开仓量（例如 0.5 手）。
InpRR	风险/收益比。如果设置为 1.5，止盈将是止损距离的 1.5 倍。
模型名称	Files 文件夹中 ONNX 文件的确切名称。
输入阈值	AI 置信度（0.0 至 1.0）。只有当 AI 概率高于该值（例如 0.6 = 60%）时，EA 才会进行交易。
输入真实范围周期	作为 AI 数据特征之一的平均真实范围 (ATR) 的周期。


3.交易逻辑和策略
第 1 阶段：机械检测
在每个新的柱状图开盘时，EA 都会检查是否出现 "外部柱状图"（当前蜡烛图的最高点高于前一个柱状图，最低点低于前一个柱状图）。

看涨信号： 价格收盘价高于前一个柱形的最高价。

看跌信号： 价格收盘低于前一个柱形的低点。

第二阶段：AI 验证
如果检测到 Outside Bar，EA 将提取10 个数据特征（体量大小、相对范围、ATR、成交量变化、星期几、小时等）并将其发送至 larry_model.onnx 模型。

如果类别 1（买入）的 AI 概率大于 InpThreshold，则 EA 执行买入。

如果类别 2（卖出）的人工智能概率 > InpThreshold，则 EA 执行卖出。

第 3 阶段：交易管理
止损 (SL)： 设置在信号蜡烛的低点（买入）或高点（卖出）。

止盈 (TP)： 根据 InpRR 比率自动计算。

频率： EA一次 只允许打开一个仓位。



4.ONNX 模型的技术要求
如果使用 Python（Scikit-Learn、PyTorch 等）训练模型，请确保输出符合 EA 要求：

输入形状：{1, 10} （10 个特征）。

输出节点 0： 预测标签（长）。

输出节点 1： 概率（包含 3 个类别的浮点数组：[中性、买入、卖出]）。

特征顺序： 必须按照 CalculateFeatures 函数中定义的顺序输入数据（体型、相对范围、牛/熊标志、ATR、相对 ATR、日、小时、成交量变化、前方向）。



5.如何部署和自我培训
解压缩 larry_william.zip

运行命令 pip install -r requirements.txt

首先打开 metatrader 5

运行 python download_csv_metatrader5.py

运行 python train_larry_williams.py

运行 python convert_onnx_larry.py