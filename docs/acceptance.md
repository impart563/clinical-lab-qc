# 项目验收证据

本文件是对照 [2026 MoonBit 黑客松公开页面](https://moonbitlang.github.io/Hackathon2026/)整理的自查表，核对日期为 2026-09-25。它不代表赛事官方审核结论，实际以赛事群及官方通知为准。

| 公开验收项 | 仓库证据 | 复现方式 |
| --- | --- | --- |
| MoonBit 为主要实现语言 | 核心模型、规则、回放、报告渲染器和 CLI 均为 .mbt 包 | **moon check --deny-warn --target all** |
| 仓库公开且开发记录可追踪 | [GitHub 仓库](https://github.com/impart563/clinical-lab-qc)、提交历史和 CHANGELOG.md | 检查提交分支的真实增量 |
| 项目能够运行，有 README 和示例 | README.md、examples/quickstart、cmd/demo | **moon run --target native examples/quickstart** |
| 已有项目包含本期实质新增 | 分析项目 JSON 配置、JSON/CSV/Markdown/HTML 审计报告、SVG 图表、场景验收测试和公开 API 示例 | 运行验收脚本并查看对应提交 |
| 开源合规 | LICENSE（Apache-2.0）、moon.mod、docs/rule-semantics.md 中的来源说明 | 提交前复查依赖许可证和来源声明 |
| 参赛者能解释技术选择与质量 | docs/design-decisions.md、源码、测试和公开 API 接口 | 说明整数精度、阶段重置、缺失值、证据与报告生成 |
| 项目验收材料可复现 | 源码、README、测试和三个演示场景 | **python scripts/acceptance.py** |

验收脚本会检查所有支持的 MoonBit 目标，构建 native CLI，运行测试和公开 quickstart；对三个演示场景核对预期结果；重复运行 Markdown、JSON、CSV、SVG、HTML 并比较输出；检查 JSON/CSV/HTML 统计一致性、HTML 内嵌 SVG 可解析且无外部资源、状态/阶段/证据导航链接均指向运行记录、CSV 预检文本和 JSON 结果、行列诊断、缺失控制警告、质控信号与输入有效性的分离、HTML/JSON 文件写入和失败路径处理、CLI 错误处理，最后构建 Moon package 归档。

当前公开的黑客松页面没有列出提交数量下限或 Mooncakes 发布要求。项目计划书引用的飞书章程提到了这些更严格条件，应先向赛事群核实再将其当作硬门槛。OSC2026 是另一场赛事，其要求不能自动套用到本场。

仓库无法证明参赛者已报名、通过资格审核或加入赛事群；这些步骤须在官方流程中完成。若报名表要求一页项目说明，应通过官方入口另行提交。

## 演示场景契约

| 场景 | 预期结果 |
| --- | --- |
| stable | 12 次运行、1 个阶段、全部 InControl、0 条规则命中 |
| step-shift | 12 次运行、两个阶段各 6 次、全部 InControl、0 条规则命中；每个控制水平面板都显示阶段边界 |
| gradual-drift | 12 次运行、1 个阶段；6 次 InControl、6 次 RequiresReview；共 9 条命中（1_2s 为 1、4_1s 为 6、10x 为 2），SVG 显示对应证据标记 |

所有演示值均为合成数据。规则命中是复核信号，不是患者结果放行决定。
