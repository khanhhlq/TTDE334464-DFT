import argparse
import csv
import heapq
import math
import re
from collections import defaultdict
from dataclasses import dataclass


INF = math.inf


@dataclass
class Gate:
    output: str
    kind: str
    inputs: list


def read_bench(filename):
    primary_inputs = set()
    primary_outputs = set()
    gates = []
    drivers = set()

    with open(filename, encoding="utf-8-sig") as file:
        for line_number, raw in enumerate(file, 1):
            line = raw.split("#", 1)[0].split("//", 1)[0].strip()

            if not line:
                continue

            line = line.rstrip(";").strip()

            port = re.fullmatch(
                r"(INPUT|OUTPUT)\s*\(\s*([^\s(),=]+)\s*\)",
                line,
                re.IGNORECASE,
            )

            if port:
                direction, name = port.groups()

                if direction.upper() == "INPUT":
                    if name in drivers:
                        raise ValueError(
                            f"Line {line_number}: multiple drivers for {name}"
                        )
                    primary_inputs.add(name)
                    drivers.add(name)
                else:
                    primary_outputs.add(name)

                continue

            assignment = re.fullmatch(
                r"([^\s(),=]+)\s*=\s*(\w+)\s*\((.*)\)",
                line,
            )

            if not assignment:
                raise ValueError(
                    f"Line {line_number}: invalid syntax: {line}"
                )

            output, kind, arguments = assignment.groups()
            kind = kind.upper()

            if kind == "BUFF":
                kind = "BUF"

            inputs = [
                value.strip()
                for value in arguments.split(",")
                if value.strip()
            ]

            supported = {
                "AND", "NAND", "OR", "NOR",
                "NOT", "BUF", "XOR", "XNOR", "DFF"
            }

            if kind not in supported:
                raise ValueError(
                    f"Line {line_number}: unsupported gate {kind}"
                )

            if kind in {"NOT", "BUF", "DFF"}:
                valid_count = len(inputs) == 1
            else:
                valid_count = len(inputs) >= 2

            if not valid_count:
                raise ValueError(
                    f"Line {line_number}: invalid input count for {kind}"
                )

            if output in drivers:
                raise ValueError(
                    f"Line {line_number}: multiple drivers for {output}"
                )

            drivers.add(output)
            gates.append(Gate(output, kind, inputs))

    if drivers & {"0", "1"}:
        raise ValueError("Names 0 and 1 are reserved for constants.")

    defined = drivers | {"0", "1"}

    referenced = set(primary_outputs)
    for gate in gates:
        referenced.update(gate.inputs)

    missing = referenced - defined
    if missing:
        raise ValueError(
            "Undriven signals: " + ", ".join(sorted(missing))
        )

    return primary_inputs, primary_outputs, gates


def topological_order(gates):
    """Sap thu tu cong to hop; bao loi neu con vong phan hoi."""
    producers = {gate.output: index for index, gate in enumerate(gates)}
    successors = defaultdict(set)
    indegree = [0] * len(gates)

    for index, gate in enumerate(gates):
        dependencies = {
            producers[signal]
            for signal in gate.inputs
            if signal in producers
        }

        indegree[index] = len(dependencies)

        for dependency in dependencies:
            successors[dependency].add(index)

    ready = [
        index for index, degree in enumerate(indegree)
        if degree == 0
    ]
    heapq.heapify(ready)

    result = []

    while ready:
        index = heapq.heappop(ready)
        result.append(gates[index])

        for successor in successors[index]:
            indegree[successor] -= 1

            if indegree[successor] == 0:
                heapq.heappush(ready, successor)

    if len(result) != len(gates):
        raise ValueError(
            "Combinational cycle detected. "
            "This program cannot analyze sequential feedback."
        )

    return result


def parity_cost(signals, cc):
    """
    Chi phi nho nhat de XOR cac tin hieu bang 0 hoac 1.
    Chua cong chi phi cua cong XOR.
    """
    even, odd = 0, INF

    for signal in signals:
        c0, c1 = cc[signal]
        even, odd = (
            min(even + c0, odd + c1),
            min(even + c1, odd + c0),
        )

    return even, odd


def gate_controllability(gate, cc):
    values = [cc[signal] for signal in gate.inputs]
    kind = gate.kind

    if kind == "BUF":
        return values[0][0] + 1, values[0][1] + 1

    if kind == "NOT":
        return values[0][1] + 1, values[0][0] + 1

    if kind in {"AND", "NAND"}:
        c0 = min(value[0] for value in values) + 1
        c1 = sum(value[1] for value in values) + 1

    elif kind in {"OR", "NOR"}:
        c0 = sum(value[0] for value in values) + 1
        c1 = min(value[1] for value in values) + 1

    elif kind in {"XOR", "XNOR"}:
        even, odd = parity_cost(gate.inputs, cc)
        c0, c1 = even + 1, odd + 1

    else:
        raise ValueError(f"Unsupported gate: {kind}")

    if kind in {"NAND", "NOR", "XNOR"}:
        c0, c1 = c1, c0

    return c0, c1


def input_observability(gate, position, cc, output_co):
    others = (
        gate.inputs[:position] + gate.inputs[position + 1:]
    )

    if gate.kind in {"AND", "NAND"}:
        side_cost = sum(cc[signal][1] for signal in others)

    elif gate.kind in {"OR", "NOR"}:
        side_cost = sum(cc[signal][0] for signal in others)

    elif gate.kind in {"XOR", "XNOR"}:
        side_cost = sum(min(cc[signal]) for signal in others)

    else:
        side_cost = 0

    return output_co + side_cost + 1


def calculate_scoap(primary_inputs, primary_outputs, gates, full_scan):
    flip_flops = [gate for gate in gates if gate.kind == "DFF"]

    if flip_flops and not full_scan:
        raise ValueError(
            "DFF found. Use --full-scan to cut ALL DFFs at D/Q. "
            "Partial-scan sequential analysis is not implemented."
        )

    combinational = [gate for gate in gates if gate.kind != "DFF"]

    scan_q = {gate.output for gate in flip_flops}
    scan_d = {gate.inputs[0] for gate in flip_flops}

    sources = primary_inputs | scan_q
    observation_points = primary_outputs | scan_d

    nodes = primary_inputs | primary_outputs
    for gate in gates:
        nodes.update(gate.inputs)
        nodes.add(gate.output)

    cc = {
        "0": (0, INF),
        "1": (INF, 0),
    }

    for signal in sources:
        cc[signal] = (1, 1)

    ordered = topological_order(combinational)

    for gate in ordered:
        cc[gate.output] = gate_controllability(gate, cc)

    co = {signal: INF for signal in nodes}

    for signal in observation_points:
        co[signal] = 0

    for gate in reversed(ordered):
        for position, signal in enumerate(gate.inputs):
            candidate = input_observability(
                gate, position, cc, co[gate.output]
            )
            co[signal] = min(co[signal], candidate)

    roles = defaultdict(set)

    for signal in primary_inputs:
        roles[signal].add("PI")
    for signal in primary_outputs:
        roles[signal].add("PO")
    for signal in scan_q:
        roles[signal].add("SCAN_Q")
    for signal in scan_d:
        roles[signal].add("SCAN_D")

    rows = []

    for signal in sorted(nodes):
        rows.append({
            "node": signal,
            "role": "|".join(sorted(roles[signal])) or "INTERNAL",
            "CC0": cc[signal][0],
            "CC1": cc[signal][1],
            "CO": co[signal],
        })

    return rows, len(flip_flops)


def format_number(value):
    return "INF" if math.isinf(value) else str(int(value))


def main():
    parser = argparse.ArgumentParser(
        description="Combinational / full-scan SCOAP calculator"
    )
    parser.add_argument("netlist", help="Input .bench netlist")
    parser.add_argument(
        "--full-scan",
        action="store_true",
        help="Treat every DFF Q as PPI and every DFF D as PPO",
    )
    parser.add_argument(
        "--csv",
        help="Optional output CSV filename",
    )
    args = parser.parse_args()

    try:
        inputs, outputs, gates = read_bench(args.netlist)
        rows, scan_count = calculate_scoap(
            inputs, outputs, gates, args.full_scan
        )
    except (OSError, ValueError) as error:
        parser.exit(1, f"ERROR: {error}\n")

    print(f"Primary inputs : {len(inputs)}")
    print(f"Primary outputs: {len(outputs)}")
    print(f"Scan DFFs      : {scan_count}")
    print()

    print(f"{'NODE':<32} {'ROLE':<20} {'CC0':>8} {'CC1':>8} {'CO':>8}")

    for row in rows:
        print(
            f"{row['node']:<32} "
            f"{row['role']:<20} "
            f"{format_number(row['CC0']):>8} "
            f"{format_number(row['CC1']):>8} "
            f"{format_number(row['CO']):>8}"
        )

    if args.csv:
        with open(args.csv, "w", newline="", encoding="utf-8-sig") as file:
            writer = csv.DictWriter(
                file, fieldnames=["node", "role", "CC0", "CC1", "CO"]
            )
            writer.writeheader()

            for row in rows:
                writer.writerow({
                    **row,
                    "CC0": format_number(row["CC0"]),
                    "CC1": format_number(row["CC1"]),
                    "CO": format_number(row["CO"]),
                })

        print(f"\nSaved: {args.csv}")

if __name__ == "__main__":
    main()