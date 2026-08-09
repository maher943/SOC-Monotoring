#!/usr/bin/env python3
"""Send a Wazuh JSON alert to a Shuffle webhook.

Wazuh integrator invokes this with:
  argv[1] = path to alert JSON file
  argv[2] = api_key (unused for Shuffle webhook; Wazuh always passes it)
  argv[3] = hook_url from <hook_url> in ossec.conf

Why the payload is TheHive-shaped
---------------------------------
Shuffle exposes the webhook POST body only as $exec (a JSON string). Nested
paths like $rule.level are NOT expanded. The Shuffle HTTP action body is
literally `$exec`, so this script builds the TheHive /api/v1/case JSON and
Shuffle forwards it unchanged to TheHive.
"""
from __future__ import print_function

import json
import sys

try:
    from urllib import request as urllib_request
except ImportError:
    import urllib2 as urllib_request  # type: ignore


def build_thehive_case(alert):
    rule = alert.get("rule") or {}
    agent = alert.get("agent") or {}
    rule_id = str(rule.get("id", ""))
    rule_level = str(rule.get("level", ""))
    rule_description = rule.get("description", "") or "Wazuh alert"
    rule_groups = ",".join(rule.get("groups") or [])
    agent_id = str(agent.get("id", ""))
    agent_name = agent.get("name", "") or ""
    location = alert.get("location", "") or ""
    full_log = alert.get("full_log", "") or ""
    raw_json = json.dumps(alert, indent=2)

    title = "Wazuh [%s] %s" % (rule_level, rule_description)
    description = "\n".join(
        [
            "Automated from Wazuh via Shuffle.",
            "",
            "**Rule ID:** %s" % rule_id,
            "**Level:** %s" % rule_level,
            "**Groups:** %s" % rule_groups,
            "**Agent:** %s (%s)" % (agent_name, agent_id),
            "**Location:** %s" % location,
            "",
            "**Full log:**",
            "```",
            full_log,
            "```",
            "",
            "**Raw event:**",
            "```json",
            raw_json,
            "```",
        ]
    )

    # Severity: map Wazuh level (0-15) roughly onto TheHive 1-4
    try:
        level_i = int(rule_level)
    except Exception:
        level_i = 5
    if level_i >= 12:
        severity = 4
    elif level_i >= 10:
        severity = 3
    elif level_i >= 7:
        severity = 2
    else:
        severity = 1

    return {
        "title": title,
        "description": description,
        "severity": severity,
        "tags": ["wazuh", "shuffle", "auto", "level-%s" % rule_level],
        "tlp": 2,
        "pap": 2,
    }


def main():
    if len(sys.argv) < 4:
        sys.stderr.write(
            "usage: custom-shuffle.py <alert_file> <api_key> <hook_url>\n"
        )
        return 1

    alert_file = sys.argv[1]
    hook_url = sys.argv[3]

    with open(alert_file) as f:
        alert = json.load(f)

    data = json.dumps(build_thehive_case(alert)).encode("utf-8")
    req = urllib_request.Request(
        hook_url,
        data=data,
        headers={"Content-Type": "application/json"},
    )
    try:
        urllib_request.urlopen(req, timeout=10)
    except Exception as exc:
        sys.stderr.write("custom-shuffle error: %s\n" % exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
