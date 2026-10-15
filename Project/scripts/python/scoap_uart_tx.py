
import argparse
import csv
import heapq
import json
import math
from collections import defaultdict
from pathlib import Path

INF = math.inf
GATES = {
    '$_NOT_': ('NOT', ['A']), '$_BUF_': ('BUF', ['A']),
    '$_AND_': ('AND', ['A', 'B']), '$_NAND_': ('NAND', ['A', 'B']),
    '$_OR_': ('OR', ['A', 'B']), '$_NOR_': ('NOR', ['A', 'B']),
    '$_XOR_': ('XOR', ['A', 'B']), '$_XNOR_': ('XNOR', ['A', 'B']),
}

def gate_cc(kind, ins, cc):
    vals = [cc[x] for x in ins]
    if kind == 'BUF': return vals[0][0]+1, vals[0][1]+1
    if kind == 'NOT': return vals[0][1]+1, vals[0][0]+1
    if kind in ('AND', 'NAND'):
        a, b = min(v[0] for v in vals)+1, sum(v[1] for v in vals)+1
    elif kind in ('OR', 'NOR'):
        a, b = sum(v[0] for v in vals)+1, min(v[1] for v in vals)+1
    elif kind in ('XOR', 'XNOR'):
        even, odd = 0, INF
        for c0, c1 in vals:
            even, odd = min(even+c0, odd+c1), min(even+c1, odd+c0)
        a, b = even+1, odd+1
    else: raise ValueError('Unsupported gate: '+kind)
    return (b, a) if kind in ('NAND', 'NOR', 'XNOR') else (a, b)

def side_cost(kind, ins, cc):
    if kind in ('AND', 'NAND'): return sum(cc[x][1] for x in ins)
    if kind in ('OR', 'NOR'): return sum(cc[x][0] for x in ins)
    if kind in ('XOR', 'XNOR'): return sum(min(cc[x]) for x in ins)
    return 0

def analyze(module, reset_name='rst'):
    ports = module['ports']
    fixed = {}
    if reset_name:
        if reset_name not in ports or ports[reset_name]['direction'] != 'input' or len(ports[reset_name]['bits']) != 1:
            raise ValueError('Inactive reset must be a scalar input')
        fixed[ports[reset_name]['bits'][0]] = '0'
    def net(bit):
        if bit in fixed: return fixed[bit]
        if isinstance(bit, int): return 'n'+str(bit)
        if bit in ('0', '1'): return bit
        raise ValueError('X/Z or unsupported constant: '+str(bit))
    def pin(cell, p):
        bits = cell['connections'][p]
        if len(bits) != 1: raise ValueError('Only single-bit mapped cells supported')
        return bits[0]
    ffs, gates, clocks = [], [], set()
    for name, cell in module['cells'].items():
        typ = cell['type']
        if typ == '$scopeinfo':
            if cell.get('connections'): raise ValueError('Unexpected scopeinfo connections')
            continue
        if typ == '$_DFF_P_':
            ffs.append((name, net(pin(cell,'D')), net(pin(cell,'Q')), pin(cell,'Q')))
            clocks.add(pin(cell,'C'))
        elif typ in GATES:
            kind, pins = GATES[typ]
            gates.append((net(pin(cell,'Y')), kind, [net(pin(cell,p)) for p in pins]))
        else: raise ValueError('Unsupported cell '+typ+' at '+name)
    if clocks and clocks != set(ports.get('clk',{}).get('bits',[])):
        raise ValueError('Expected only top-level clk as DFF clock')
    pi, po = set(), set()
    aliases = defaultdict(set)
    for name, info in module.get('netnames',{}).items():
        if info.get('hide_name') or name.startswith('$'): continue
        bits = info['bits']; offset = info.get('offset',0)
        for i, bit in enumerate(bits):
            label = name if len(bits)==1 else f'{name}[{offset+i}]'
            aliases[bit].add(label)
    for name, port in ports.items():
        if port['direction'] not in ('input','output'): raise ValueError('Inout unsupported')
        for bit in port['bits']:
            if port['direction']=='output': po.add(net(bit))
            elif bit not in clocks and bit not in fixed: pi.add(net(bit))
    qs = {q for _,d,q,b in ffs}; ds = {d for _,d,q,b in ffs}
    drivers = {}
    for i,(out,kind,ins) in enumerate(gates):
        if out in drivers or out in pi|qs|{'0','1'}: raise ValueError('Multiple/invalid driver: '+out)
        drivers[out] = i
    if len(qs) != len(ffs): raise ValueError('Multiple DFF drivers')
    nodes = pi|po|qs|ds
    for out,kind,ins in gates: nodes.add(out); nodes.update(ins)
    missing = nodes - pi - qs - set(drivers) - {'0','1'}
    if missing: raise ValueError('Undriven nodes: '+str(sorted(missing)))
    clock_nets = {net(c) for c in clocks}
    if any(clock_nets.intersection(ins) for _,_,ins in gates) or clock_nets & ds:
        raise ValueError('Clock also used as data')
    successors = defaultdict(set); indegree=[]
    for i,(_,_,ins) in enumerate(gates):
        deps={drivers[n] for n in ins if n in drivers}; indegree.append(len(deps))
        for dep in deps: successors[dep].add(i)
    ready=[i for i,v in enumerate(indegree) if v==0]; heapq.heapify(ready); ordered=[]
    while ready:
        i=heapq.heappop(ready); ordered.append(gates[i])
        for j in successors[i]:
            indegree[j]-=1
            if indegree[j]==0: heapq.heappush(ready,j)
    if len(ordered)!=len(gates): raise ValueError('Combinational loop after DFF cut')
    cc={'0':(0,INF),'1':(INF,0)}
    cc.update({n:(1,1) for n in pi|qs})
    for out,kind,ins in ordered: cc[out]=gate_cc(kind,ins,cc)
    co={n:INF for n in nodes}
    for n in po|ds: co[n]=0
    for out,kind,ins in reversed(ordered):
        for i,n in enumerate(ins):
            co[n]=min(co[n],co[out]+side_cost(kind,ins[:i]+ins[i+1:],cc)+1)
    roles=defaultdict(set)
    for tag, group in [('PI',pi),('PO',po),('PPI_Q',qs),('PPO_D',ds)]:
        for n in group: roles[n].add(tag)
    node_rows=[]
    for n in sorted(nodes):
        bit=int(n[1:]) if n.startswith('n') else n
        node_rows.append(dict(node=n,names='|'.join(sorted(aliases.get(bit,[]))),
                              role='|'.join(sorted(roles[n])) or 'INTERNAL',
                              CC0=cc[n][0],CC1=cc[n][1],CO=co[n]))
    ff_rows=[]
    for cell,d,q,bit in ffs:
        labels=sorted(aliases.get(bit,[]),key=lambda s:(len(s),s))
        ff_rows.append(dict(register=labels[0] if labels else q,aliases='|'.join(labels),
                            cell=cell,D=d,Q=q,CC0_D=cc[d][0],CC1_D=cc[d][1],CO_Q=co[q],
                            score=max(cc[d])+co[q]))
    ff_rows.sort(key=lambda r:(-r['score'],r['register']))
    previous=None; rank=0
    for i,r in enumerate(ff_rows,1):
        if r['score']!=previous: rank=i
        r['rank']=rank; previous=r['score']
    return node_rows,ff_rows,len(gates)

def number(x):
    return 'INF' if isinstance(x,(float,int)) and math.isinf(x) else x

def write_csv(path,rows,fields):
    with path.open('w',newline='',encoding='utf-8-sig') as f:
        w=csv.DictWriter(f,fieldnames=fields); w.writeheader()
        w.writerows({k:number(v) for k,v in row.items()} for row in rows)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('netlist',type=Path)
    p.add_argument('--top',default='uart_tx')
    p.add_argument('--out-dir',type=Path,default=Path('results'))
    p.add_argument('--prefix',default='tx_baseline')
    p.add_argument('--reset',default='rst',help='Active-high reset constrained to 0; empty string leaves all controls free')
    a=p.parse_args()
    try:
        design=json.loads(a.netlist.read_text(encoding='utf-8-sig'))
        nodes,ffs,gate_count=analyze(design['modules'][a.top],a.reset)
        a.out_dir.mkdir(parents=True,exist_ok=True)
        np=a.out_dir/(a.prefix+'_scoap_nodes.csv'); fp=a.out_dir/(a.prefix+'_scoap_ff.csv')
        write_csv(np,nodes,['node','names','role','CC0','CC1','CO'])
        write_csv(fp,ffs,['register','aliases','cell','D','Q','CC0_D','CC1_D','CO_Q','score','rank'])
    except (ValueError,KeyError,OSError) as e: p.exit(1,'ERROR: '+str(e)+'\n')
    print('MODEL: ALL DFFs cut; combinational SCOAP, not sequential SCOAP')
    print('Reset constraint:',(a.reset+'=0') if a.reset else 'none')
    print('DFFs:',len(ffs),' Gates:',gate_count,' Nodes:',len(nodes))
    print('Score heuristic: max(CC0(D), CC1(D)) + CO(Q); higher first')
    print(f'{"REGISTER":<20} {"CC0_D":>7} {"CC1_D":>7} {"CO_Q":>7} {"SCORE":>7} {"RANK":>6}')
    for r in ffs:
        print(f'{r["register"]:<20} {str(number(r["CC0_D"])):>7} {str(number(r["CC1_D"])):>7} {str(number(r["CO_Q"])):>7} {str(number(r["score"])):>7} {r["rank"]:>6}')
    print('Saved:',np); print('Saved:',fp)

if __name__=='__main__': main()
