"""
*** CUIDADO, CÓDIGO FEIO ***
Gerado pelo Claude para validar decisões de projeto

Reindexando com N na "zona de perigo" original (5041<N<8191), sera que
K=5041 arrisca ALGUM no de profundidade<=11 (o que K=4095 garante)?
Ou os ~946 slots extras (4096-5041) sao sempre lucro liquido, sem risco,
porque profundidade<=11 ja esta garantida assim que N>=4095?
"""
from collections import deque
import random

def build_tree_edges(lo, hi):
    nodes = {}
    def rec(lo, hi):
        if hi < lo: return None
        mid = (lo + hi) // 2
        esq = rec(lo, mid - 1); dir_ = rec(mid + 1, hi)
        nodes[mid] = (esq, dir_)
        return mid
    root = rec(lo, hi)
    return root, nodes

def largura_rrn(root, nodes):
    rrn = {}; depth = {}; counter = 1
    rrn[root] = counter; depth[root] = 0; counter += 1
    q = deque([root])
    while q:
        node = q.popleft()
        esq, dir_ = nodes[node]
        for filho in (esq, dir_):
            if filho is not None:
                rrn[filho] = counter; depth[filho] = depth[node] + 1
                counter += 1; q.append(filho)
    return rrn, depth

def testa(N0, M, K, seed=99):
    random.seed(seed)
    root, nodes = build_tree_edges(1, N0)
    rrn, depth = largura_rrn(root, nodes)
    left_ptr, right_ptr, key_of = {}, {}, {}
    for rank, (esq, dir_) in nodes.items():
        r = rrn[rank]
        left_ptr[r] = rrn[esq] if esq is not None else 0
        right_ptr[r] = rrn[dir_] if dir_ is not None else 0
        key_of[r] = rank * 10
    root_rrn = rrn[root]
    next_rrn = N0 + 1

    # PROFUNDIDADE 11 (o que K=4095 garante) esta completa na propria reindexacao?
    nivel_11_completo = sum(1 for d in depth.values() if d == 11) == 2048

    problematicos_prof11 = 0
    for i in range(M):
        nova_chave = random.uniform(0, N0 * 10)
        atual, d = root_rrn, 0
        while True:
            if nova_chave < key_of[atual]:
                prox = left_ptr[atual]; vai_esq = True
            else:
                prox = right_ptr[atual]; vai_esq = False
            if prox == 0: break
            atual = prox; d += 1
        novo_rrn = next_rrn; next_rrn += 1
        if vai_esq: left_ptr[atual] = novo_rrn
        else: right_ptr[atual] = novo_rrn
        left_ptr[novo_rrn] = 0; right_ptr[novo_rrn] = 0
        key_of[novo_rrn] = nova_chave
        profundidade = d + 1
        if novo_rrn > K and profundidade <= 11:
            problematicos_prof11 += 1
    return problematicos_prof11, nivel_11_completo

N0 = 6616  # zona de perigo ORIGINAL (pro nivel 12), mas nivel 11 ja completo
M = 4000
print(f"Reindexando em N0={N0} (nivel 11 completo? checando...), {M} insercoes depois\n")
for K in (4095, 5041):
    probs, nivel11_ok = testa(N0, M, K)
    print(f"K={K}: nivel 11 100% completo na reindexacao = {nivel11_ok} | "
          f"insercoes com profundidade<=11 E fora do cache = {probs} de {M}")
