# clinical-lab-qc：MoonBit 临床检验室内质控分析与回放库

**申报人：翁佳浩｜项目类型：独立 MoonBit 实现（新生态项目）｜许可证：Apache-2.0**

本项目将临床检验室内质控数据组织为可回放轨迹，确定性检测规则，并保留触发信号的运行、控制水平、数值和阈值证据。规则术语参考 [Westgard 多规则质控说明](https://www.westgard.com/westgard-rules.html)，仅参考规则概念，不移植其代码。

试剂、控制品批号和校准变化会改变数据的可比边界；单个超限值也不足以表达完整复核过程。项目为 MoonBit 提供可嵌入的分析库与离线 CLI，覆盖 `1_2s`、`1_3s`、`2_2s`、`R_4s`、`4_1s`、`10x` 规则、CSV 诊断和 Markdown、JSON、CSV、SVG、HTML 审阅输出。

**生态定位：**2026-09-26 检索 Mooncakes 时发现 [`moonbitSPC`](https://mooncakes.io/docs/mwqcodex/moonbitSPC) 聚焦制造业 SPC，公开列有控制图及 Western Electric 规则；[`moonbit-ocean-qc`](https://mooncakes.io/docs/lwq443/moonbit-ocean-qc) 面向海洋观测质控。本项目聚焦临床检验室内质控的数据模型与复核轨迹：显式记录分析项目、控制水平和批号/校准阶段快照，以定精度整数计算并输出可复核证据。此定位说明项目的专业范围，不假定相邻项目缺少未核实的能力。

| 使用者与场景 | 输入与操作 | 可检查结果 |
| --- | --- | --- |
| 检验人员复核常规批次 | 配置均值、标准差和控制水平，回放 12 次稳定合成运行 | 12 次均为 `InControl`、无规则命中；重复运行结果一致 |
| 检验人员处理批号或校准切换 | 提供两个 `QCEpoch` 的有序运行并回放 | 报告呈现两个阶段；新阶段的跨运行窗口不拼接旧阶段数据 |
| 复核人员调查渐进漂移 | 运行 `gradual-drift`，查看 HTML 或 JSON 报告 | 显示规则、运行、控制水平、观测值、阈值和方向，并可跳转至证据运行 |

技术取舍：阈值比较使用定精度缩放整数；阶段快照界定历史窗口；输入保持原顺序，不自动排序；缺失值不插补并打断对应窗口；规则检测与复核状态分离。这些选择使边界变化和信号来源可复算、可解释。

项目只处理合成或实验室提供的质控数据，不保存患者信息、不连接仪器或医院系统、不作诊断、不替代实验室 SOP，也不自动放行患者结果。默认策略和示例数值不是临床操作限值，实际规则由实验室审核。

**仓库与复现：**[github.com/impart563/clinical-lab-qc](https://github.com/impart563/clinical-lab-qc)；运行 `python scripts/acceptance.py` 验证测试、下游 API 消费及三个演示场景。规则边界与实现限制见 `docs/rule-semantics.md`。
