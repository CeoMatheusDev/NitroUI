# Etapa 24.5 — Diagnóstico opcional de IDs duplicados

`interaction.State.setIdTrackingStorage(?[]ids.Id)` e `Context.setInteractionIdStorage(?[]ids.Id)` aceitam armazenamento fornecido pela engine, configurado fora do frame. Com armazenamento ativo, toda submissão de `interact` (inclusive widgets não hovered) é registrada, e duplicatas retornam `error.DuplicateId`. Se a capacidade se esgotar, retorna `error.IdTrackingCapacity` sem registrar o item. A contagem é reiniciada a cada `beginFrame`.

O diagnóstico é **opcional** e usa busca linear O(n) por submissão, O(n²) por frame; adequado para depuração com poucos itens, **não recomendado para cargas grandes**. Sem armazenamento, permanece o comportamento anterior: apenas IDs hovered/ativos repetidos são detectados. Nenhuma alocação é feita. O checkpoint de widget restaura `visited_count` em caso de falha, junto aos demais estados.

IDs são valores `u64` derivados de escopos pelo módulo `ids.zig`; escopos diferentes geram IDs distintos. Não há garantia criptográfica de ausência de colisões de hash. O armazenamento precisa permanecer válido até a desativação. A engine não deve modificar a memória enquanto o diagnóstico estiver ativo.

Validação local com Zig 0.17.0 pendente; executar `zig fmt build.zig src bench`, `zig build test --summary all`, `zig test src/root.zig`, `zig build bench -Doptimize=ReleaseFast`.
