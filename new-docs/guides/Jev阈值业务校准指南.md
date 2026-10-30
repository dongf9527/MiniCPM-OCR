# Jev 阈值业务校准指南

| 项目 | 内容 |
|---|---|
| 目的 | 在自有业务样本上标定 Jev 分数阈值 t*:score ≥ t* 自动通过(免检),否则转人工复核 |
| 前置 | 实机 23 号评分服务在线(`:18500/healthz`);一批人工标注样本;`41_jev_threshold_report.py` |
| 方法来源 | 官方三步法(采样标注 → 多阈值统计 → 按业务容错线定阈值),深度评估报告 §3.4/§10.1 |
| 关联 | `workspace/deploy-16g/41_jev_threshold_report.py`、评估记录 §5 #5 |

## 1. 校准在解决什么问题

Jev 对每个识别区域输出 0–1 分与 `verdict`。业务侧需要一条线:**高于阈值自动入库,低于阈值进人工队列**。官方明确两点:

1. **分数是排序信号(AUROC 口径),不是校准过的正确概率**——"0.85"不能直接读作"85% 正确",不能直接当置信度用;
2. **阈值必须在自己业务样本上标注校准**,解析器或文档分布改变后应重新验证。

校准的本质:测出本业务分布下"分数-正确率"的真实关系,再按业务容错线(免检区允许的错误率上限)反推阈值。

## 2. 三条铁律

1. **只认 `verdict=scored` 的分数**。`precheck_reject`(如 LaTeX 语法坏)/`render_error` 固定返回 0.0,`encode_error`/`forward_error` 返回 -1.0——都是错误态,不是"低分",业务上直接转人工,**不参与阈值统计**;
2. **阈值绑定"文档分布 + 解析器"组合**。换文档类型、换 OCR 引擎、换模型版本,任一变化都触发重校;
3. **标注质量决定校准质量**。`correct` 必须逐块对照原图人工判定;半角/全角、标点、空格、表格数字进位的判定口径要先定义成文。

## 3. 第一步:采样与标注

**样本规模**:每类文档(合同/票据/报表等)≥ 30 块,总量 100–300 块起步;`text`/`formula`/`table` 分开统计;难度分布贴近真实业务(拍歪、模糊、印章遮挡、手写都要有)。

**产出**:JSONL,每行一个标注样本(字段契约,41 号即按此读取):

```json
{"case_id":"contract01#b3", "category":"text", "score":0.97, "verdict":"scored", "correct":true}
```

**分数采集两条路径**(任选,可并用):

**路径 A——直连评分服务(推荐,与 OCR 解耦)**。把"区域原图 + 候选文本"直接 POST 给 23 号服务(`/v1/rm/score`,服务端自动渲染 ternary 三元组;三接口粒度:`/v1/rm/score`、`/v1/rm/score_best`、`/v1/rm/score_best_batch`):

```bash
# item 字段:image=原图 b64(PNG/JPEG), ocr_text=候选文本, category=text|formula|table
python3 - <<'PY'
import base64, json, urllib.request
items = []
for img, text, cat, cid in samples:            # 你的标注清单
    items.append({
        "case_id": cid,
        "image": base64.b64encode(open(img, "rb").read()).decode(),
        "ocr_text": text, "category": cat,
    })
req = urllib.request.Request("http://127.0.0.1:18500/v1/rm/score",
    data=json.dumps({"input_form": "ternary", "items": items}).encode(),
    headers={"Content-Type": "application/json"})
resp = json.load(urllib.request.urlopen(req))
with open("scores.jsonl", "w", encoding="utf-8") as fh:
    for it in resp["items"]:                    # 每项含 score/verdict/category/case_id
        fh.write(json.dumps({**it, "correct": LABELS[it["case_id"]]}, ensure_ascii=False) + "\n")
PY
```

路径 A 的候选文本不必来自 1.0 引擎——同一套流程可以给任意解析器(GLM-OCR、PaddleOCR-VL 等)的输出打分,用于跨解析器对比。

**路径 B——全链路采集**。样本文档走 40 号,从中间产物提取:

```bash
JEV_ENABLED=true JEV_FORCE_SCORE=true bash 40_parse.sh <样本.pdf> ./out-calib
# 从 run_dir 提取:workspace/runs/minicpmvocr_parse_<名>_<时间戳>/results_json/*.json
# 各块的 result_block.tts 含 scores/verdicts 与 label;与人工标注按块对齐后写 scores.jsonl
```

## 4. 第二步:阈值扫描(41 号工具)

```bash
cd ~/sourcecode/minicpm-ocr/workspace/deploy-16g
python3 41_jev_threshold_report.py scores.jsonl --target-err 0.005
python3 41_jev_threshold_report.py scores.jsonl --target-err 0.005 --by-category
```

输出示例(合成数据,仅演示格式):

```
== 全部样本 ==  样本 12(其中错误 3,错误率 25.00%)
  阈值    免检率   免检错误  免检准确率  拦下错误  误拦正确
  0.86   50.00%        1     83.33%        2        4
  0.88   41.67%        0    100.00%        3        4  <-- 建议
建议阈值 t* = 0.88(免检率 41.67%,免检准确率 100.00%,免检错误 0 个)
```

五列含义:**免检率**=自动通过占比(人工复核量的节省);**免检错误**=放过去的错误(业务风险);**免检准确率**=免检区正确率;**拦下错误**=人工兜住的成本;**误拦正确**=被多拦的正确块(复核成本虚高)。`--t-min/--t-max/--t-step` 可在 t* 附近加密网格精扫。

## 5. 第三步:定阈值并落地

**决策规则**:给定业务容错线(免检区错误率上限,如财税场景 0.5%),**t* = 满足容错线的最小阈值**(此时免检率最大)。官方免检曲线的两个方向都在手里:降 t* 多免检但错误率升,升 t* 更稳但复核量增;按业务容错线取舍,不要照抄别人的数。

**落地位置(三层,职责不同)**:

| 层 | 位置 | 说明 |
|---|---|---|
| 业务门控(主) | 下游消费端:读 40 号 run_dir 的 `results_json`(各块 `tts.scores/verdicts`)或自建评分调用,按 t* 分流"入库/转人工" | SDK 与部署包不含此层,需业务侧实现;`verdict != scored` 一律转人工 |
| 生成期早停(可选成本优化) | 40 号加 `--set tts.adaptive.enabled=true --set tts.adaptive.tau=<t*>` | best_score ≥ tau 即停止加采样轮,省质检耗时;tau 是停止规则,与业务阈值语义不同,可先用同值起步再独立标定 |
| 服务端 summary | `/v1/rm/score` 响应内按 thr 的统计 | 仅汇报用,不作为门控依据 |

**持久化**:把 t* 写入 `workspace/deploy-16g/env.local.sh`(如 `JEV_THRESHOLD=0.93`)供业务脚本取用;校准结论按下方模板记入 `new-docs/records/`。

## 6. 何时重新校准

- 更换/升级解析引擎(含 1.0 → 量化版权重切换);
- 业务文档类型或分布变化(新合同模板、新票种);
- Jev 模型版本升级;
- 抽检发现免检区错误率逼近/超过容错线(建议线上持续抽检 1–5%)。

## 7. 校准记录模板

| 项目 | 内容 |
|---|---|
| 日期 / 执行人 | |
| 样本集 | 来源系统、文档类型、块数(按 text/formula/table 分列)、标注口径文档链接 |
| 采集路径 | A(直连)/ B(全链路),run_dir 或请求批次 |
| 容错线与结果 | target-err、t*(分类目)、免检率、免检准确率 |
| 生效范围 | 阈值写入位置(env.local.sh / 业务门控版本) |
| 备注 | 非 scored 占比、异常 case、下次重校触发条件 |
