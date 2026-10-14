# Etapa 28.6 — Elegibilidade explícita

- `interaction.State.itemEnabled(id, rect, snapshot, enabled)` adiciona submissão de item desabilitado sem modificar a assinatura de `item()`.
- `Context.interactEnabled(id, rect, enabled)` expõe o contrato durante o estado `building`.
- Itens desabilitados continuam registrados no diagnóstico opcional de IDs, mas não ocupam a ordem de navegação, não recebem hover/capture/foco e limpam foco/capture anterior do próprio ID.
- `item()` preserva o comportamento anterior delegando com `enabled = true`.
- Dois testes foram escritos; **não executados** (Zig 0.17.0 indisponível).

## Limitações

A navegação Tab ainda usa a ordem anterior; quando a elegibilidade muda entre frames, pode selecionar um ID que será desabilitado no frame atual, e o foco será descartado ao submeter esse item. Pular esse ID no mesmo evento exige um contrato adicional para a lista anterior de elegibilidade. A API de widgets de alto nível ainda não recebe `enabled`; integração posterior deve evitar registrar um mesmo ID duas vezes. A busca linear de duplicados permanece O(n²) no pior caso por frame.

Não houve benchmark, compilação, alteração de versão ou publicação remota.
