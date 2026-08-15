"""
*** CUIDADO, CÓDIGO FEIO ***
Gerado pelo Claude para validar decisões de projeto

Repete o teste anterior, mas agora pro caso N < K na reindexacao (arvore
NAO enche o cache de saida) -- caso plausivel pra produtos no comeco de
vida do negocio, ou sempre verdade pra clientes (500 de cache, "algumas
centenas" de clientes).

Pergunta: apos reindexar com N < K, conforme o total cresce (insercoes
organicas) e ultrapassa K, alguma insercao NAO cacheada (RRN > K) pousa
mais rasa que nos ja cacheados?
"""
from collections import deque
import random

def build_tree_edges(lo, hi):
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

def largura_rrn(root, nodes):
    rrn = {}
    depth = {}
    counter = 1
    rrn[root] = counter; depth[root] = 0; counter += 1
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

N = 3000     # < K -- reindexacao NAO enche o cache
K = 5041
root, nodes = build_tree_edges(1, N)
rrn, depth = largura_rrn(root, nodes)

left_ptr = {}
right_ptr = {}
key_of = {}
for rank, (esq, dir_) in nodes.items():
    r = rrn[rank]
    left_ptr[r] = rrn[esq] if esq is not None else 0
    right_ptr[r] = rrn[dir_] if dir_ is not None else 0
    key_of[r] = rank * 10

max_depth_original = max(depth.values())
# quantos "buracos" (filho ausente) existem em cada profundidade, na arvore original
gaps_by_depth = {}
for r, d in depth.items():
    if left_ptr[r] == 0:
        gaps_by_depth[d + 1] = gaps_by_depth.get(d + 1, 0) + 1
    if right_ptr[r] == 0:
        gaps_by_depth[d + 1] = gaps_by_depth.get(d + 1, 0) + 1

print(f"Reindexacao com N={N} < K={K} (arvore nao enche o cache)")
print(f"Profundidade maxima da arvore original: {max_depth_original}")
print(f"Buracos (posicoes livres p/ insercao) por profundidade na arvore original:")
for d in sorted(gaps_by_depth):
    print(f"  profundidade {d}: {gaps_by_depth[d]} buracos")
print()

random.seed(7)
next_rrn = N + 1
root_rrn = rrn[root]
pousos = []  # (rrn, profundidade, cacheado?)
M = 6000     # insercoes organicas suficientes p/ passar de K e sobrar
for i in range(M):
    nova_chave = random.uniform(0, N * 10)
    atual = root_rrn
    d = 0
    while True:
        if nova_chave < key_of[atual]:
            prox = left_ptr[atual]; vai_esquerda = True
        else:
            prox = right_ptr[atual]; vai_esquerda = False
        if prox == 0:
            break
        atual = prox
        d += 1
    novo_rrn = next_rrn
    next_rrn += 1
    if vai_esquerda:
        left_ptr[atual] = novo_rrn
    else:
        right_ptr[atual] = novo_rrn
    left_ptr[novo_rrn] = 0
    right_ptr[novo_rrn] = 0
    key_of[novo_rrn] = nova_chave
    cacheado = novo_rrn <= K
    pousos.append((novo_rrn, d + 1, cacheado))

nao_cacheados = [(r, d) for r, d, c in pousos if not c]
cacheados_organicos = [(r, d) for r, d, c in pousos if c]

print(f"{M} insercoes organicas simuladas (RRN {N+1}..{next_rrn-1})")
print(f"Das quais {len(cacheados_organicos)} cacheadas (RRN<=K) e {len(nao_cacheados)} fora do cache (RRN>K)")
print()
if nao_cacheados:
    prof_min_nao_cacheado = min(d for r, d in nao_cacheados)
    prof_max_cacheado_organico = max((d for r, d in cacheados_organicos), default=0)
    print(f"Profundidade minima entre os NAO cacheados: {prof_min_nao_cacheado}")
    print(f"Profundidade maxima entre os cacheados organicos (RRN>N, RRN<=K): {prof_max_cacheado_organico}")
    print(f"Profundidade maxima da arvore original (todos cacheados, RRN<=N): {max_depth_original}")
    problema = prof_min_nao_cacheado <= max_depth_original
    print()
    print(f"Existe no NAO cacheado tao raso quanto (ou mais que) a arvore original cacheada? "
          f"{'SIM -- invariante quebra perto do topo' if problema else 'NAO'}")
    # quantos nao-cacheados sao mais rasos que a profundidade maxima ORIGINAL (garantidamente cacheada)
    rasos_demais = [d for r, d in nao_cacheados if d <= max_depth_original]
    print(f"Quantidade de nos NAO cacheados com profundidade <= {max_depth_original} "
          f"(prof. maxima da arvore original 100% cacheada): {len(rasos_demais)} de {len(nao_cacheados)}")
