#!/usr/bin/env python3
"""Fetch the upstream dashboards that need a rewrite before the sync-job sees
them and write them to o11y/vendor/ (git-ignored). The sync-job then treats
them like any other source: it adds the fleet's `$cluster` variable, the
`cluster=~"$cluster"` filter, `by (cluster)` on aggregations and the Fleet
datasource.

Rewrites:
- cloudnativepg: upstream uses `cluster` for the Postgres cluster; the fleet
  keeps that under `pg_cluster` and reserves `cluster` for the Kubernetes one.
- etcd: the mixin's `cluster` variable holds job names and filters on
  `job="$cluster"`; it is renamed to `job` so the sync-job's cluster variable
  does not collide with it.
"""

import pathlib
import re
import sys
import urllib.request

VENDOR_DIR = pathlib.Path(__file__).resolve().parent.parent / "vendor"


def rename_cnpg_cluster(text):
    text = re.sub(r"\$cluster\b", "$pg_cluster", text)
    text = re.sub(r"\bcluster(\s*(?:=~|!~|!=|=)\s*)", r"pg_cluster\1", text)
    text = re.sub(r"([(,]\s*)cluster(\s*[,)])", r"\1pg_cluster\2", text)
    text = re.sub(r'"name":\s*"cluster"', '"name": "pg_cluster"', text)
    return text.replace("\\\\bcluster\\\\b=", "\\\\bpg_cluster\\\\b=")


def rename_etcd_cluster_to_job(text):
    text = re.sub(r"\$cluster\b", "$job", text)
    return re.sub(r'"name":\s*"cluster"', '"name": "job"', text)


IMPORTS = {
    "cloudnativepg": (
        "https://raw.githubusercontent.com/cloudnative-pg/grafana-dashboards/cluster-v0.0.5/charts/cluster/grafana-dashboard.json",
        rename_cnpg_cluster,
    ),
    "etcd": (
        "https://raw.githubusercontent.com/monitoring-mixins/website/master/assets/etcd/dashboards/etcd.json",
        rename_etcd_cluster_to_job,
    ),
}


def main():
    only = set(sys.argv[1:])
    VENDOR_DIR.mkdir(parents=True, exist_ok=True)
    for name, (url, rewrite) in IMPORTS.items():
        if only and name not in only:
            continue
        text = urllib.request.urlopen(url, timeout=30).read().decode()
        (VENDOR_DIR / f"{name}.json").write_text(rewrite(text))
        print(f"{name}.json <- {url}")


if __name__ == "__main__":
    main()
