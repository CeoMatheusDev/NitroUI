# NitroUI — Etapa 26.2: preenchimento do espaço restante

## Contrato

`layout.Stack.nextFillRemaining(cross_size: f32)` reserva a extensão ainda disponível no eixo principal da região ativa. `cross_size` é sempre explícito: largura em região vertical, altura em região horizontal. Não altera os contratos de `next` ou `nextAligned` e não redistribui elementos já posicionados. Espaçamento entre itens é respeitado. Regiões já excedidas ou dimensões transversais maiores que a área interna retornam `error.InvalidSize` sem avanço do cursor. Coordenadas não finitas retornam `error.CoordinateOverflow`.

`Context.nextFillRemainingLayoutRect(cross_size)` expõe a operação somente no estado `building`.

## Arquivos

- `src/layout.zig`: nova operação e dois testes de regressão.
- `src/root.zig`: wrapper no contexto e teste de estado do frame.
- `src/text.zig`: correção de teste de overflow não determinístico introduzido na etapa 25.3; agora utiliza soma de dois valores finitos que excede `f32`.

## Memória e desempenho

O(1) por reserva, sem novas alocações ou buffers, preservando a pilha de regiões existente. Nenhum benchmark foi executado.

## Validação

Inspeção estática e empacotamento ZIP. Zig 0.17.0 não disponível: compilação, `zig fmt`, testes Debug/ReleaseFast e integração **não executados**. Não publicar sem validação.

## Limitações

Preenchimento não é flexbox: não há distribuição proporcional, reflow, clipping implícito nem layout responsivo automático. A validade dos retângulos gerados deve ser respeitada pelo chamador e pelo renderer da engine.
