from __future__ import annotations

import argparse
import csv
from pathlib import Path
from statistics import mean

import matplotlib.pyplot as plt


STAGE_COLUMNS = [
    "avg_capture",
    "avg_mediapipe",
    "avg_feature",
    "avg_mapping",
    "avg_osc",
    "avg_drawing",
    "avg_display",
]

MAX_COLUMNS = [
    "max_total",
    "max_mediapipe",
    "max_drawing",
    "max_display",
]


def parse_value(value: str):
    if value == "skipped":
        return None
    try:
        return float(value)
    except ValueError:
        return value


def parse_perf_line(line: str) -> dict | None:
    if "[perf]" not in line:
        return None

    # Example:
    # [perf] fps=30.1 avg_ms total=33.22 capture=5.06 ... max_ms total=61.00 ...
    tokens = line.strip().split()
    if not tokens or tokens[0] != "[perf]":
        return None

    row: dict = {}
    prefix = ""

    for token in tokens[1:]:
        if token == "avg_ms":
            prefix = "avg_"
            continue
        if token == "max_ms":
            prefix = "max_"
            continue
        if "=" not in token:
            continue

        key, value = token.split("=", 1)
        parsed = parse_value(value)

        # fps / events / hands are overall values, not avg_ or max_ values.
        if key in {"fps", "events", "hands"}:
            out_key = key
        elif prefix:
            out_key = prefix + key
        else:
            out_key = key

        row[out_key] = parsed

    if "fps" not in row:
        return None

    return row

def read_text_auto(path: Path) -> str:
    """Read PowerShell / UTF-8 / Japanese Windows log files robustly."""
    data = path.read_bytes()

    if not data:
        return ""

    # BOM付きUTF-16 / UTF-8を優先
    if data.startswith(b"\xff\xfe") or data.startswith(b"\xfe\xff"):
        return data.decode("utf-16", errors="replace")
    if data.startswith(b"\xef\xbb\xbf"):
        return data.decode("utf-8-sig", errors="replace")

    # PowerShell 5系の Tee-Object / Out-File は UTF-16LE になりやすい。
    # UTF-16LEをUTF-8として読むと、文字間に NUL が入り [perf] が検出できない。
    sample = data[:2000]
    nul_ratio = sample.count(b"\x00") / max(1, len(sample))
    if nul_ratio > 0.2:
        for encoding in ("utf-16-le", "utf-16-be", "utf-16"):
            try:
                return data.decode(encoding)
            except UnicodeDecodeError:
                continue
        return data.decode("utf-16-le", errors="replace")

    # 通常候補
    for encoding in ("utf-8-sig", "utf-8", "cp932", "utf-16", "utf-16-le"):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            continue

    return data.decode("utf-8", errors="replace")

def read_perf_log(path: Path, interval: float) -> list[dict]:
    rows: list[dict] = []
    text = read_text_auto(path)

    for line in text.splitlines():
        row = parse_perf_line(line)
        if row is None:
            continue
        row["sample"] = len(rows)
        row["time_s"] = len(rows) * interval
        rows.append(row)

    return rows

def write_csv(rows: list[dict], path: Path) -> None:
    all_keys = []
    for row in rows:
        for key in row:
            if key not in all_keys:
                all_keys.append(key)

    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=all_keys)
        writer.writeheader()
        writer.writerows(rows)


def numeric_values(rows: list[dict], key: str) -> list[float]:
    values = []
    for row in rows:
        value = row.get(key)
        if isinstance(value, (int, float)):
            values.append(float(value))
        else:
            values.append(float("nan"))
    return values


def save_line_chart(rows: list[dict], keys: list[str], title: str, ylabel: str, path: Path) -> None:
    x = numeric_values(rows, "time_s")

    plt.figure(figsize=(12, 6))
    for key in keys:
        y = numeric_values(rows, key)
        plt.plot(x, y, label=key)

    plt.title(title)
    plt.xlabel("Time (s, approximate)")
    plt.ylabel(ylabel)
    plt.legend()
    plt.grid(True)
    plt.tight_layout()
    plt.savefig(path, dpi=150)
    plt.close()


def save_bar_chart(rows: list[dict], keys: list[str], title: str, ylabel: str, path: Path) -> None:
    labels = []
    values = []

    for key in keys:
        nums = [v for v in numeric_values(rows, key) if v == v]
        if not nums:
            continue
        labels.append(key.replace("avg_", "").replace("max_", "max_"))
        values.append(mean(nums))

    plt.figure(figsize=(10, 6))
    plt.bar(labels, values)
    plt.title(title)
    plt.xlabel("Stage")
    plt.ylabel(ylabel)
    plt.xticks(rotation=35, ha="right")
    plt.grid(True, axis="y")
    plt.tight_layout()
    plt.savefig(path, dpi=150)
    plt.close()


def save_scatter(rows: list[dict], x_key: str, y_key: str, title: str, path: Path) -> None:
    x = numeric_values(rows, x_key)
    y = numeric_values(rows, y_key)

    plt.figure(figsize=(8, 6))
    plt.scatter(x, y)
    plt.title(title)
    plt.xlabel(x_key)
    plt.ylabel(y_key)
    plt.grid(True)
    plt.tight_layout()
    plt.savefig(path, dpi=150)
    plt.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Plot handtrack performance logs.")
    parser.add_argument("log_file", type=Path)
    parser.add_argument("--out-dir", type=Path, default=Path("analysis/perf"))
    parser.add_argument("--interval", type=float, default=1.0, help="Performance print interval in seconds.")
    args = parser.parse_args()

    rows = read_perf_log(args.log_file, args.interval)
    if not rows:
        raise SystemExit("No [perf] lines found in the log file.")

    args.out_dir.mkdir(parents=True, exist_ok=True)

    csv_path = args.out_dir / "perf_summary.csv"
    write_csv(rows, csv_path)

    save_line_chart(
        rows,
        ["avg_total", "max_total"],
        "Total frame time",
        "ms",
        args.out_dir / "total_frame_time.png",
    )

    save_line_chart(
        rows,
        ["fps"],
        "FPS over time",
        "fps",
        args.out_dir / "fps_over_time.png",
    )

    save_line_chart(
        rows,
        STAGE_COLUMNS,
        "Stage timings over time",
        "ms",
        args.out_dir / "stage_timings_over_time.png",
    )

    save_bar_chart(
        rows,
        STAGE_COLUMNS,
        "Average processing time by stage",
        "ms",
        args.out_dir / "average_stage_breakdown.png",
    )

    save_bar_chart(
        rows,
        MAX_COLUMNS,
        "Average of max timings by stage",
        "ms",
        args.out_dir / "max_stage_breakdown.png",
    )

    if any(isinstance(row.get("hands"), (int, float)) for row in rows):
        save_scatter(
            rows,
            "hands",
            "avg_mediapipe",
            "Hands detected vs MediaPipe time",
            args.out_dir / "hands_vs_mediapipe.png",
        )

    print(f"Parsed {len(rows)} perf rows.")
    print(f"Wrote CSV: {csv_path}")
    print(f"Wrote charts to: {args.out_dir}")


if __name__ == "__main__":
    main()