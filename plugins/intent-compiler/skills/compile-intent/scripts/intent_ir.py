#!/usr/bin/env python3
"""Validate and assess machine-readable Intent IR files using only the stdlib."""

from __future__ import annotations

import argparse
import ipaddress
import json
import math
import re
import sys
from pathlib import Path
from typing import Any


STATUSES = {
    "READY",
    "READY_WITH_ASSUMPTIONS",
    "NEEDS_CLARIFICATION",
    "BLOCKED_BY_EVIDENCE",
}
LEVELS = {"low", "medium", "high"}
REVERSIBILITY = {"easy", "moderate", "hard"}
MIGRATIONS = {"none", "possible", "required"}

EMAIL_RE = re.compile(r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", re.IGNORECASE)
PRIVATE_KEY_RE = re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")
TOKEN_RE = re.compile(
    r"\b(?:AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,})\b"
)
SECRET_ASSIGNMENT_RE = re.compile(
    r"\b(?:api[_ -]?key|access[_ -]?token|password|passwd|client[_ -]?secret|authorization)"
    r"\s*[:=]\s*(?!\[REDACTED_SECRET\])[^\s,;]{8,}",
    re.IGNORECASE,
)
PERSONAL_PATH_RE = re.compile(
    r"(?:\b[A-Z]:[\\/]+Users[\\/]+[^\\/\s]+|/(?:Users|home)/[^/\s]+|/root(?:/|\b))",
    re.IGNORECASE,
)
IP_CANDIDATE_RE = re.compile(r"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])")
PRECISE_TIMESTAMP_RE = re.compile(
    r"\b\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2})?\b"
)


def load_ir(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError("Intent IR root must be a JSON object")
    return value


def normalized_entropy(probabilities: list[float]) -> float:
    if len(probabilities) < 2:
        return 0.0
    entropy = -sum(p * math.log(p) for p in probabilities if p > 0)
    return entropy / math.log(len(probabilities))


def iter_strings(value: Any, location: str = "root") -> list[tuple[str, str]]:
    strings: list[tuple[str, str]] = []
    if isinstance(value, str):
        strings.append((location, value))
    elif isinstance(value, dict):
        for key, item in value.items():
            strings.extend(iter_strings(item, f"{location}.{key}"))
    elif isinstance(value, list):
        for index, item in enumerate(value):
            strings.extend(iter_strings(item, f"{location}[{index}]"))
    return strings


def privacy_errors(ir: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    for location, value in iter_strings(ir):
        if EMAIL_RE.search(value):
            errors.append(f"{location} contains an email address; replace it with a placeholder")
        if PRIVATE_KEY_RE.search(value):
            errors.append(f"{location} contains private-key material; replace it with [REDACTED_SECRET]")
        if TOKEN_RE.search(value) or SECRET_ASSIGNMENT_RE.search(value):
            errors.append(f"{location} contains authentication material; replace it with [REDACTED_SECRET]")
        if PERSONAL_PATH_RE.search(value):
            errors.append(f"{location} contains a personal absolute path; use a repository-relative or role-based path")
        if PRECISE_TIMESTAMP_RE.search(value):
            errors.append(f"{location} contains a precise timestamp; reduce it to the least precise useful value")
        for candidate in IP_CANDIDATE_RE.findall(value):
            try:
                ipaddress.ip_address(candidate)
            except ValueError:
                continue
            errors.append(f"{location} contains an IP address; replace it with a stable placeholder")
            break
    return errors


def validate(ir: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    required = [
        "version", "status", "observed_request", "goal", "decomposition",
        "hypotheses", "evidence", "constraints", "assumptions",
        "success_criteria", "affected_surface", "execution_gate",
        "verification_plan",
    ]
    for key in required:
        if key not in ir:
            errors.append(f"missing required field: {key}")

    if ir.get("version") != "1.0":
        errors.append("version must be '1.0'")
    if ir.get("status") not in STATUSES:
        errors.append(f"status must be one of: {', '.join(sorted(STATUSES))}")
    for key in ("observed_request", "goal", "execution_gate"):
        if not isinstance(ir.get(key), str) or not ir.get(key, "").strip():
            errors.append(f"{key} must be a non-empty string")

    decomposition = ir.get("decomposition")
    if not isinstance(decomposition, dict):
        errors.append("decomposition must be an object")
    else:
        for key in ("problem", "cause_hypothesis", "requested_action"):
            if key not in decomposition:
                errors.append(f"decomposition.{key} is required (use null when unknown)")
            elif decomposition[key] is not None and not isinstance(decomposition[key], str):
                errors.append(f"decomposition.{key} must be a string or null")

    hypotheses = ir.get("hypotheses")
    probabilities: list[float] = []
    if not isinstance(hypotheses, list) or not hypotheses:
        errors.append("hypotheses must be a non-empty array")
    else:
        seen_ids: set[str] = set()
        for index, hypothesis in enumerate(hypotheses):
            prefix = f"hypotheses[{index}]"
            if not isinstance(hypothesis, dict):
                errors.append(f"{prefix} must be an object")
                continue
            hypothesis_id = hypothesis.get("id")
            if not isinstance(hypothesis_id, str) or not hypothesis_id.startswith("H"):
                errors.append(f"{prefix}.id must look like H1")
            elif hypothesis_id in seen_ids:
                errors.append(f"duplicate hypothesis id: {hypothesis_id}")
            else:
                seen_ids.add(hypothesis_id)
            if not isinstance(hypothesis.get("interpretation"), str) or not hypothesis.get("interpretation", "").strip():
                errors.append(f"{prefix}.interpretation must be a non-empty string")
            probability = hypothesis.get("probability")
            if not isinstance(probability, (int, float)) or isinstance(probability, bool) or not 0 <= probability <= 1:
                errors.append(f"{prefix}.probability must be between 0 and 1")
            else:
                probabilities.append(float(probability))
            for evidence_key in ("evidence_for", "evidence_against"):
                if not isinstance(hypothesis.get(evidence_key), list) or not all(
                    isinstance(item, str) for item in hypothesis.get(evidence_key, [])
                ):
                    errors.append(f"{prefix}.{evidence_key} must be an array of strings")
        if probabilities and not math.isclose(sum(probabilities), 1.0, abs_tol=0.001):
            errors.append(f"hypothesis probabilities must sum to 1.0 (got {sum(probabilities):.6f})")

    for key in ("evidence", "constraints", "assumptions", "success_criteria", "verification_plan"):
        value = ir.get(key)
        if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
            errors.append(f"{key} must be an array of strings")
    for key in ("success_criteria", "verification_plan"):
        if isinstance(ir.get(key), list) and not ir[key]:
            errors.append(f"{key} must not be empty")

    surface = ir.get("affected_surface")
    if not isinstance(surface, dict):
        errors.append("affected_surface must be an object")
    else:
        if not isinstance(surface.get("confirmed"), list) or not all(
            isinstance(item, str) for item in surface.get("confirmed", [])
        ):
            errors.append("affected_surface.confirmed must be an array of strings")
        if surface.get("data_migration") not in MIGRATIONS:
            errors.append("affected_surface.data_migration must be none, possible, or required")
        estimate = surface.get("estimated_file_count")
        if estimate is not None:
            if not isinstance(estimate, dict):
                errors.append("affected_surface.estimated_file_count must be an object or null")
            else:
                low, high = estimate.get("min"), estimate.get("max")
                if not isinstance(low, int) or isinstance(low, bool) or low < 0:
                    errors.append("estimated_file_count.min must be a non-negative integer")
                if not isinstance(high, int) or isinstance(high, bool) or high < 0:
                    errors.append("estimated_file_count.max must be a non-negative integer")
                if isinstance(low, int) and isinstance(high, int) and low > high:
                    errors.append("estimated_file_count.min must not exceed max")
                if not isinstance(estimate.get("basis"), str) or not estimate.get("basis", "").strip():
                    errors.append("estimated_file_count.basis must be a non-empty string")

    factors = ir.get("decision_factors")
    if factors is not None:
        if not isinstance(factors, dict):
            errors.append("decision_factors must be an object")
        else:
            if factors.get("impact_divergence") not in LEVELS:
                errors.append("decision_factors.impact_divergence must be low, medium, or high")
            if factors.get("risk") not in LEVELS:
                errors.append("decision_factors.risk must be low, medium, or high")
            if factors.get("reversibility") not in REVERSIBILITY:
                errors.append("decision_factors.reversibility must be easy, moderate, or hard")
            if not isinstance(factors.get("evidence_conflict"), bool):
                errors.append("decision_factors.evidence_conflict must be boolean")

    errors.extend(privacy_errors(ir))

    return errors


def assess(ir: dict[str, Any]) -> dict[str, Any]:
    probabilities = [float(item["probability"]) for item in ir["hypotheses"]]
    dominant = max(probabilities)
    entropy = normalized_entropy(probabilities)
    factors = ir.get("decision_factors") or {}
    divergence = factors.get("impact_divergence", "medium")
    risk = factors.get("risk", "medium")
    reversibility = factors.get("reversibility", "moderate")
    conflict = factors.get("evidence_conflict", bool(ir.get("conflicts")))

    if conflict:
        recommendation = "BLOCKED_BY_EVIDENCE"
        reason = "Observed evidence conflicts with the requested action or cause hypothesis."
    elif divergence == "high" and entropy > 0.45:
        recommendation = "NEEDS_CLARIFICATION"
        reason = "Competing interpretations remain diffuse and lead to materially different changes."
    elif (risk == "high" or reversibility == "hard") and dominant < 0.80:
        recommendation = "NEEDS_CLARIFICATION"
        reason = "The change is risky or difficult to reverse without a sufficiently dominant interpretation."
    elif dominant >= 0.80 and entropy <= 0.45 and risk == "low" and reversibility == "easy":
        recommendation = "READY"
        reason = "Evidence is concentrated and the proposed action is low-risk and reversible."
    elif divergence == "low" and risk != "high" and reversibility != "hard":
        recommendation = "READY_WITH_ASSUMPTIONS"
        reason = "Remaining interpretations share a safe first step."
    else:
        recommendation = "NEEDS_CLARIFICATION"
        reason = "No safe default gate was established; gather evidence or ask one discriminating question."

    return {
        "dominant_probability": round(dominant, 6),
        "normalized_entropy": round(entropy, 6),
        "recommended_status": recommendation,
        "declared_status": ir["status"],
        "status_matches": recommendation == ir["status"],
        "reason": reason,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("validate", "assess"))
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    try:
        ir = load_ir(args.path)
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    errors = validate(ir)
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    if args.command == "validate":
        print("Intent IR is valid.")
    else:
        print(json.dumps(assess(ir), ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
