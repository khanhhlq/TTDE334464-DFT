import argparse
import json
from pathlib import Path

GATES = {
    "$_NOT_":  ("NOT",  ["A"]),
    "$_BUF_":  ("BUF",  ["A"]),
    "$_AND_":  ("AND",  ["A", "B"]),
    "$_NAND_": ("NAND", ["A", "B"]),
    "$_OR_":   ("OR",   ["A", "B"]),
    "$_NOR_":  ("NOR",  ["A", "B"]),
    "$_XOR_":  ("XOR",  ["A", "B"]),
    "$_XNOR_": ("XNOR", ["A", "B"]),
}


def convert(source, destination, top, capture):
    design = json.loads(
        Path(source).read_text(encoding="utf-8-sig")
    )

    module = design["modules"][top]
    ports = module["ports"]

    # Capture: reset khong kich hoat, scan_en = 0.
    fixed = {}

    if capture:
        for name in ("rst", "scan_en"):
            port = ports[name]

            if port["direction"] != "input" or len(port["bits"]) != 1:
                raise ValueError(f"{name} must be a one-bit input")

            fixed[port["bits"][0]] = "0"

    # Chuyen ID bit Yosys thanh ten net BENCH.
    def net(bit):
        if bit in fixed:
            return fixed[bit]

        if isinstance(bit, int):
            return f"n{bit}"

        if bit in ("0", "1"):
            return bit

        raise ValueError(f"Unsupported constant: {bit}")

    def pin(cell, name):
        bits = cell["connections"][name]

        if len(bits) != 1:
            raise ValueError(f"Pin {name} is not one bit")

        return bits[0]

    equations = []
    used = set()
    driven = set()
    clocks = set()
    count_ff = 0

    for name, cell in module["cells"].items():
        kind = cell["type"]

        # Metadata, khong phai cong logic.
        if kind == "$scopeinfo":
            if cell.get("connections"):
                raise ValueError("Unexpected scopeinfo connections")
            continue

        if kind == "$_DFF_P_":
            output = net(pin(cell, "Q"))
            args = [net(pin(cell, "D"))]
            operation = "DFF"

            clocks.add(pin(cell, "C"))
            count_ff += 1

        elif kind in GATES:
            operation, names = GATES[kind]
            output = net(pin(cell, "Y"))
            args = [net(pin(cell, p)) for p in names]

        else:
            # Khong bo qua cell la vi se lam sai mach.
            raise ValueError(f"Unsupported cell {kind}: {name}")

        if output in driven or output in ("0", "1"):
            raise ValueError(f"Invalid/multiple driver: {output}")

        driven.add(output)
        used.update(args)

        equations.append(
            f'{output} = {operation}({", ".join(args)})'
        )

    # BENCH nay dung cho phan tich SCOAP, khong mo phong clock.
    if clocks and clocks != set(ports["clk"]["bits"]):
        raise ValueError("Expected only the top clk as DFF clock")

    if any(net(bit) in used for bit in clocks):
        raise ValueError(
            "Clock is also used as data; manual review required"
        )

    inputs = set()
    outputs = set()
    comments = []

    for name, port in ports.items():
        if port["direction"] not in ("input", "output"):
            raise ValueError("Inout ports are not supported")

        for i, bit in enumerate(port["bits"]):
            label = name if len(port["bits"]) == 1 else f"{name}[{i}]"
            signal = net(bit)

            # Ghi chu de doi chieu ten chan voi ID net.
            comments.append(f"# {label} -> {signal}")

            if port["direction"] == "input":
                if bit not in clocks and bit not in fixed:
                    inputs.add(signal)
            else:
                outputs.add(signal)

    if inputs & driven:
        raise ValueError("Input is also driven by a cell")

    missing = (used | outputs) - inputs - driven - {"0", "1"}

    if missing:
        raise ValueError(f"Undriven nets: {sorted(missing)}")

    lines = [
        "# Converted Yosys netlist for scoap.py",
        "# DFF clock/reset semantics are not simulated by BENCH.",
        (
            "# Capture: rst=0, scan_en=0"
            if capture else
            "# Controls remain primary inputs"
        ),
        "# Gate topology retained; constants are not propagated.",
    ]

    lines += comments
    lines += [f"INPUT({n})" for n in sorted(inputs)]
    lines += [f"OUTPUT({n})" for n in sorted(outputs)]
    lines += equations

    Path(destination).write_text(
        "\n".join(lines) + "\n",
        encoding="utf-8",
    )

    print(
        f"Saved {destination}: "
        f"{count_ff} DFFs, {len(equations) - count_ff} gates"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Convert supported Yosys JSON cells to BENCH"
    )

    parser.add_argument("source")
    parser.add_argument("destination")
    parser.add_argument("--top", default="uart_tx_scan")
    parser.add_argument("--capture", action="store_true")

    args = parser.parse_args()

    try:
        convert(
            args.source,
            args.destination,
            args.top,
            args.capture,
        )
    except (OSError, ValueError, KeyError) as error:
        parser.exit(1, f"ERROR: {error}\n")