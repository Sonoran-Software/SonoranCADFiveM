#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable


DEFAULT_EXCLUDES = {".git", "node_modules"}


@dataclass
class Finding:
    file: str
    line: int
    function: str
    first_arg: str
    issue: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Audit Lua logging calls for missing structured codes.")
    parser.add_argument("repo_root", help="Repository root to scan.")
    parser.add_argument(
        "--logging-file",
        default="sonorancad/core/logging.lua",
        help="Path to logging.lua relative to repo root.",
    )
    parser.add_argument(
        "--format",
        choices=("text", "json"),
        default="text",
        help="Output format.",
    )
    parser.add_argument(
        "--include",
        action="append",
        default=["**/*.lua"],
        help="Glob pattern(s) to include. Repeat as needed.",
    )
    return parser.parse_args()


def load_registered_keys(logging_file: Path) -> tuple[set[str], set[str]]:
    content = logging_file.read_text(encoding="utf-8")
    warning_match = re.search(r"local WarningCodes = \{(.*?)\n\}", content, re.S)
    error_match = re.search(r"local ErrorCodes = \{(.*?)\n\}", content, re.S)
    if not warning_match or not error_match:
        raise RuntimeError(f"Could not parse code tables from {logging_file}")

    key_pattern = re.compile(r"\['([^']+)'\]\s*=")
    warning_keys = set(key_pattern.findall(warning_match.group(1)))
    error_keys = set(key_pattern.findall(error_match.group(1)))
    return warning_keys, error_keys


def iter_lua_files(repo_root: Path, patterns: Iterable[str]) -> Iterable[Path]:
    seen: set[Path] = set()
    for pattern in patterns:
        for path in repo_root.glob(pattern):
            if not path.is_file():
                continue
            if any(part in DEFAULT_EXCLUDES for part in path.parts):
                continue
            if path in seen:
                continue
            seen.add(path)
            yield path


def line_number_from_offset(content: str, offset: int) -> int:
    return content.count("\n", 0, offset) + 1


def split_first_argument(call_body: str) -> str:
    depth = 0
    in_single = False
    in_double = False
    in_long = False
    i = 0
    while i < len(call_body):
        ch = call_body[i]
        nxt = call_body[i + 1] if i + 1 < len(call_body) else ""
        if not in_single and not in_double and not in_long and ch == "-" and nxt == "-":
            if i + 3 < len(call_body) and call_body[i + 2] == "[" and call_body[i + 3] == "[":
                end = call_body.find("]]", i + 4)
                if end == -1:
                    return call_body.strip()
                i = end + 2
                continue
            end = call_body.find("\n", i + 2)
            if end == -1:
                return call_body[:i].strip()
            i = end + 1
            continue
        if not in_double and not in_long and ch == "'" and (i == 0 or call_body[i - 1] != "\\"):
            in_single = not in_single
        elif not in_single and not in_long and ch == '"' and (i == 0 or call_body[i - 1] != "\\"):
            in_double = not in_double
        elif not in_single and not in_double and ch == "[" and nxt == "[":
            in_long = True
            i += 2
            continue
        elif in_long and ch == "]" and nxt == "]":
            in_long = False
            i += 2
            continue
        elif not in_single and not in_double and not in_long:
            if ch in "({[":
                depth += 1
            elif ch in ")}]":
                depth = max(0, depth - 1)
            elif ch == "," and depth == 0:
                return call_body[:i].strip()
        i += 1
    return call_body.strip()


def extract_calls(content: str) -> list[tuple[str, int, str]]:
    calls: list[tuple[str, int, str]] = []
    pattern = re.compile(r"\b(errorLog|logError|warnLog|logWarn)\s*\(")
    for match in pattern.finditer(content):
        function_name = match.group(1)
        start = match.end()
        depth = 1
        in_single = False
        in_double = False
        in_long = False
        i = start
        while i < len(content):
            ch = content[i]
            nxt = content[i + 1] if i + 1 < len(content) else ""
            if not in_single and not in_double and not in_long and ch == "-" and nxt == "-":
                if i + 3 < len(content) and content[i + 2] == "[" and content[i + 3] == "[":
                    end = content.find("]]", i + 4)
                    if end == -1:
                        break
                    i = end + 2
                    continue
                end = content.find("\n", i + 2)
                if end == -1:
                    break
                i = end + 1
                continue
            if not in_double and not in_long and ch == "'" and (i == 0 or content[i - 1] != "\\"):
                in_single = not in_single
            elif not in_single and not in_long and ch == '"' and (i == 0 or content[i - 1] != "\\"):
                in_double = not in_double
            elif not in_single and not in_double and ch == "[" and nxt == "[":
                in_long = True
                i += 2
                continue
            elif in_long and ch == "]" and nxt == "]":
                in_long = False
                i += 2
                continue
            elif not in_single and not in_double and not in_long:
                if ch == "(":
                    depth += 1
                elif ch == ")":
                    depth -= 1
                    if depth == 0:
                        calls.append((function_name, match.start(), content[start:i]))
                        break
            i += 1
    return calls


def classify_first_arg(function_name: str, first_arg: str, warning_keys: set[str], error_keys: set[str]) -> str | None:
    first_arg = first_arg.strip()
    string_match = re.fullmatch(r"""(['"])(.*?)\1""", first_arg, re.S)
    if string_match:
        value = string_match.group(2)
        if function_name in ("warnLog", "logWarn"):
            if value in warning_keys or value in error_keys:
                return None
        else:
            if value in error_keys:
                return None
        if re.fullmatch(r"[A-Z0-9_]+", value):
            return "unknown_code_key"
        return "raw_message_literal"
    return "raw_expression"


def run_audit(repo_root: Path, logging_file: Path, patterns: Iterable[str]) -> list[Finding]:
    warning_keys, error_keys = load_registered_keys(logging_file)
    findings: list[Finding] = []
    for path in iter_lua_files(repo_root, patterns):
        if path.resolve() == logging_file.resolve():
            continue
        content = path.read_text(encoding="utf-8")
        for function_name, offset, body in extract_calls(content):
            first_arg = split_first_argument(body)
            issue = classify_first_arg(function_name, first_arg, warning_keys, error_keys)
            if issue is None:
                continue
            findings.append(
                Finding(
                    file=str(path.relative_to(repo_root)).replace("\\", "/"),
                    line=line_number_from_offset(content, offset),
                    function=function_name,
                    first_arg=first_arg,
                    issue=issue,
                )
            )
    findings.sort(key=lambda item: (item.file, item.line, item.function))
    return findings


def render_text(findings: list[Finding]) -> str:
    if not findings:
        return "No missing structured log codes found."
    lines = [f"Found {len(findings)} logging call(s) missing structured codes:"]
    for finding in findings:
        lines.append(
            f"- {finding.file}:{finding.line} {finding.function} -> {finding.issue} | first_arg={finding.first_arg}"
        )
    return "\n".join(lines)


def main() -> None:
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    logging_file = (repo_root / args.logging_file).resolve()
    findings = run_audit(repo_root, logging_file, args.include)
    if args.format == "json":
        print(json.dumps([asdict(item) for item in findings], indent=2))
    else:
        print(render_text(findings))


if __name__ == "__main__":
    main()
