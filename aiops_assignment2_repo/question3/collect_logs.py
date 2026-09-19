import re

from kubernetes import client, config

JOB_NAME = "shard-validator"


def main() -> None:
    config.load_kube_config()
    api = client.CoreV1Api()

    pods = api.list_pod_for_all_namespaces(
        label_selector=f"job-name={JOB_NAME}"
    ).items

    if not pods:
        raise SystemExit("No shard-validator pods found")

    results = {}
    pattern = re.compile(
        r"RESULT shard=(\d+) .* invalid_rows=(\d+)"
    )

    for pod in pods:
        log = api.read_namespaced_pod_log(
            name=pod.metadata.name,
            namespace=pod.metadata.namespace,
        )

        match = pattern.search(log)
        if not match:
            raise RuntimeError(
                f"Could not parse result from pod {pod.metadata.name}:\n{log}"
            )

        shard = int(match.group(1))
        invalid_rows = int(match.group(2))
        results[shard] = {
            "pod": pod.metadata.name,
            "node": pod.spec.node_name,
            "invalid_rows": invalid_rows,
        }

    print("shard,pod,node,invalid_rows")
    for shard in sorted(results):
        item = results[shard]
        print(
            f"{shard},{item['pod']},{item['node']},{item['invalid_rows']}"
        )

    expected = set(range(8))
    observed = set(results)
    if observed != expected:
        raise RuntimeError(
            f"Expected shards {sorted(expected)}, got {sorted(observed)}"
        )

    print("ALL_8_SHARDS_REPORTED=1")


if __name__ == "__main__":
    main()
