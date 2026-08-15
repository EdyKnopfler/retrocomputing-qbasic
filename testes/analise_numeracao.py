#!/usr/bin/env python3
"""
*** CUIDADO, CÓDIGO FEIO ***
Gerado pelo Claude para validar decisões de projeto

Experimento: comparar numeracao de RRN em pre-ordem vs largura, pra
reconstrucao por bissecao do indice (docs/reindexacao.md).

Mede, com numeros de verdade (nao Big-O abstrato):
1. Cobertura de cache: dos primeiros K RRN, quantos nos de cada
   profundidade da arvore real sao capturados.
2. Distancia de salto pai->filho em RRN, por profundidade (proxy de
   custo de seek quando o no esta fora do cache).
3. Se a formula "mid = ceil((lo+hi)/2)" reproduz o formato de heap
   (alegacao que foi escrita nos docs e que precisa ser verificada).
"""
import sys
from collections import deque

sys.setrecursionlimit(10000)


def build_tree(lo, hi):
    """Bisseciona [lo,hi] (1-indexed, dump ordenado) com mid = (lo+hi)//2,
    a formula simples usada desde o primeiro turno. Devolve dict de
    no -> (lo,hi,filho_esq,filho_dir), onde cada no e identificado pela
    posicao no dump (seu rank, 1..N) -- so pra dar nome unico ao no,
    NAO e o RRN de saida (esse e calculado depois, separadamente)."""
    nodes = {}

    def rec(lo, hi):
        if hi < lo:
            return None
        mid = (lo + hi) // 2
        esq = rec(lo, mid - 1)
        dir_ = rec(mid + 1, hi)
        nodes[mid] = (esq, dir_)
        return mid

    root = rec(lo, hi)
    return root, nodes


def preorder_rrn(root, nodes, n):
    """RRN por aritmetica de pre-ordem: base+1 / base+1+tamanhoEsq."""
    rrn = {}
    depth = {}

    def size(node):
        if node is None:
            return 0
        esq, dir_ = nodes[node]
        return 1 + size(esq) + size(dir_)

    def rec(node, base, d):
        if node is None:
            return
        rrn[node] = base
        depth[node] = d
        esq, dir_ = nodes[node]
        tam_esq = size(esq)
        rec(esq, base + 1, d + 1)
        rec(dir_, base + 1 + tam_esq, d + 1)

    rec(root, 1, 0)
    return rrn, depth


def largura_rrn(root, nodes, n):
    """RRN atribuido na hora de ENFILEIRAR (fila real, BFS)."""
    rrn = {}
    depth = {}
    counter = 1
    rrn[root] = counter
    depth[root] = 0
    counter += 1
    q = deque([root])
    while q:
        node = q.popleft()
        esq, dir_ = nodes[node]
        for filho in (esq, dir_):
            if filho is not None:
                rrn[filho] = counter
                depth[filho] = depth[node] + 1
                counter += 1
                q.append(filho)
    return rrn, depth


def coverage_by_depth(nodes, root, rrn, depth, K):
    """Pra cada profundidade, fracao de nos capturados em RRN<=K."""
    total_by_depth = {}
    covered_by_depth = {}
    for node, d in depth.items():
        total_by_depth[d] = total_by_depth.get(d, 0) + 1
        if rrn[node] <= K:
            covered_by_depth[d] = covered_by_depth.get(d, 0) + 1
    return total_by_depth, covered_by_depth


def hop_distance_by_depth(nodes, rrn, depth):
    """Distancia |RRN_filho - RRN_pai| media, por profundidade do FILHO."""
    dist_by_depth = {}
    for node, (esq, dir_) in nodes.items():
        for filho in (esq, dir_):
            if filho is not None:
                d = depth[filho]
                dist = abs(rrn[filho] - rrn[node])
                dist_by_depth.setdefault(d, []).append(dist)
    return dist_by_depth


def heap_split_correto(n):
    """Formula CORRETA de tamanho de subarvore esquerda/direita pra
    arvore completa (heap-shape) com n nos totais (raiz + resto)."""
    if n <= 1:
        return 0, 0
    remaining = n - 1
    D = remaining.bit_length()  # menor D tal que 2^D - 1 >= remaining, aprox
    while (1 << D) - 1 < remaining:
        D += 1
    while D > 0 and (1 << (D - 1)) - 1 >= remaining:
        D -= 1
    extra = remaining - ((1 << D) - 1)
    half = 1 << (D - 1) if D > 0 else 0
    left = ((1 << (D - 1)) - 1 if D > 0 else 0) + min(extra, half)
    right = ((1 << (D - 1)) - 1 if D > 0 else 0) + max(0, extra - half)
    return left, right


def ceil_mid_split(n):
    """Formula que foi ESCRITA NOS DOCS: mid = ceil((1+n)/2)."""
    lo, hi = 1, n
    mid = -(-(lo + hi) // 2)  # ceil division
    return mid - lo, hi - mid


print("=" * 70)
print("1) A formula 'mid = ceil((lo+hi)/2)' reproduz o formato de heap?")
print("=" * 70)
mismatches = []
for n in range(1, 200):
    correto = heap_split_correto(n)
    chutado = ceil_mid_split(n)
    status = "OK" if correto == chutado else "DIVERGE"
    if correto != chutado:
        mismatches.append((n, correto, chutado))
print(f"Testado N=1..199: {len(mismatches)} divergencias de {199} casos")
print("Primeiras 10 divergencias (N, split_correto_heap, split_ceil_mid):")
for n, c, ch in mismatches[:10]:
    print(f"  N={n}: heap correto={c}  ceil-mid (doc)={ch}")

print()
print("=" * 70)
print("2) Cobertura de cache: pre-ordem vs largura")
print("=" * 70)
N = 12000       # "algumas milhares" de produtos
K = 5041        # capacidadeCacheProduto% (docs/decisoes.md)
root, nodes = build_tree(1, N)
rrn_pre, depth_pre = preorder_rrn(root, nodes, N)
rrn_larg, depth_larg = largura_rrn(root, nodes, N)

print(f"N={N} produtos, cache K={K}\n")

for nome, rrn, depth in [("PRE-ORDEM", rrn_pre, depth_pre),
                          ("LARGURA", rrn_larg, depth_larg)]:
    total_d, cov_d = coverage_by_depth(nodes, root, rrn, depth, K)
    max_depth = max(total_d)
    print(f"--- {nome} ---")
    print(f"{'prof':>5} {'nos_no_nivel':>13} {'cobertos_RRN<=K':>16} {'%':>7}")
    for d in range(0, max_depth + 1):
        tot = total_d.get(d, 0)
        cov = cov_d.get(d, 0)
        pct = 100.0 * cov / tot if tot else 0.0
        marcador = "" if pct in (0.0, 100.0) else "  <-- nivel PARCIALMENTE coberto"
        print(f"{d:>5} {tot:>13} {cov:>16} {pct:>6.1f}%{marcador}")
    print()

print("=" * 70)
print("3) Distancia de salto pai->filho (RRN), por profundidade")
print("=" * 70)
for nome, rrn, depth in [("PRE-ORDEM", rrn_pre, depth_pre),
                          ("LARGURA", rrn_larg, depth_larg)]:
    dist_d = hop_distance_by_depth(nodes, rrn, depth)
    print(f"--- {nome} ---")
    print(f"{'prof_filho':>10} {'salto_medio':>12} {'salto_max':>10} {'n_saltos':>9}")
    for d in sorted(dist_d):
        vals = dist_d[d]
        media = sum(vals) / len(vals)
        print(f"{d:>10} {media:>12.1f} {max(vals):>10} {len(vals):>9}")
    print()
