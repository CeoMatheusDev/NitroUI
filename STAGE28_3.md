# Etapa 28.3 — Preflight de capacidade da navegação

## Alteração

`interaction.State.item()` agora valida a capacidade do buffer de navegação atual e o contador da ordem anterior **antes** de registrar o ID no armazenamento de diagnóstico ou resolver Tab. Antes, uma falha `NavigationCapacity` podia ocorrer depois de incrementar `visited_count`, deixando o ID rejeitado registrado e produzindo `DuplicateId` em uma tentativa posterior no mesmo frame.

## Testes acrescentados

- Exaustão do buffer de navegação com rastreamento de IDs ativado: verifica contadores inalterados, foco preservado e recuperação no próximo frame.
- `previous_count` inválido: verifica rejeição antes de mutação e recuperação após correção.

## Limitações

A política de widgets desabilitados, o comportamento de widgets removidos da ordem anterior e o isolamento completo dos efeitos colaterais de `item()` em todas as falhas permanecem pendentes. A ordem anterior e a atual precisam de armazenamento disjunto fornecido pela engine; o contrato de não sobreposição ainda não é verificado em runtime.

## Validação

ZIP criado localmente. Não foi possível executar `zig fmt`, compilar, testar ou executar benchmarks porque Zig 0.17.0 não está disponível neste ambiente. Não publicar sem validar Debug e ReleaseFast.
