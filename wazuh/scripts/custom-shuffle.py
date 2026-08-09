#!/usr/bin/env python3
"""Send a Wazuh JSON alert to a Shuffle webhook.

Wazuh integrator invokes this with:
  argv[1] = path to alert JSON file
  argv[2] = api_key (unused for Shuffle webhook; Wazuh always passes it)
  argv[3] = hook_url from <hook_url> in ossec.conf

No secrets are hardcoded here — the URL comes from the ConfigMap.
"""
from __future__ import print_function

import json
import sys

try:
    from urllib import request as urllib_request
except ImportError:
    import urllib2 as urllib_request  # type: ignore


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

    data = json.dumps(alert).encode("utf-8")
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
