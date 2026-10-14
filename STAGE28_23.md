# Etapa 28.23 — Progresso de eventos no widget visual

## Contrato

Nova API opt-in `Context.inputTextDraggedTracked(...)`, com `*text_input.Progress` pertencente à aplicação. As APIs anteriores são preservadas e reutilizam o mesmo processamento interno. O progresso é reinicializado no início da chamada e atualizado pelo `text_input.applyTracked` após o hit testing, antes da emissão de geometria.

- Falha anterior ao processamento de eventos: `consumed == 0`, `changes == 0`.
- Falha de edição: prefixo consumido e estado de modificadores/foco são preservados; evento com erro não é consumido.
- Falha de renderização: progresso completo permanece observável, mesmo que a geometria/interação sejam revertidas.
- Texto e seleção continuam pertencendo à aplicação; edições anteriores à falha são mantidas.
- A engine não deve reenviar eventos do prefixo consumido. O progresso **não** inclui interações por mouse.
- Não existe rollback de texto nem transação global de lote; os dados de `Progress` não devem ser interpretados como garantia de desenho.

## Arquivos

- `src/root.zig`: API tracked e implementação compartilhada.
- `STAGE28_23.md`: documentação.

## Validação

Verificação estática de assinatura e integridade do arquivo ZIP. Compilação Zig 0.17.0, testes e benchmarks não executados: compilador ausente. A integração com uma engine real permanece pendente.

## Pendências

Testes integrados com buffers de geometria insuficientes e eventos parciais; testes Debug/ReleaseFast; composição IME; clusters de grafemas; métricas de performance.
