# Etapa 24.4 — Contrato de leitura de DrawData

## Alterações

- `draw.View`: três slices `[]const`, apenas com os elementos emitidos.
- `draw.Buffer.view()`: converte os contadores em slices de leitura sem cópia.
- `Context.drawDataView()`: disponibiliza a view somente no estado `ready`.
- `Context.drawData()` permanece disponível e sem mudança de assinatura para preservar compatibilidade; seu retorno ainda contém slices mutáveis (API legada).
- Dois testes verificam estados do frame, ausência de geometria, contagens e identidade dos buffers.

## Contrato de ownership e ciclo de vida

A engine fornece e mantém a propriedade dos buffers. A view é emprestada e só pode ser consumida entre `endFrame()` e `releaseFrame()`. Depois de `releaseFrame()`, slices previamente obtidos devem ser considerados inválidos pelo contrato, mesmo que o endereço de memória não tenha mudado. A engine não deve modificar nem reutilizar a memória enquanto estiver consumindo a view. Para renderização assíncrona, a engine deve manter armazenamento independente ou aguardar a conclusão do consumo antes de liberar o frame.

`[]const` impede a escrita *através da view*, mas não fornece isolamento contra aliases mutáveis. `drawData()` legado permanece por compatibilidade e deverá ter sua política de descontinuação discutida antes da versão 0.2.0.

## Validação

A implementação não foi compilada nem testada com Zig 0.17.0 neste ambiente. Executar `zig fmt`, `zig build test --summary all`, `zig test src/root.zig` e `zig build bench -Doptimize=ReleaseFast` no Fedora.
