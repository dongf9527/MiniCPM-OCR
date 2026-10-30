#!/usr/bin/env python3
"""41 — Jev 阈值校准报告:对标注样本集做阈值扫描,输出"免检率-免检准确率"曲线与建议阈值。

官方三步法(深度评估报告 §3.4/§10.1)的第三步工具化:
  采样标注 → 提交评分 → 多阈值统计"自动通过率 × 通过准确率" → 按业务容错线定阈值。

输入:JSONL,每行一个标注样本(UTF-8):
  {"case_id":"doc1#b3", "category":"text", "score":0.97, "verdict":"scored", "correct":true}
  score/verdict 来自评分服务(40 号 run_dir 的 results_json,或直连 /v1/rm/score 的响应);
  correct 为人工标注:true=候选文本与原图比对无误,false=有错。
verdict != "scored" 的样本(precheck_reject / render_error / encode_error / forward_error)
不参与阈值统计——它们不是低分,单列后应全部转人工。

用法:
  python3 41_jev_threshold_report.py scores.jsonl
  python3 41_jev_threshold_report.py scores.jsonl --target-err 0.005
  python3 41_jev_threshold_report.py scores.jsonl --by-category
  python3 41_jev_threshold_report.py scores.jsonl --t-min 0.6 --t-max 0.99 --t-step 0.01

参数:
  --target-err X   业务容错线:免检区允许的错误率上限(默认 0.005,即 0.5%)。
                   建议阈值 = 满足该线的最小阈值(免检率最大)。
  --by-category    按 category 分组分别扫描(各类文档分布差异大时使用)。
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

VALID_CATEGORIES = {"text", "formula", "table"}


def load_samples(path: Path):
    scored, unscored, bad = [], Counter(), 0
    with path.open(encoding="utf-8") as fh:
        for lineno, line in enumerate(fh, 1):
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError as exc:
                bad += 1
                print(f"!! 第 {lineno} 行不是合法 JSON,已跳过({exc})", file=sys.stderr)
                continue
            verdict = str(rec.get("verdict", ""))
            if verdict != "scored":
                unscored[verdict or "(空)"] += 1
                continue
            try:
                score = float(rec["score"])
                correct = bool(rec["correct"])
            except (KeyError, TypeError, ValueError):
                bad += 1
                print(f"!! 第 {lineno} 行缺 score/correct 或类型错误,已跳过", file=sys.stderr)
                continue
            scored.append({
                "case_id": str(rec.get("case_id", f"line{lineno}")),
                "category": str(rec.get("category", "text")),
                "score": score,
                "correct": correct,
            })
    return scored, unscored, bad


def sweep(samples, t_min: float, t_max: float, t_step: float, target_err: float):
    """返回 (阈值扫描行列表, 建议阈值)。每行: (t, 免检率, 免检错误数, 免检准确率, 拦下错误数, 误拦截数)"""
    n = len(samples)
    rows = []
    steps = max(1, round((t_max - t_min) / t_step))
    ts = [round(t_min + i * t_step, 4) for i in range(steps + 1)]
    if ts and abs(ts[-1] - t_max) > 1e-9:
        ts.append(t_max)
    best_t = None
    for t in ts:
        acc = [s for s in samples if s["score"] >= t]
        rej = [s for s in samples if s["score"] < t]
        acc_err = sum(1 for s in acc if not s["correct"])
        acc_rate = (len(acc) / n) if n else 0.0
        acc_precision = (1.0 - acc_err / len(acc)) if acc else None
        rows.append((t, acc_rate, acc_err, acc_precision,
                     sum(1 for s in rej if not s["correct"]),
                     sum(1 for s in rej if s["correct"])))
        if best_t is None and acc_precision is not None \
                and acc_precision >= 1.0 - target_err:
            best_t = t  # 免检率随阈值单调递减,最小满足阈值即免检率最大;曲线仍全量输出
    return rows, best_t


def print_report(title: str, samples, args) -> None:
    n = len(samples)
    n_err = sum(1 for s in samples if not s["correct"])
    print(f"\n== {title} ==  样本 {n}(其中错误 {n_err},错误率 {n_err / n:.2%})" if n
          else f"\n== {title} ==  样本 0,跳过")
    if not n:
        return
    rows, best_t = sweep(samples, args.t_min, args.t_max, args.t_step, args.target_err)
    header = f"{'阈值':>6} {'免检率':>8} {'免检错误':>8} {'免检准确率':>10} {'拦下错误':>8} {'误拦正确':>8}"
    print(header)
    print("-" * len(header))
    for t, acc_rate, acc_err, acc_prec, rej_err, rej_ok in rows:
        prec = f"{acc_prec:.2%}" if acc_prec is not None else "  (空)"
        mark = "  <-- 建议" if best_t is not None and abs(t - best_t) < 1e-9 else ""
        print(f"{t:>6.2f} {acc_rate:>8.2%} {acc_err:>8} {prec:>10} {rej_err:>8} {rej_ok:>8}{mark}")
    if best_t is None:
        print(f"!! 任何阈值都达不到容错线 {args.target_err:.2%} —— 分数区分度不足,")
        print("   检查标注质量/样本分布,或下调容错线,或接受更高人工复核率。")
    else:
        rec = next(r for r in rows if abs(r[0] - best_t) < 1e-9)
        print(f"\n建议阈值 t* = {best_t:.2f}(免检率 {rec[1]:.2%},免检准确率 {rec[3]:.2%},"
              f"免检错误 {rec[2]} 个)——按业务容错线 {args.target_err:.2%} 计。")


def main() -> int:
    ap = argparse.ArgumentParser(description="Jev 阈值校准报告(官方三步法第三步)")
    ap.add_argument("scores", type=Path, help="标注样本 JSONL(score/verdict/correct)")
    ap.add_argument("--target-err", type=float, default=0.005,
                    help="免检区允许错误率上限(默认 0.005)")
    ap.add_argument("--t-min", type=float, default=0.50)
    ap.add_argument("--t-max", type=float, default=0.99)
    ap.add_argument("--t-step", type=float, default=0.01)
    ap.add_argument("--by-category", action="store_true", help="按 category 分组扫描")
    args = ap.parse_args()

    scored, unscored, bad = load_samples(args.scores)
    print(f"输入 {args.scores}:有效标注 {len(scored)},非 scored {sum(unscored.values())},"
          f"坏行 {bad}")
    for v, c in unscored.most_common():
        print(f"    verdict={v}: {c} 个 —— 不计入阈值统计,业务上全部转人工")
    if not scored:
        print("!! 没有 verdict=scored 的样本,无法校准 —— 先检查评分服务与样本采集", file=sys.stderr)
        return 1
    bad_cat = [s for s in scored if s["category"] not in VALID_CATEGORIES]
    if bad_cat:
        print(f"!! {len(bad_cat)} 个样本 category 不在 {sorted(VALID_CATEGORIES)},按 text 归组",
              file=sys.stderr)

    if args.by_category:
        groups = defaultdict(list)
        for s in scored:
            groups[s["category"] if s["category"] in VALID_CATEGORIES else "text"].append(s)
        for cat in sorted(groups):
            print_report(f"category={cat}", groups[cat], args)
    print_report("全部样本", scored, args)
    print("\n下一步:把 t* 写入业务门控(见《Jev阈值业务校准指南》§5),"
          "换解析器/换文档分布后重新校准。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
